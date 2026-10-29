defmodule RegentHttp.PublicMessagesTest do
  # Informational (1xx) replies, found in review on 29 Oct: `answer: :headers`
  # acknowledges only on a 2xx's headers, as MCP Events callbacks always have.
  # Runs the module's own source with private functions exported against a
  # plain-TCP Mint connection, since the public-address guard refuses loopback.
  use ExUnit.Case, async: true

  @source Path.expand("../../lib/regent_http/public.ex", __DIR__)
  @mod RegentHttp.PublicUnderTest

  setup_all do
    @source
    |> File.read!()
    |> String.replace(
      "defmodule RegentHttp.Public do",
      "defmodule #{inspect(@mod)} do\n  @compile :export_all",
      global: false
    )
    |> Code.compile_string()

    :ok
  end

  # Starts a server that writes `reply` (a binary, or a function looping on the
  # socket) and returns a Mint conn with the request sent.
  defp request(reply) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)

    Task.start(fn ->
      {:ok, socket} = :gen_tcp.accept(listen)
      {:ok, _request} = :gen_tcp.recv(socket, 0)
      if is_function(reply), do: reply.(socket), else: :gen_tcp.send(socket, reply)
      Process.sleep(300)
      :gen_tcp.close(socket)
    end)

    {:ok, conn} = Mint.HTTP.connect(:http, "127.0.0.1", port, mode: :passive)
    {:ok, conn, ref} = Mint.HTTP.request(conn, "POST", "/", [], "{}")
    {conn, ref}
  end

  defp answer(reply, answer, deadline_ms \\ 1_000) do
    {conn, ref} = request(reply)
    deadline = System.monotonic_time(:millisecond) + deadline_ms
    response = %{status: nil, headers: nil, body: "", answer: answer}
    apply(@mod, :receive_response, [conn, ref, 16_384, deadline, response])
  end

  defp mint_messages(reply) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(listen)

    Task.start(fn ->
      {:ok, socket} = :gen_tcp.accept(listen)
      {:ok, _request} = :gen_tcp.recv(socket, 0)
      :ok = :gen_tcp.send(socket, reply)
      Process.sleep(200)
      :gen_tcp.close(socket)
    end)

    {:ok, conn} = Mint.HTTP.connect(:http, "127.0.0.1", port, mode: :passive)
    {:ok, conn, ref} = Mint.HTTP.request(conn, "POST", "/", [], "{}")
    {:ok, _conn, messages} = Mint.HTTP.recv(conn, 0, 1_000)
    {ref, messages}
  end

  test "endless 1xx replies end at the deadline" do
    flood = fn socket ->
      Enum.each(1..100_000, fn _ ->
        :gen_tcp.send(socket, "HTTP/1.1 103 x\r\nlink: </a>\r\n\r\n")
      end)
    end

    started = System.monotonic_time(:millisecond)
    assert {:error, _} = answer(flood, :headers, 500)
    assert System.monotonic_time(:millisecond) - started < 2_000
  end

  test "a 1xx carrying bytes after its blank line is an error, not an answer" do
    assert {:error, _} = answer("HTTP/1.1 100 Continue\r\ncontent-length: 5\r\n\r\nhello", :body)
  end

  test "2xx and 3xx+ answers after a 1xx are unchanged" do
    early = "HTTP/1.1 103 x\r\nlink: </a>\r\n\r\n"

    assert {:ok, %{status: 200, body: nil}} =
             answer(early <> "HTTP/1.1 200 OK\r\ncontent-length: 2\r\n\r\nok", :headers)

    assert {:ok, %{status: 200, body: "ok", headers: [{"content-length", "2"}]}} =
             answer(early <> "HTTP/1.1 200 OK\r\ncontent-length: 2\r\n\r\nok", :body)

    assert {:ok, %{status: 302, body: ""}} =
             answer(early <> "HTTP/1.1 302 Found\r\nlocation: /x\r\n\r\n", :body)
  end

  # Found in review on 29 Oct: a chunked reply's trailers replaced its headers,
  # so a document's content type and cache lifetime came from the trailers.
  test "a chunked reply's trailers never replace its headers" do
    reply =
      "HTTP/1.1 200 OK\r\ntransfer-encoding: chunked\r\ncontent-type: application/json\r\n\r\n" <>
        "2\r\nok\r\n0\r\nx-late: 1\r\n\r\n"

    assert {:ok, %{status: 200, body: "ok", headers: headers}} = answer(reply, :body)
    assert {"content-type", "application/json"} in headers
  end

  test "101 Switching Protocols is a failed call, never an answer without a status" do
    reply = "HTTP/1.1 101 Switching Protocols\r\nupgrade: x\r\n\r\nraw bytes"
    assert {:error, :connection_error} = answer(reply, :body)
  end

  test "an informational response is never taken as a callback's acknowledgement" do
    {ref, messages} =
      mint_messages(
        "HTTP/1.1 103 Early Hints\r\nlink: </a>; rel=preload\r\n\r\n" <>
          "HTTP/1.1 503 Service Unavailable\r\ncontent-length: 0\r\n\r\n"
      )

    assert [{:status, ^ref, 103}, {:headers, ^ref, _} | _] = messages

    deadline = System.monotonic_time(:millisecond) + 1_000
    response = %{status: nil, headers: nil, body: "", answer: :headers}

    # Taking the 103 as the answer would end an MCP Events subscription that
    # should retry on the final 503.
    assert {:ok, %{status: 503}} =
             apply(@mod, :consume, [
               messages,
               nil,
               ref,
               16_384,
               deadline,
               response
             ])
  end
end

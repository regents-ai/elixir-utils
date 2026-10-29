defmodule RegentHttp.PublicMessagesTest do
  # `answer: :headers` acknowledges only on a 2xx's headers, as MCP Events
  # callbacks always have (found in review of the move onto this module, 29 Oct). Mint reports a 1xx response (103 Early Hints,
  # 100 Continue) as its own {:status, ref, 1xx} and {:headers, ref, _} before
  # the final status, and RegentHttp.Public.consume/6 returns on those headers.
  # A network test cannot reach a loopback server through the public-address
  # guard, so this runs the module's own source with its private functions
  # exported, on the message list Mint really produces.
  use ExUnit.Case, async: true

  @source Path.expand("../../lib/regent_http/public.ex", __DIR__)

  setup_all do
    source =
      @source
      |> File.read!()
      |> String.replace(
        "defmodule RegentHttp.Public do",
        "defmodule RegentHttp.PublicUnderTest do\n  @compile :export_all",
        global: false
      )

    Code.compile_string(source)
    :ok
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

  test "an informational response is never taken as a callback's acknowledgement" do
    {ref, messages} =
      mint_messages(
        "HTTP/1.1 103 Early Hints\r\nlink: </a>; rel=preload\r\n\r\n" <>
          "HTTP/1.1 503 Service Unavailable\r\ncontent-length: 0\r\n\r\n"
      )

    assert [{:status, ^ref, 103}, {:headers, ^ref, _} | _] = messages

    deadline = System.monotonic_time(:millisecond) + 1_000
    response = %{status: nil, headers: [], body: "", answer: :headers}

    # Taking the 103 as the answer would end an MCP Events subscription that
    # should retry on the final 503.
    assert {:ok, %{status: 503}} =
             apply(RegentHttp.PublicUnderTest, :consume, [
               messages,
               nil,
               ref,
               16_384,
               deadline,
               response
             ])
  end
end

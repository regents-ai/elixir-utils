defmodule Siwa.RpcStub do
  @moduledoc false
  # A stand-in for a Base JSON-RPC endpoint on this machine: answers every
  # request with `body` and sends each decoded request to `listener`.

  def start(body, listener \\ nil) do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])
    {:ok, port} = :inet.port(socket)
    pid = spawn_link(fn -> accept_loop(socket, Jason.encode!(body), listener) end)

    ExUnit.Callbacks.on_exit(fn ->
      :gen_tcp.close(socket)
      Process.exit(pid, :shutdown)
    end)

    "http://127.0.0.1:#{port}"
  end

  @doc "A Multicall3 `aggregate3` result holding one `(success, returnData)`."
  def wallet_answers({success, returned}) do
    padding = rem(32 - rem(byte_size(returned), 32), 32)
    success = if success, do: 1, else: 0

    result =
      <<32::256, 1::256, 32::256, success::256, 64::256, byte_size(returned)::256>> <>
        returned <> <<0::size(padding * 8)>>

    rpc_result("0x" <> Base.encode16(result, case: :lower))
  end

  @doc "ERC-1271's approval: the `isValidSignature` selector."
  def erc1271_approval, do: <<0x1626BA7E::32, 0::224>>

  def rpc_result(result), do: %{"jsonrpc" => "2.0", "id" => 1, "result" => result}

  defp accept_loop(socket, body, listener) do
    case :gen_tcp.accept(socket) do
      {:ok, client} ->
        request = read_request(client, "")
        if listener, do: send(listener, {:rpc_request, request})

        :gen_tcp.send(
          client,
          "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\n\r\n#{body}"
        )

        :gen_tcp.close(client)
        accept_loop(socket, body, listener)

      {:error, _closed} ->
        :ok
    end
  end

  defp read_request(client, received) do
    {:ok, data} = :gen_tcp.recv(client, 0, 1_000)
    received = received <> data

    with [head, request_body] <- String.split(received, "\r\n\r\n", parts: 2),
         [_, length] <- Regex.run(~r/content-length: (\d+)/i, head),
         true <- byte_size(request_body) >= String.to_integer(length) do
      Jason.decode!(request_body)
    else
      _incomplete -> read_request(client, received)
    end
  end
end

defmodule Siwa.EthereumTest do
  use ExUnit.Case, async: true

  alias Siwa.Ethereum

  @registry_address "0x3333333333333333333333333333333333333333"
  @owner_address "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266"

  test "normalizes and validates addresses and hashes" do
    assert {:ok, "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266"} =
             Ethereum.normalize_address("  0xF39FD6E51AAD88F6F4CE6AB8827279CFFFB92266  ")

    refute Ethereum.valid_address?("not-an-address")
    assert Ethereum.valid_tx_hash?("0x" <> String.duplicate("a", 64))
    refute Ethereum.valid_tx_hash?("0x1234")
  end

  test "computes deterministic Ethereum hashes" do
    assert {:ok, "0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8"} =
             Ethereum.keccak_hex("hello")

    assert {:ok, "0x0000000000000000000000000000000000000000000000000000000000000000"} =
             Ethereum.namehash("")

    assert {:ok, "0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae"} =
             Ethereum.namehash("eth")

    assert {:ok, "0xde9b09fd7c5f901e23a3f19fecc54828e9c848539801e86591bd9801b019f84f"} =
             Ethereum.namehash("foo.eth")

    assert {:error, :invalid_ens_name} = Ethereum.namehash("foo..eth")
  end

  test "builds and decodes ownerOf calls" do
    assert {:ok, "0x6352211e0000000000000000000000000000000000000000000000000000000000000000"} =
             Ethereum.owner_of_call_data("0")

    assert {:ok, "0x6352211e000000000000000000000000000000000000000000000000000000000000004d"} =
             Ethereum.owner_of_call_data("77")

    assert {:ok, @owner_address} =
             Ethereum.decode_owner_of_result(
               "0x000000000000000000000000" <> String.trim_leading(@owner_address, "0x")
             )
  end

  test "resolves ownerOf through JSON-RPC" do
    rpc_url = rpc_server(fn _request -> rpc_result(owner_result(@owner_address)) end)

    assert {:ok, @owner_address} =
             Ethereum.owner_of(@registry_address, "77", rpc_url, timeout_ms: 100)
  end

  test "maps JSON-RPC failures" do
    rpc_url = rpc_server(fn _request -> %{} end)

    assert {:error, :invalid_rpc_response} =
             Ethereum.json_rpc(rpc_url, "eth_call", [], timeout_ms: 100)
  end

  defp rpc_server(handler) do
    {:ok, listen_socket} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

    {:ok, port} = :inet.port(listen_socket)

    pid =
      spawn_link(fn ->
        accept_loop(listen_socket, handler)
      end)

    ExUnit.Callbacks.on_exit(fn ->
      :gen_tcp.close(listen_socket)
      Process.exit(pid, :shutdown)
    end)

    "http://127.0.0.1:#{port}"
  end

  defp accept_loop(listen_socket, handler) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        {:ok, request} = :gen_tcp.recv(socket, 0, 1_000)
        body = request |> handler.() |> Jason.encode!()

        response =
          "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\n\r\n#{body}"

        :gen_tcp.send(socket, response)
        :gen_tcp.close(socket)
        accept_loop(listen_socket, handler)

      {:error, :closed} ->
        :ok
    end
  end

  defp rpc_result(result), do: %{"jsonrpc" => "2.0", "id" => 1, "result" => result}

  defp owner_result(address) do
    "0x000000000000000000000000" <> String.trim_leading(address, "0x")
  end
end

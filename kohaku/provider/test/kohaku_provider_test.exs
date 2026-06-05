defmodule KohakuProviderTest do
  use ExUnit.Case, async: true

  alias KohakuProvider.TxData

  setup do
    bypass = Bypass.open()
    {:ok, provider} = KohakuProvider.new("http://localhost:#{bypass.port}")
    {:ok, bypass: bypass, provider: provider}
  end

  test "reads chain id from JSON-RPC quantity", %{bypass: bypass, provider: provider} do
    expect_rpc(bypass, "eth_chainId", "0xaa36a7")

    assert {:ok, 11_155_111} = KohakuProvider.get_chain_id(provider)
  end

  test "sends transaction data", %{bypass: bypass, provider: provider} do
    expect_rpc(bypass, "eth_sendTransaction", "0x" <> String.duplicate("1", 64), fn params ->
      assert [
               %{
                 "to" => "0xfff9976782d46cc05630d1f6ebab18b2324d6b14",
                 "data" => "0x1234",
                 "value" => "0x5"
               }
             ] = params
    end)

    assert {:ok, tx} = TxData.new("0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14", "0x1234", 5)
    assert {:ok, "0x" <> _hash} = KohakuProvider.send_transaction(provider, tx)
  end

  test "normalizes receipts", %{bypass: bypass, provider: provider} do
    hash = "0x" <> String.duplicate("2", 64)

    expect_rpc(bypass, "eth_getTransactionReceipt", %{
      "blockNumber" => "0x10",
      "status" => "0x1",
      "gasUsed" => "0x5208",
      "logs" => []
    })

    assert {:ok, receipt} = KohakuProvider.get_transaction_receipt(provider, hash)
    assert receipt.block_number == 16
    assert receipt.status == 1
    assert receipt.gas_used == 21_000
  end

  defp expect_rpc(bypass, expected_method, result, assert_params \\ fn _params -> :ok end) do
    Bypass.expect_once(bypass, "POST", "/", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)
      assert payload["method"] == expected_method
      assert_params.(payload["params"])

      Plug.Conn.resp(
        Plug.Conn.put_resp_content_type(conn, "application/json"),
        200,
        Jason.encode!(%{"jsonrpc" => "2.0", "id" => payload["id"], "result" => result})
      )
    end)
  end
end

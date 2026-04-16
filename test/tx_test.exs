defmodule AgentEns.TxTest do
  use ExUnit.Case, async: true

  alias AgentEns.Tx

  test "builds an ENS setText transaction request" do
    assert {:ok, tx} =
             Tx.build_set_text_tx(%{
               ens_name: "vitalik.eth",
               chain_id: 1,
               registry_address: "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
               agent_id: 42,
               resolver_address: "0x226159d592e2b063810a10ebf6dcbada94ed68b8"
             })

    assert tx.to == "0x226159d592e2b063810a10ebf6dcbada94ed68b8"
    assert tx.chain_id == 1
    assert String.starts_with?(tx.data, "0x10f13a8c")
  end

  test "builds an ERC-8004 setAgentURI transaction request" do
    assert {:ok, tx} =
             Tx.build_set_agent_uri_tx(%{
               chain_id: 1,
               registry_address: "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
               agent_id: 42,
               new_uri: "data:application/json,%7B%7D"
             })

    assert tx.to == "0x8004a169fb4a3325136eb29fa0ceb6d2e539a432"
    assert tx.chain_id == 1
    assert String.starts_with?(tx.data, "0x0af28bd3")
  end

  test "builds a reverse name transaction request" do
    assert {:ok, tx} =
             Tx.build_reverse_set_name_tx(%{
               chain_id: 1,
               ens_name: "vitalik.eth",
               reverse_registrar: "0xa58E81fe9b61B5c3fE2AFD33CF304c454AbFc7Cb"
             })

    assert tx.to == "0xa58e81fe9b61b5c3fe2afd33cf304c454abfc7cb"
    assert tx.chain_id == 1
    assert String.starts_with?(tx.data, "0xc47f0027")
  end
end

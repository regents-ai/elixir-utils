defmodule AgentEns.TxTest do
  use ExUnit.Case, async: true

  alias AgentEns.Error
  alias AgentEns.Internal.ABI
  alias AgentEns.Tx

  test "builds an ENSIP-25 setText transaction request" do
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
    assert String.starts_with?(tx.data, ABI.selector("setText(bytes32,string,string)"))
  end

  test "builds a generic ENS text-record transaction request" do
    assert {:ok, tx} =
             Tx.build_set_text_record_tx(%{
               ens_name: "vitalik.eth",
               chain_id: 1,
               resolver_address: "0x226159d592e2b063810a10ebf6dcbada94ed68b8",
               key: "avatar",
               value: "ipfs://avatar"
             })

    assert tx.to == "0x226159d592e2b063810a10ebf6dcbada94ed68b8"
    assert String.starts_with?(tx.data, ABI.selector("setText(bytes32,string,string)"))
  end

  test "builds an ETH address transaction request" do
    assert {:ok, tx} =
             Tx.build_set_addr_tx(%{
               ens_name: "vitalik.eth",
               chain_id: 1,
               resolver_address: "0x226159d592e2b063810a10ebf6dcbada94ed68b8",
               address: "0x1234567890abcdef1234567890ABCDEF12345678"
             })

    assert tx.to == "0x226159d592e2b063810a10ebf6dcbada94ed68b8"
    assert String.starts_with?(tx.data, ABI.selector("setAddr(bytes32,address)"))
  end

  test "builds a Regent-managed ETH address transaction request" do
    assert {:ok, tx} =
             Tx.build_regent_addr_tx(%{
               chain_id: 1,
               registrar_address: "0x3333333333333333333333333333333333333333",
               label: "vitalik",
               address: "0x1234567890abcdef1234567890ABCDEF12345678"
             })

    assert tx.to == "0x3333333333333333333333333333333333333333"
    assert String.starts_with?(tx.data, ABI.selector("setAddr(string,address)"))
  end

  test "builds a content hash transaction request" do
    assert {:ok, tx} =
             Tx.build_set_contenthash_tx(%{
               ens_name: "vitalik.eth",
               chain_id: 1,
               resolver_address: "0x226159d592e2b063810a10ebf6dcbada94ed68b8",
               contenthash: "0xe3010170122001020304"
             })

    assert tx.to == "0x226159d592e2b063810a10ebf6dcbada94ed68b8"
    assert String.starts_with?(tx.data, ABI.selector("setContenthash(bytes32,bytes)"))
  end

  test "builds a resolver update transaction request" do
    assert {:ok, tx} =
             Tx.build_set_resolver_tx(%{
               ens_name: "vitalik.eth",
               chain_id: 1,
               new_resolver_address: "0x1234567890abcdef1234567890abcdef12345678"
             })

    assert tx.to == "0x00000000000c2e074ec69a0dfb2997ba6c7d2e1e"
    assert String.starts_with?(tx.data, ABI.selector("setResolver(bytes32,address)"))
  end

  test "builds a ttl update transaction request" do
    assert {:ok, tx} =
             Tx.build_set_ttl_tx(%{
               ens_name: "vitalik.eth",
               chain_id: 1,
               ttl: 3600
             })

    assert tx.to == "0x00000000000c2e074ec69a0dfb2997ba6c7d2e1e"
    assert String.starts_with?(tx.data, ABI.selector("setTTL(bytes32,uint64)"))
  end

  test "builds a wrapped record update transaction request" do
    assert {:ok, tx} =
             Tx.build_set_record_tx(%{
               ens_name: "vitalik.eth",
               chain_id: 1,
               control: :name_wrapper,
               owner_address: "0x1111111111111111111111111111111111111111",
               resolver_address: "0x226159d592e2b063810a10ebf6dcbada94ed68b8",
               ttl: 300
             })

    assert tx.to == "0xd4416b13d2b3a9abae7acd5d6c2bbdbe25686401"
    assert String.starts_with?(tx.data, ABI.selector("setRecord(bytes32,address,address,uint64)"))
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
    assert String.starts_with?(tx.data, ABI.selector("setAgentURI(uint256,string)"))
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
    assert String.starts_with?(tx.data, ABI.selector("setName(string)"))
  end

  test "builds a reverse-name clear transaction request" do
    assert {:ok, tx} =
             Tx.build_reverse_set_name_tx(%{
               chain_id: 1,
               ens_name: "",
               reverse_registrar: "0xa58E81fe9b61B5c3fE2AFD33CF304c454AbFc7Cb"
             })

    assert tx.to == "0xa58e81fe9b61b5c3fe2afd33cf304c454abfc7cb"
    assert String.starts_with?(tx.data, ABI.selector("setName(string)"))
  end

  test "builds a registry subname owner transaction request" do
    assert {:ok, tx} =
             Tx.build_set_subnode_owner_tx(%{
               parent_name: "vitalik.eth",
               chain_id: 1,
               label: "app",
               owner_address: "0x1111111111111111111111111111111111111111"
             })

    assert tx.to == "0x00000000000c2e074ec69a0dfb2997ba6c7d2e1e"
    assert String.starts_with?(tx.data, ABI.selector("setSubnodeOwner(bytes32,bytes32,address)"))
  end

  test "builds a wrapped subname owner transaction request" do
    assert {:ok, tx} =
             Tx.build_set_subnode_owner_tx(%{
               parent_name: "vitalik.eth",
               chain_id: 1,
               control: :name_wrapper,
               label: "agent",
               owner_address: "0x1111111111111111111111111111111111111111",
               fuses: 65_536,
               expiry: 2_021_232_060
             })

    assert tx.to == "0xd4416b13d2b3a9abae7acd5d6c2bbdbe25686401"

    assert String.starts_with?(
             tx.data,
             ABI.selector("setSubnodeOwner(bytes32,string,address,uint32,uint64)")
           )
  end

  test "builds a registry subname record transaction request" do
    assert {:ok, tx} =
             Tx.build_set_subnode_record_tx(%{
               parent_name: "vitalik.eth",
               chain_id: 1,
               label: "app",
               owner_address: "0x1111111111111111111111111111111111111111",
               resolver_address: "0x226159d592e2b063810a10ebf6dcbada94ed68b8",
               ttl: 0
             })

    assert tx.to == "0x00000000000c2e074ec69a0dfb2997ba6c7d2e1e"

    assert String.starts_with?(
             tx.data,
             ABI.selector("setSubnodeRecord(bytes32,bytes32,address,address,uint64)")
           )
  end

  test "builds a wrapped subname record transaction request" do
    assert {:ok, tx} =
             Tx.build_set_subnode_record_tx(%{
               parent_name: "vitalik.eth",
               chain_id: 1,
               control: :name_wrapper,
               label: "app",
               owner_address: "0x1111111111111111111111111111111111111111",
               resolver_address: "0x226159d592e2b063810a10ebf6dcbada94ed68b8",
               ttl: 0,
               fuses: 65_536,
               expiry: 2_021_232_060
             })

    assert tx.to == "0xd4416b13d2b3a9abae7acd5d6c2bbdbe25686401"

    assert String.starts_with?(
             tx.data,
             ABI.selector("setSubnodeRecord(bytes32,string,address,address,uint64,uint32,uint64)")
           )
  end

  test "builds a convenience subname creation request" do
    assert {:ok, tx} =
             Tx.build_create_subname_tx(%{
               parent_name: "vitalik.eth",
               chain_id: 1,
               label: "docs",
               owner_address: "0x1111111111111111111111111111111111111111",
               resolver_address: "0x226159d592e2b063810a10ebf6dcbada94ed68b8",
               ttl: 0
             })

    assert tx.to == "0x00000000000c2e074ec69a0dfb2997ba6c7d2e1e"

    assert String.starts_with?(
             tx.data,
             ABI.selector("setSubnodeRecord(bytes32,bytes32,address,address,uint64)")
           )
  end

  test "rejects partial convenience subname record inputs instead of falling back to owner-only mode" do
    assert {:error, %Error{kind: :invalid_argument, message: message}} =
             Tx.build_create_subname_tx(%{
               parent_name: "vitalik.eth",
               chain_id: 1,
               label: "docs",
               owner_address: "0x1111111111111111111111111111111111111111",
               resolver_address: "0x226159d592e2b063810a10ebf6dcbada94ed68b8"
             })

    assert message =~ "resolver_address and ttl"
  end

  test "rejects invalid destination contract addresses" do
    assert {:error, %Error{kind: :invalid_argument, message: resolver_message}} =
             Tx.build_set_text_record_tx(%{
               ens_name: "vitalik.eth",
               chain_id: 1,
               resolver_address: "resolver.eth",
               key: "avatar",
               value: "ipfs://avatar"
             })

    assert resolver_message =~ "invalid address"

    assert {:error, %Error{kind: :invalid_argument, message: registrar_message}} =
             Tx.build_reverse_set_name_tx(%{
               chain_id: 1,
               ens_name: "vitalik.eth",
               reverse_registrar: "reverse.eth"
             })

    assert registrar_message =~ "invalid address"
  end

  test "rejects ttl values outside uint64 range" do
    assert {:error, %Error{kind: :invalid_argument, message: message}} =
             Tx.build_set_ttl_tx(%{
               ens_name: "vitalik.eth",
               chain_id: 1,
               ttl: 18_446_744_073_709_551_616
             })

    assert message =~ "invalid argument ttl"
  end

  test "rejects wrapped subname fuse values outside uint32 range" do
    assert {:error, %Error{kind: :invalid_argument, message: message}} =
             Tx.build_set_subnode_owner_tx(%{
               parent_name: "vitalik.eth",
               chain_id: 1,
               control: :name_wrapper,
               label: "agent",
               owner_address: "0x1111111111111111111111111111111111111111",
               fuses: 4_294_967_296,
               expiry: 2_021_232_060
             })

    assert message =~ "invalid argument fuses"
  end

  test "rejects wrapped subname expiry values outside uint64 range" do
    assert {:error, %Error{kind: :invalid_argument, message: message}} =
             Tx.build_set_subnode_record_tx(%{
               parent_name: "vitalik.eth",
               chain_id: 1,
               control: :name_wrapper,
               label: "app",
               owner_address: "0x1111111111111111111111111111111111111111",
               resolver_address: "0x226159d592e2b063810a10ebf6dcbada94ed68b8",
               ttl: 0,
               fuses: 65_536,
               expiry: "18446744073709551616"
             })

    assert message =~ "invalid argument expiry"
  end
end

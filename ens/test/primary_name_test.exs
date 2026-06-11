defmodule AgentEns.PrimaryNameTest do
  use ExUnit.Case, async: true

  alias AgentEns.PrimaryName

  @wallet "0x1234567890abcdef1234567890abcdef12345678"
  @other_wallet "0x9999999999999999999999999999999999999999"
  @rpc_url "https://rpc.test.invalid"

  defmodule RpcStub do
    @ens_registry "0x00000000000c2e074ec69a0dfb2997ba6c7d2e1e"
    @resolver "0x226159d592e2b063810a10ebf6dcbada94ed68b8"
    @owner "0x1111111111111111111111111111111111111111"

    def eth_call(_rpc_url, to, data) do
      to = String.downcase(to)
      reverse_node = node_hex("1234567890abcdef1234567890abcdef12345678.addr.reverse")
      forward_node = node_hex("alice.eth")
      forward_address = Process.get(:primary_name_forward_address)

      cond do
        to == @ens_registry and data == selector("resolver(bytes32)") <> reverse_node ->
          {:ok, address_word(@resolver)}

        to == @resolver and data == selector("name(bytes32)") <> reverse_node ->
          {:ok, encode_string("alice.eth")}

        to == @ens_registry and data == selector("resolver(bytes32)") <> forward_node ->
          {:ok, address_word(@resolver)}

        to == @ens_registry and data == selector("owner(bytes32)") <> forward_node ->
          {:ok, address_word(@owner)}

        to == @ens_registry and data == selector("ttl(bytes32)") <> forward_node ->
          {:ok, uint_word(0)}

        to == @ens_registry and data == selector("recordExists(bytes32)") <> forward_node ->
          {:ok, bool_word(true)}

        to == @resolver and interface_probe?(data, "0x3b3b57de") ->
          {:ok, bool_word(true)}

        to == @resolver and interface_probe?(data, "0x59d1d43c") ->
          {:ok, bool_word(true)}

        to == @resolver and interface_probe?(data, "0xbc1c58d1") ->
          {:ok, bool_word(true)}

        to == @resolver and interface_probe?(data, "0x9061b923") ->
          {:ok, bool_word(false)}

        to == @resolver and data == selector("addr(bytes32)") <> forward_node ->
          {:ok, address_word(forward_address)}
      end
    end

    defp node_hex(name) do
      {:ok, node} = AgentEns.Verify.namehash(name)
      Base.encode16(node, case: :lower)
    end

    defp interface_probe?(data, interface_id) do
      String.starts_with?(
        data,
        selector("supportsInterface(bytes4)") <> String.replace_prefix(interface_id, "0x", "")
      )
    end

    defp selector(signature), do: AgentEns.Internal.ABI.selector(signature)
    defp uint_word(value), do: "0x" <> String.pad_leading(Integer.to_string(value, 16), 64, "0")
    defp bool_word(true), do: "0x" <> String.pad_leading("1", 64, "0")
    defp bool_word(false), do: "0x" <> String.duplicate("0", 64)

    defp address_word(address) do
      "0x" <>
        String.pad_leading(String.replace_prefix(String.downcase(address), "0x", ""), 64, "0")
    end

    defp encode_string(value) do
      hex = Base.encode16(value, case: :lower)
      padding = rem(64 - rem(byte_size(hex), 64), 64)

      "0x" <>
        String.pad_leading("20", 64, "0") <>
        String.pad_leading(Integer.to_string(byte_size(value), 16), 64, "0") <>
        hex <> String.duplicate("0", padding)
    end
  end

  defmodule RpcNoReverseRecord do
    def eth_call(_rpc_url, _to, _data) do
      {:ok, "0x" <> String.duplicate("0", 64)}
    end
  end

  test "returns the normalized name when forward resolution matches the wallet" do
    Process.put(:primary_name_forward_address, @wallet)

    assert {:ok, "alice.eth"} =
             PrimaryName.verified_primary_name(
               String.upcase(@wallet) |> String.replace("0X", "0x"),
               rpc_url: @rpc_url,
               rpc_module: RpcStub
             )
  end

  test "returns nil when the name resolves to a different wallet" do
    Process.put(:primary_name_forward_address, @other_wallet)

    assert {:ok, nil} =
             PrimaryName.verified_primary_name(@wallet, rpc_url: @rpc_url, rpc_module: RpcStub)
  end

  test "returns nil when no reverse resolver is set" do
    assert {:ok, nil} =
             PrimaryName.verified_primary_name(@wallet,
               rpc_url: @rpc_url,
               rpc_module: RpcNoReverseRecord
             )
  end

  test "returns nil for invalid wallets or missing rpc url" do
    assert {:ok, nil} = PrimaryName.verified_primary_name("not-a-wallet", rpc_url: @rpc_url)
    assert {:ok, nil} = PrimaryName.verified_primary_name(nil, rpc_url: @rpc_url)
    assert {:ok, nil} = PrimaryName.verified_primary_name(@wallet, rpc_url: "")
    assert {:ok, nil} = PrimaryName.verified_primary_name(@wallet, [])
  end
end

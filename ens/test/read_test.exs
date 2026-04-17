defmodule AgentEns.ReadTest do
  use ExUnit.Case, async: true

  alias AgentEns.Error
  alias AgentEns.Read

  defmodule RpcRichRead do
    @ens_registry "0x00000000000c2e074ec69a0dfb2997ba6c7d2e1e"
    @name_wrapper "0xd4416b13d2b3a9abae7acd5d6c2bbdbe25686401"
    @resolver "0x226159d592e2b063810a10ebf6dcbada94ed68b8"
    @manager "0x1111111111111111111111111111111111111111"
    @target_address "0x1234567890abcdef1234567890abcdef12345678"
    @contenthash <<0xE3, 0x01, 0x01, 0x70, 0x12, 0x20, 0x01, 0x02, 0x03, 0x04>>

    def eth_call(_rpc_url, to, data) do
      to = String.downcase(to)

      cond do
        to == @ens_registry and String.starts_with?(data, selector("resolver(bytes32)")) ->
          {:ok, address_word(@resolver)}

        to == @ens_registry and String.starts_with?(data, selector("owner(bytes32)")) ->
          {:ok, address_word(@name_wrapper)}

        to == @ens_registry and String.starts_with?(data, selector("ttl(bytes32)")) ->
          {:ok, uint_word(3600)}

        to == @ens_registry and String.starts_with?(data, selector("recordExists(bytes32)")) ->
          {:ok, bool_word(true)}

        to == @name_wrapper and String.starts_with?(data, selector("ownerOf(uint256)")) ->
          {:ok, address_word(@manager)}

        to == @resolver and interface_probe?(data, "0x3b3b57de") ->
          {:ok, bool_word(true)}

        to == @resolver and interface_probe?(data, "0x59d1d43c") ->
          {:ok, bool_word(true)}

        to == @resolver and interface_probe?(data, "0xbc1c58d1") ->
          {:ok, bool_word(true)}

        to == @resolver and interface_probe?(data, "0x9061b923") ->
          {:ok, bool_word(false)}

        to == @resolver and String.starts_with?(data, selector("addr(bytes32)")) ->
          {:ok, address_word(@target_address)}

        to == @resolver and String.starts_with?(data, selector("contenthash(bytes32)")) ->
          {:ok, encode_bytes(@contenthash)}

        to == @resolver and String.starts_with?(data, selector("text(bytes32,string)")) ->
          {:ok, encode_text_response(data)}
      end
    end

    defp encode_text_response(data) do
      case decode_string_arg(data) do
        "avatar" -> encode_string("ipfs://avatar")
        "url" -> encode_string("https://example.invalid")
        _other -> encode_string("")
      end
    end

    defp decode_string_arg("0x" <> payload) do
      encoded_args = String.slice(payload, 8, byte_size(payload) - 8)
      head = String.slice(encoded_args, 0, 64 * 2)
      offset_bytes = String.to_integer(String.slice(head, 64, 64), 16)
      length = String.to_integer(String.slice(encoded_args, offset_bytes * 2, 64), 16)
      hex = String.slice(encoded_args, (offset_bytes + 32) * 2, length * 2)
      {:ok, binary} = Base.decode16(hex, case: :mixed)
      binary
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
      binary = :erlang.iolist_to_binary(value)
      hex = Base.encode16(binary, case: :lower)
      padding = rem(64 - rem(byte_size(hex), 64), 64)

      "0x" <>
        String.pad_leading("20", 64, "0") <>
        String.pad_leading(Integer.to_string(byte_size(binary), 16), 64, "0") <>
        hex <> String.duplicate("0", padding)
    end

    defp encode_bytes(binary) do
      hex = Base.encode16(binary, case: :lower)
      padding = rem(64 - rem(byte_size(hex), 64), 64)

      "0x" <>
        String.pad_leading("20", 64, "0") <>
        String.pad_leading(Integer.to_string(byte_size(binary), 16), 64, "0") <>
        hex <> String.duplicate("0", padding)
    end
  end

  defmodule RpcProbeFailure do
    @ens_registry "0x00000000000c2e074ec69a0dfb2997ba6c7d2e1e"
    @resolver "0x226159d592e2b063810a10ebf6dcbada94ed68b8"
    @owner "0x1111111111111111111111111111111111111111"

    def eth_call(_rpc_url, to, data) do
      to = String.downcase(to)

      cond do
        to == @ens_registry and String.starts_with?(data, selector("resolver(bytes32)")) ->
          {:ok, address_word(@resolver)}

        to == @ens_registry and String.starts_with?(data, selector("owner(bytes32)")) ->
          {:ok, address_word(@owner)}

        to == @ens_registry and String.starts_with?(data, selector("ttl(bytes32)")) ->
          {:ok, uint_word(0)}

        to == @ens_registry and String.starts_with?(data, selector("recordExists(bytes32)")) ->
          {:ok, bool_word(true)}

        to == @resolver and interface_probe?(data, "0x3b3b57de") ->
          {:error, {:rpc_error, :probe_failed}}
      end
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

    defp address_word(address) do
      "0x" <>
        String.pad_leading(String.replace_prefix(String.downcase(address), "0x", ""), 64, "0")
    end
  end

  defmodule RpcWildcardSubname do
    @ens_registry "0x00000000000c2e074ec69a0dfb2997ba6c7d2e1e"
    @owner "0x1111111111111111111111111111111111111111"

    def eth_call(_rpc_url, to, data) do
      to = String.downcase(to)

      cond do
        to == @ens_registry and String.starts_with?(data, selector("resolver(bytes32)")) ->
          {:ok, "0x" <> String.duplicate("0", 64)}

        to == @ens_registry and String.starts_with?(data, selector("owner(bytes32)")) ->
          {:ok, address_word(@owner)}

        to == @ens_registry and String.starts_with?(data, selector("ttl(bytes32)")) ->
          {:ok, uint_word(0)}

        to == @ens_registry and String.starts_with?(data, selector("recordExists(bytes32)")) ->
          {:ok, bool_word(false)}
      end
    end

    defp selector(signature), do: AgentEns.Internal.ABI.selector(signature)
    defp uint_word(value), do: "0x" <> String.pad_leading(Integer.to_string(value, 16), 64, "0")
    defp bool_word(false), do: "0x" <> String.duplicate("0", 64)

    defp address_word(address) do
      "0x" <>
        String.pad_leading(String.replace_prefix(String.downcase(address), "0x", ""), 64, "0")
    end
  end

  defmodule RpcNoResolver do
    @ens_registry "0x00000000000c2e074ec69a0dfb2997ba6c7d2e1e"
    @owner "0x1111111111111111111111111111111111111111"

    def eth_call(_rpc_url, to, data) do
      to = String.downcase(to)

      cond do
        to == @ens_registry and String.starts_with?(data, selector("resolver(bytes32)")) ->
          {:ok, "0x" <> String.duplicate("0", 64)}

        to == @ens_registry and String.starts_with?(data, selector("owner(bytes32)")) ->
          {:ok, address_word(@owner)}

        to == @ens_registry and String.starts_with?(data, selector("ttl(bytes32)")) ->
          {:ok, uint_word(0)}

        to == @ens_registry and String.starts_with?(data, selector("recordExists(bytes32)")) ->
          {:ok, bool_word(false)}
      end
    end

    defp selector(signature), do: AgentEns.Internal.ABI.selector(signature)
    defp uint_word(value), do: "0x" <> String.pad_leading(Integer.to_string(value, 16), 64, "0")
    defp bool_word(false), do: "0x" <> String.duplicate("0", 64)

    defp address_word(address) do
      "0x" <>
        String.pad_leading(String.replace_prefix(String.downcase(address), "0x", ""), 64, "0")
    end
  end

  test "reads a wrapped ENS name with resolver details" do
    assert {:ok, details} =
             Read.read_name(%{
               ens_name: "Demo.eth",
               chain_id: 1,
               rpc_url: "https://example.invalid",
               rpc_module: RpcRichRead,
               text_keys: ["avatar", "url"]
             })

    assert details.normalized_name == "demo.eth"
    assert details.record_exists?
    assert details.wrapped?
    assert details.manager_source == :name_wrapper_owner
    assert details.manager == "0x1111111111111111111111111111111111111111"
    assert details.resolver_address == "0x226159d592e2b063810a10ebf6dcbada94ed68b8"
    assert details.ttl == 3600
    assert details.eth_address == "0x1234567890abcdef1234567890abcdef12345678"
    assert details.contenthash == "0xe3010170122001020304"
    assert details.text_records["avatar"] == "ipfs://avatar"
    assert details.text_records["url"] == "https://example.invalid"

    assert details.resolver_profiles == %{
             addr: true,
             text: true,
             contenthash: true,
             extended: false
           }

    assert "ENS name is wrapped, so manager checks use the Name Wrapper owner." in details.warnings
  end

  test "reads a name without a resolver and returns empty resolver details" do
    assert {:ok, details} =
             Read.read_name(%{
               ens_name: "empty.eth",
               chain_id: 1,
               rpc_url: "https://example.invalid",
               rpc_module: RpcNoResolver,
               text_keys: ["avatar"]
             })

    refute details.record_exists?
    refute details.wrapped?
    assert details.resolver_address == nil
    assert details.eth_address == nil
    assert details.contenthash == nil
    assert details.text_records == %{}
    assert "ENS name does not currently have a resolver set." in details.warnings
  end

  test "returns resolver capability probe failures instead of downgrading them to missing data" do
    assert {:error, %Error{kind: :io, message: message}} =
             Read.read_name(%{
               ens_name: "demo.eth",
               chain_id: 1,
               rpc_url: "https://example.invalid",
               rpc_module: RpcProbeFailure,
               text_keys: ["avatar"]
             })

    assert message =~ "resolver call failed"
  end

  test "warns when a subname exact-node lookup may miss wildcard or offchain resolution" do
    assert {:ok, details} =
             Read.read_name(%{
               ens_name: "app.demo.eth",
               chain_id: 1,
               rpc_url: "https://example.invalid",
               rpc_module: RpcWildcardSubname
             })

    assert "The exact name does not currently have a resolver set. Wildcard or offchain subname resolution is not checked here." in details.warnings
  end
end

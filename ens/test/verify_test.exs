defmodule AgentEns.VerifyTest do
  use ExUnit.Case, async: true

  alias AgentEns.Verify

  defmodule RpcVerified do
    def eth_call(_rpc_url, "0x00000000000c2e074ec69a0dfb2997ba6c7d2e1e", _data) do
      {:ok, "0x000000000000000000000000226159d592e2b063810a10ebf6dcbada94ed68b8"}
    end

    def eth_call(
          _rpc_url,
          "0x226159d592e2b063810a10ebf6dcbada94ed68b8",
          "0x59d1d43c" <> _rest
        ) do
      {:ok, encode_string("verified")}
    end

    defp encode_string(value) do
      hex = Base.encode16(value, case: :lower)
      padded = hex <> String.duplicate("0", 64 - rem(byte_size(hex), 64))

      "0x" <>
        String.pad_leading("20", 64, "0") <>
        String.pad_leading(Integer.to_string(byte_size(value), 16), 64, "0") <>
        padded
    end
  end

  defmodule RpcMissing do
    def eth_call(_rpc_url, "0x00000000000c2e074ec69a0dfb2997ba6c7d2e1e", _data) do
      {:ok, "0x" <> String.duplicate("0", 64)}
    end
  end

  defmodule RpcEmptyRecord do
    def eth_call(_rpc_url, "0x00000000000c2e074ec69a0dfb2997ba6c7d2e1e", _data) do
      {:ok, "0x000000000000000000000000226159d592e2b063810a10ebf6dcbada94ed68b8"}
    end

    def eth_call(
          _rpc_url,
          "0x226159d592e2b063810a10ebf6dcbada94ed68b8",
          "0x59d1d43c" <> _rest
        ) do
      {:ok, "0x" <> String.pad_leading("20", 64, "0") <> String.duplicate("0", 64)}
    end
  end

  defmodule RpcExactKey do
    @resolver "0x226159d592e2b063810a10ebf6dcbada94ed68b8"

    def eth_call(_rpc_url, "0x00000000000c2e074ec69a0dfb2997ba6c7d2e1e", _data) do
      {:ok, "0x000000000000000000000000226159d592e2b063810a10ebf6dcbada94ed68b8"}
    end

    def eth_call(_rpc_url, @resolver, data) do
      if data == expected_call() do
        {:ok, encode_string("not-1-but-valid")}
      else
        {:ok, encode_string("")}
      end
    end

    defp expected_call do
      {:ok, key} =
        AgentEns.RecordKey.evm_record_key(
          1,
          "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
          42
        )

      {:ok, node} = AgentEns.Verify.namehash("vitalik.eth")

      {:ok, call} =
        AgentEns.Internal.ABI.encode_call("text(bytes32,string)", [
          {:bytes32, node},
          {:string, key}
        ])

      call
    end

    defp encode_string(value) do
      hex = Base.encode16(value, case: :lower)
      padded = hex <> String.duplicate("0", 64 - rem(byte_size(hex), 64))

      "0x" <>
        String.pad_leading("20", 64, "0") <>
        String.pad_leading(Integer.to_string(byte_size(value), 16), 64, "0") <>
        padded
    end
  end

  test "verifies a non-empty ENS text record" do
    assert {:ok, :verified} =
             Verify.verify(
               "https://example.invalid",
               "vitalik.eth",
               1,
               "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
               42,
               rpc_module: RpcVerified
             )
  end

  test "treats a missing resolver as ens record missing" do
    assert {:ok, :ens_record_missing} =
             Verify.verify(
               "https://example.invalid",
               "vitalik.eth",
               1,
               "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
               42,
               rpc_module: RpcMissing
             )
  end

  test "treats an empty ENS text record as missing" do
    assert {:ok, :ens_record_missing} =
             Verify.verify(
               "https://example.invalid",
               "vitalik.eth",
               1,
               "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
               42,
               rpc_module: RpcEmptyRecord
             )
  end

  test "accepts any non-empty ENSIP-25 proof value" do
    assert {:ok, :verified} =
             Verify.verify(
               "https://example.invalid",
               "vitalik.eth",
               1,
               "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
               42,
               rpc_module: RpcExactKey
             )
  end

  test "fails verification when the registry address is wrong" do
    assert {:ok, :ens_record_missing} =
             Verify.verify(
               "https://example.invalid",
               "vitalik.eth",
               1,
               "0x1111111111111111111111111111111111111111",
               42,
               rpc_module: RpcExactKey
             )
  end

  test "fails verification when the agent id is wrong" do
    assert {:ok, :ens_record_missing} =
             Verify.verify(
               "https://example.invalid",
               "vitalik.eth",
               1,
               "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
               167,
               rpc_module: RpcExactKey
             )
  end

  test "computes the known namehash for vitalik.eth" do
    assert {:ok, hash} = Verify.namehash("vitalik.eth")

    assert "0x" <> Base.encode16(hash, case: :lower) ==
             "0xee6c4522aab0003e8d14cd40a6af439055fd2577951148c14b6cea9a53475835"
  end

  test "verify_agent uses the built-in ERC-8004 network mapping" do
    assert {:ok, :ens_record_missing} =
             Verify.verify_agent(
               "https://example.invalid",
               :ethereum_sepolia,
               7,
               "demo.eth",
               rpc_module: RpcMissing
             )
  end
end

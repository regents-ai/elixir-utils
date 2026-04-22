defmodule AgentEns.RecordKeyTest do
  use ExUnit.Case, async: true

  alias AgentEns.RecordKey

  test "pins the ENSIP-25 key format for the Base ERC-8004 registry fixture" do
    assert {:ok,
            "agent-registration[0x00010000022105148004a169fb4a3325136eb29fa0ceb6d2e539a432][167]"} =
             RecordKey.evm_record_key(
               8453,
               "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
               167
             )
  end

  test "rejects agent ids that contain square brackets" do
    {:ok, interop} =
      AgentEns.ERC7930.evm(8453, "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432")

    assert {:error, error} =
             RecordKey.record_key(interop, "agent[167]")

    assert error.message =~ "must not contain '[' or ']'"
  end
end

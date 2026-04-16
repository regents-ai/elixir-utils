defmodule AgentEns.RecordKeyTest do
  use ExUnit.Case, async: true

  alias AgentEns.Error
  alias AgentEns.RecordKey

  test "builds the ENSIP-25 key from the spec example" do
    assert {:ok, key} =
             RecordKey.evm_record_key(
               1,
               "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
               167
             )

    assert key ==
             "agent-registration[0x000100000101148004a169fb4a3325136eb29fa0ceb6d2e539a432][167]"
  end

  test "rejects agent ids containing brackets" do
    assert {:error, %Error{kind: :invalid_argument, message: message}} =
             (with {:ok, interop} <-
                     AgentEns.ERC7930.evm(
                       1,
                       "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432"
                     ) do
                RecordKey.record_key(interop, "foo[bar]")
              end)

    assert message =~ "agent id must not contain"
  end
end

defmodule AgentEns.ERC7930Test do
  use ExUnit.Case, async: true

  alias AgentEns.ERC7930
  alias AgentEns.Error

  test "encodes the ENSIP-25 mainnet registry example" do
    assert {:ok, address} =
             ERC7930.evm(1, "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432")

    assert ERC7930.to_hex(address) ==
             "0x000100000101148004a169fb4a3325136eb29fa0ceb6d2e539a432"
  end

  test "encodes an EVM address without a chain reference" do
    assert {:ok, address} =
             ERC7930.evm_no_chain("0xd8da6bf26964af9d7eed9e03e53415d37aa96045")

    assert ERC7930.to_hex(address) ==
             "0x000100000014d8da6bf26964af9d7eed9e03e53415d37aa96045"
  end

  test "decodes a round trip address" do
    assert {:ok, original} =
             ERC7930.evm(1, "0x8004A169FB4a3325136EB29fA0ceB6D2e539a432")

    assert {:ok, decoded} = original |> ERC7930.encode() |> ERC7930.decode()
    assert decoded == original
    assert ERC7930.evm_chain_id(decoded) == 1
    assert ERC7930.evm_address(decoded) == "0x8004a169fb4a3325136eb29fa0ceb6d2e539a432"
  end

  test "decodes from hex and preserves the spec example" do
    assert {:ok, decoded} =
             ERC7930.from_hex("0x000100000101148004a169fb4a3325136eb29fa0ceb6d2e539a432")

    assert ERC7930.is_evm?(decoded)
    assert ERC7930.evm_chain_id(decoded) == 1
    assert ERC7930.evm_address(decoded) == "0x8004a169fb4a3325136eb29fa0ceb6d2e539a432"
  end

  test "keeps an empty chain reference separate from the address bytes" do
    assert {:ok, address} =
             ERC7930.evm_no_chain("0xd8da6bf26964af9d7eed9e03e53415d37aa96045")

    assert ERC7930.evm_chain_id(address) == nil
    assert ERC7930.evm_address(address) == "0xd8da6bf26964af9d7eed9e03e53415d37aa96045"
  end

  test "rejects malformed payloads" do
    assert {:error, %Error{kind: :invalid_argument, message: message}} = ERC7930.decode(<<0>>)
    assert message =~ "buffer too short"

    assert {:error, %Error{kind: :unsupported, message: message}} =
             ERC7930.decode(<<0, 2, 0, 0, 0, 1, 0>>)

    assert message =~ "unsupported version"

    assert {:error, %Error{kind: :invalid_argument, message: truncated_message}} =
             ERC7930.decode(<<0, 1, 0, 0, 5, 0>>)

    assert truncated_message =~ "truncated payload"

    assert {:error, %Error{kind: :invalid_argument, message: empty_message}} =
             ERC7930.decode(<<0, 1, 0, 0, 0, 0>>)

    assert empty_message =~ "both chain reference and address are empty"
  end
end

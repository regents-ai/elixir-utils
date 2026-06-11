defmodule AgentEns.AddressTest do
  use ExUnit.Case, async: true

  alias AgentEns.Address

  test "normalize trims, downcases, and validates" do
    assert Address.normalize("  0x52908400098527886E0F7030069857D2E4169EE7  ") ==
             "0x52908400098527886e0f7030069857d2e4169ee7"

    assert Address.normalize("0X52908400098527886E0F7030069857D2E4169EE7") ==
             "0x52908400098527886e0f7030069857d2e4169ee7"

    assert Address.normalize("0x123") == nil
    assert Address.normalize("not-an-address") == nil
    assert Address.normalize(nil) == nil
    assert Address.normalize(42) == nil
  end

  test "valid? mirrors normalize" do
    assert Address.valid?("0x0cb27e883e207905ad2a94f9b6ef0c7a99223c37")
    refute Address.valid?("0x123")
    refute Address.valid?(nil)
  end

  test "checksum returns EIP-55 display addresses" do
    assert {:ok, "0x52908400098527886E0F7030069857D2E4169EE7"} =
             Address.checksum("0x52908400098527886e0f7030069857d2e4169ee7")

    assert {:ok, "0x0cb27e883E207905AD2A94F9B6eF0C7A99223C37"} =
             Address.checksum("0x0cb27e883e207905ad2a94f9b6ef0c7a99223c37")

    assert {:error, :invalid_address} = Address.checksum("0x123")
  end
end

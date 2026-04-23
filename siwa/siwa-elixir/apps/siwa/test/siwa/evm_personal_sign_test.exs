defmodule Siwa.EvmPersonalSignTest do
  use ExUnit.Case, async: true

  alias Siwa.EvmPersonalSign

  @private_key Base.decode16!("59C6995E998F97A5A0044966F094538C5F6C75A5D9E7F0B6E6A0F9F5D4D17CE4")
  @message "world.example wants you to sign in with your Ethereum account:\n0xabc"

  test "recovers the signer address from a personal-sign signature" do
    %{address: address, signature: signature} = signed_message(@message)

    assert {:ok, ^address} = EvmPersonalSign.recover_personal_address(@message, signature)

    assert :ok =
             EvmPersonalSign.verify_personal_signature(
               @message,
               signature,
               String.upcase(address)
             )
  end

  test "rejects a signature for a different expected address" do
    %{signature: signature} = signed_message(@message)

    assert {:error, :invalid_signature} =
             EvmPersonalSign.verify_personal_signature(
               @message,
               signature,
               "0x0000000000000000000000000000000000000000"
             )
  end

  test "rejects malformed compact signatures" do
    assert {:error, :invalid_signature_encoding} =
             EvmPersonalSign.recover_personal_address(@message, "0x1234")
  end

  defp signed_message(message) do
    digest = EvmPersonalSign.personal_hash(message)
    {:ok, {signature, recovery_id}} = ExSecp256k1.sign_compact(digest, @private_key)
    {:ok, public_key} = ExSecp256k1.create_public_key(@private_key)
    address = EvmPersonalSign.public_key_to_address(public_key)

    %{
      address: address,
      signature: "0x" <> Base.encode16(signature <> <<recovery_id + 27>>, case: :lower)
    }
  end
end

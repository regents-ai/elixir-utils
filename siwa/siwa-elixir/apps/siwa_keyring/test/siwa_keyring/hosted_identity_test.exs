defmodule SiwaKeyring.HostedIdentityTest do
  use ExUnit.Case, async: true

  alias SiwaKeyring.HostedIdentity

  # A stored key must sign as the address it reports, and only with its own password.
  test "a stored key signs as its own address and opens only with its password" do
    {:ok, encrypted} = HostedIdentity.new("hosted-password")
    {:ok, signer} = HostedIdentity.signer(encrypted, "hosted-password")
    {:ok, address} = Siwa.RemoteSigner.get_address(signer)
    {:ok, signature} = Siwa.RemoteSigner.sign_message(signer, "hello")

    assert :ok = Siwa.EvmPersonalSign.verify_personal_signature("hello", signature, address)

    assert HostedIdentity.signer(encrypted, "another-password") ==
             {:error, :keystore_decrypt_failed}
  end
end

defmodule Siwa.SecretAllowlistTest do
  use ExUnit.Case, async: true

  @allowlist_path Path.expand("../../../../../../secret-allowlist.yaml", __DIR__)

  test "secret allowlist keeps shared utility secrets inside this repo boundary" do
    allowlist = File.read!(@allowlist_path)

    for name <- ~w(
      SIWA_RECEIPT_SECRET
      SIWA_NONCE_SECRET
      KEYRING_PROXY_SECRET
      KEYSTORE_PASSWORD
      XMTP_AGENT_PRIVATE_KEY
    ) do
      assert allowlist =~ "  - #{name}"
    end

    assert allowlist =~ "  - shared_siwa_receipt_signing"
    assert allowlist =~ "  - shared_keyring_proxy_hmac"
    assert allowlist =~ "  - product_database_url"
    assert allowlist =~ "  - product_billing_secret"
    refute allowlist =~ "STRIPE_SECRET"
    refute allowlist =~ "DATABASE_URL"
  end
end

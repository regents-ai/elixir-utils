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

  test "documented runtime env lookups stay in the allowlist" do
    allowlist = File.read!(@allowlist_path)
    allowed_names = env_names_from_allowlist(allowlist)
    root = Path.expand("../../../../../..", __DIR__)

    mentioned_names =
      root
      |> surface_files()
      |> Enum.flat_map(&env_names_from_file/1)
      |> MapSet.new()

    assert MapSet.subset?(mentioned_names, allowed_names),
           "Unallowlisted env names found: #{inspect(MapSet.difference(mentioned_names, allowed_names))}"
  end

  defp env_names_from_allowlist(source) do
    ~r/^\s+- ([A-Z][A-Z0-9_]+)$/m
    |> Regex.scan(source)
    |> Enum.map(fn [_match, name] -> name end)
    |> MapSet.new()
  end

  defp surface_files(root) do
    root
    |> Path.join("**/*.{ex,exs,md}")
    |> Path.wildcard()
    |> Enum.reject(&ignored_surface?/1)
  end

  defp ignored_surface?(path) do
    String.contains?(path, ["/deps/", "/_build/", "/doc/", "/node_modules/", "/siwa/siwa-js/"])
  end

  defp env_names_from_file(path) do
    ~r/System\.(?:fetch_env!|get_env)\("([A-Z][A-Z0-9_]+)"/
    |> Regex.scan(File.read!(path))
    |> Enum.map(fn [_match, name] -> name end)
  end
end

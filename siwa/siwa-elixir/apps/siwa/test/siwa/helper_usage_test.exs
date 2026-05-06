defmodule Siwa.HelperUsageTest do
  use ExUnit.Case, async: false

  test "identity file roundtrip preserves the main fields" do
    path = Path.join(System.tmp_dir!(), "siwa-identity-#{System.unique_integer([:positive])}.md")

    on_exit(fn -> File.rm(path) end)

    :ok =
      Siwa.Identity.write(path, %{
        address: "0x123",
        agent_id: 12,
        agent_registry: "eip155:8453:0xregistry",
        chain_id: 8453,
        endpoint: "https://api.example.com"
      })

    assert {:ok, identity} = Siwa.Identity.read(path)
    assert identity.address == "0x123"
    assert identity.agent_id == "12"
    assert identity.agent_registry == "eip155:8453:0xregistry"
    assert identity.chain_id == "8453"
    assert identity.endpoint == "https://api.example.com"
  end

  test "identity parsing keeps unknown labels as strings" do
    parsed =
      Siwa.Identity.parse("""
      # SIWA Identity

      - Address: 0x123
      - Custom Label: hello
      """)

    assert parsed.address == "0x123"
    assert parsed["Custom Label"] == "hello"
    refute Map.has_key?(parsed, :"Custom Label")
  end

  test "nonce input keeps unknown keys out of the atom table" do
    capture = self()

    assert {:ok, _nonce} =
             Siwa.create_nonce(
               %{
                 "customField" => "hello",
                 address: "0x123",
                 agent_id: 1,
                 agent_registry: "eip155:8453:0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
                 audience: "techtree"
               },
               store: fn _key, _nonce, _metadata, params ->
                 send(capture, {:nonce_params, params})
                 :ok
               end
             )

    assert_receive {:nonce_params, params}
    assert params["customField"] == "hello"
    refute Map.has_key?(params, :customField)
  end

  test "client resolver returns usable local signers" do
    assert {:ok, signer} = Siwa.ClientResolver.resolve_signer(%{provider: :local})
    assert {:ok, signed} = Siwa.LocalSigner.sign_message(signer, "hello")
    assert is_binary(signed)
    assert String.starts_with?(signed, "0x")
  end

  test "token-bound helper and registry helper cover the common lookups" do
    assert {:ok, registry} = Siwa.Registry.get_agent_registry_string(8453)
    assert registry == "eip155:8453:0x8004A169FB4a3325136EB29fA0ceB6D2e539a432"

    account = Siwa.TBA.account_key(registry, 42)
    assert Siwa.TBA.matches?(account, registry, 42)
    refute Siwa.TBA.matches?(account, registry, 43)
  end

  test "x402 memory session store can remember a paid session" do
    store = Siwa.X402.create_memory_session_store()
    assert {:ok, nil} = store.get.("0xabc", "/weather")
    assert :ok = store.set.("0xabc", "/weather", %{paid_at: 123, tx_hash: "0xtx"}, 5_000)
    assert {:ok, session} = store.get.("0xabc", "/weather")
    assert session == %{paid_at: 123, tx_hash: "0xtx"}
  end
end

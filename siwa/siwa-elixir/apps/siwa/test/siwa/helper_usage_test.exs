defmodule Siwa.HelperUsageTest do
  use ExUnit.Case, async: false

  test "identity file roundtrip preserves the main fields" do
    path = Path.join(System.tmp_dir!(), "siwa-identity-#{System.unique_integer([:positive])}.md")

    on_exit(fn -> File.rm(path) end)

    :ok =
      Siwa.Identity.write(path, %{
        address: "0x123",
        agent_id: 12,
        agent_registry: "eip155:84532:0xregistry",
        chain_id: 84532,
        endpoint: "https://api.example.com"
      })

    assert {:ok, identity} = Siwa.Identity.read(path)
    assert identity.address == "0x123"
    assert identity.agent_id == "12"
    assert identity.agent_registry == "eip155:84532:0xregistry"
    assert identity.chain_id == "84532"
    assert identity.endpoint == "https://api.example.com"
  end

  test "client resolver returns usable local signers" do
    assert {:ok, signer} = Siwa.ClientResolver.resolve_signer(%{provider: :local})
    assert {:ok, signed} = Siwa.LocalSigner.sign_message(signer, "hello")
    assert signed.address == signer.address
  end

  test "token-bound helper and registry helper cover the common lookups" do
    assert {:ok, registry} = Siwa.Registry.get_agent_registry_string(84532)
    assert registry == "eip155:84532:0x8004A818BFB912233c491871b3d84c89A494BD9e"

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

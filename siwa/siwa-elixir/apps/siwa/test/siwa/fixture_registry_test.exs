defmodule Siwa.FixtureRegistryTest do
  use ExUnit.Case, async: true

  defmodule MockClient do
    def owner_of(_registry_address, 42, _opts), do: {:ok, "0xowner"}

    def token_uri(_registry_address, 42, _opts),
      do:
        {:ok,
         "data:application/json;base64,eyJuYW1lIjoiRml4dHVyZSBBZ2VudCIsImRlc2NyaXB0aW9uIjoiRml4dHVyZSIsImltYWdlIjoiaXBmczovL2ltYWdlIiwic2VydmljZXMiOlt7Im5hbWUiOiJ3ZWIiLCJlbmRwb2ludCI6Imh0dHBzOi8vYXBpLmV4YW1wbGUuY29tIn1dLCJhY3RpdmUiOnRydWUsInN1cHBvcnRlZFRydXN0IjpbInJlcHV0YXRpb24iXX0="}

    def agent_wallet(_registry_address, 42, _opts), do: {:ok, "0xwallet"}

    def reputation_summary(_registry_address, 42, _opts),
      do: {:ok, %{count: 5, score: 25, rawValue: 2500, decimals: 2}}

    def submit_registration(signed, _opts), do: {:ok, %{transaction: signed.transaction}}
  end

  test "registry only exposes Base mainnet" do
    base_chains = MapSet.new([8453])

    assert Map.keys(Siwa.Registry.registry_addresses()) |> MapSet.new() == base_chains
    assert Map.keys(Siwa.Registry.reputation_addresses()) |> MapSet.new() == base_chains
    assert Map.keys(Siwa.Registry.rpc_endpoints()) |> MapSet.new() == base_chains
  end

  test "matches the frozen JS registry and reputation cases" do
    fixture = Siwa.TestFixtures.load("registry")
    data = fixture["case"]

    assert {:ok, agent} =
             Siwa.Registry.get_agent(42,
               client: MockClient,
               registry_address: "0xregistry",
               fetch_metadata: true
             )

    assert agent.agent_id == data["agent"]["agentId"]
    assert agent.owner == data["agent"]["owner"]
    assert agent.uri == data["agent"]["uri"]
    assert agent.agent_wallet == data["agent"]["agentWallet"]
    assert agent.metadata["name"] == data["agent"]["metadata"]["name"]

    assert {:ok, reputation} =
             Siwa.Registry.get_reputation(42,
               client: MockClient,
               reputation_registry_address: "0xreputation"
             )

    assert reputation.count == data["reputation"]["count"]
    assert reputation.score == data["reputation"]["score"]
    assert to_string(reputation.rawValue) == data["reputation"]["rawValue"]
    assert reputation.decimals == data["reputation"]["decimals"]

    assert {:ok, encoded} =
             Siwa.Registry.encode_register_agent(
               agent_uri: "ipfs://fixture-agent",
               chain_id: 8453,
               expected_signer: data["encodedRegistration"]["expected_signer"],
               expires_at: data["encodedRegistration"]["expires_at"],
               risk_copy: data["encodedRegistration"]["risk_copy"],
               idempotency_key: data["encodedRegistration"]["idempotency_key"]
             )

    assert encoded == data["encodedRegistration"]
  end

  test "registers agents through the canonical wallet action envelope" do
    {:ok, signer} = Siwa.LocalSigner.new()

    assert {:ok, registration} =
             Siwa.Registry.register_agent(
               agent_uri: "ipfs://fixture-agent",
               chain_id: 8453,
               tx_signer: signer,
               client: MockClient
             )

    assert registration.encoded["expected_signer"] == signer.address
    assert registration.encoded["risk_copy"] == "Register this agent with Regent."
    assert {:ok, _expires_at, 0} = DateTime.from_iso8601(registration.encoded["expires_at"])
    assert registration.signed.transaction == registration.encoded
    assert registration.result.transaction == registration.encoded
  end
end

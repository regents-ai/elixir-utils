defmodule Siwa.UsageFlowTest do
  use ExUnit.Case, async: false

  defmodule MockChainClient do
    def owner_of(_registry_address, _agent_id, _opts),
      do: {:ok, :persistent_term.get({__MODULE__, :owner})}

    def token_uri(_registry_address, _agent_id, _opts) do
      metadata = %{
        "name" => "Usage Agent",
        "description" => "Fixture for end-to-end usage",
        "image" => "ipfs://usage-agent",
        "services" => [%{"name" => "web", "endpoint" => "https://api.example.com"}],
        "active" => true,
        "supportedTrust" => ["reputation"]
      }

      {:ok, "data:application/json;base64," <> Base.encode64(Jason.encode!(metadata))}
    end

    def agent_wallet(_registry_address, _agent_id, _opts),
      do: {:ok, :persistent_term.get({__MODULE__, :owner})}
  end

  test "local signer flow covers nonce, sign-in, receipt, and authenticated follow-up request" do
    {:ok, signer} = Siwa.LocalSigner.new()
    :persistent_term.put({MockChainClient, :owner}, signer.address)

    {:ok, nonce} =
      Siwa.create_nonce(
        %{
          address: signer.address,
          agent_id: 7,
          agent_registry: "eip155:84532:0x8004A818BFB912233c491871b3d84c89A494BD9e"
        },
        nonce_secret: "nonce-secret"
      )

    assert nonce.status == "nonce_issued"
    assert is_binary(nonce.nonce)
    assert is_binary(nonce.nonce_token)

    {:ok, signed} =
      Siwa.sign_message(
        %{
          domain: "api.example.com",
          uri: "https://api.example.com/siwa",
          agent_id: 7,
          agent_registry: "eip155:84532:0x8004A818BFB912233c491871b3d84c89A494BD9e",
          chain_id: 84532,
          nonce: nonce.nonce,
          issued_at: "2026-04-17T00:00:00Z",
          statement: "Authenticate as a registered agent."
        },
        signer
      )

    {:ok, verified} =
      Siwa.verify(
        signed.message,
        signed.signature,
        domain: "api.example.com",
        nonce_token: nonce.nonce_token,
        nonce_secret: "nonce-secret",
        receipt_secret: "receipt-secret",
        chain_client: MockChainClient,
        require_active: true,
        required_services: ["web"],
        required_trust_models: ["reputation"]
      )

    assert verified.status == "authenticated"
    assert verified.address == signer.address
    assert verified.signer_type == "eoa"

    assert {:ok, receipt_payload} =
             Siwa.verify_receipt(verified.receipt, receipt_secret: "receipt-secret")

    assert receipt_payload["address"] == signer.address
    assert receipt_payload["agentId"] == 7

    request = %{
      method: "POST",
      path: "/protected",
      host: "api.example.com",
      query: "mode=test",
      body: ~s({"hello":"world"}),
      headers: %{"content-type" => "application/json"}
    }

    assert {:ok, signed_request} =
             Siwa.sign_authenticated_request(request, verified.receipt, signer)

    assert {:ok, follow_up} =
             Siwa.verify_authenticated_request(signed_request, receipt_secret: "receipt-secret")

    assert follow_up.address == signer.address
    assert follow_up.auth["path"] == "/protected"
    assert follow_up.auth["query"] == "mode=test"
  end

  test "wrong domain is rejected cleanly" do
    {:ok, signer} = Siwa.LocalSigner.new()
    :persistent_term.put({MockChainClient, :owner}, signer.address)

    {:ok, nonce} =
      Siwa.create_nonce(
        %{
          address: signer.address,
          agent_id: 8,
          agent_registry: "eip155:84532:0x8004A818BFB912233c491871b3d84c89A494BD9e"
        },
        nonce_secret: "nonce-secret"
      )

    {:ok, signed} =
      Siwa.sign_message(
        %{
          domain: "api.example.com",
          uri: "https://api.example.com/siwa",
          agent_id: 8,
          agent_registry: "eip155:84532:0x8004A818BFB912233c491871b3d84c89A494BD9e",
          chain_id: 84532,
          nonce: nonce.nonce,
          issued_at: "2026-04-17T00:00:00Z"
        },
        signer
      )

    assert {:ok, rejected} =
             Siwa.verify(
               signed.message,
               signed.signature,
               domain: "wrong.example.com",
               nonce_token: nonce.nonce_token,
               nonce_secret: "nonce-secret",
               receipt_secret: "receipt-secret",
               chain_client: MockChainClient
             )

    assert rejected.status == "rejected"
    assert rejected.reason == "domain_mismatch"
  end

  test "nonce issuance can require a challenge before continuing" do
    {:ok, signer} = Siwa.LocalSigner.new()

    assert {:ok, challenge_result} =
             Siwa.create_nonce(
               %{
                 address: signer.address,
                 agent_id: 9,
                 agent_registry: "eip155:84532:0x8004A818BFB912233c491871b3d84c89A494BD9e"
               },
               captcha_policy: fn _ -> "medium" end,
               captcha_secret: "captcha-secret",
               captcha_topic: "autonomous agents",
               captcha_format: "quatrain"
             )

    assert challenge_result.status == "captcha_required"
    assert is_map(challenge_result.challenge)
    assert is_binary(challenge_result.challenge_token)
  end

  test "messages with both not_before and expiration_time still reject early use" do
    {:ok, signer} = Siwa.LocalSigner.new()
    :persistent_term.put({MockChainClient, :owner}, signer.address)

    {:ok, nonce} =
      Siwa.create_nonce(
        %{
          address: signer.address,
          agent_id: 10,
          agent_registry: "eip155:84532:0x8004A818BFB912233c491871b3d84c89A494BD9e"
        },
        nonce_secret: "nonce-secret"
      )

    {:ok, signed} =
      Siwa.sign_message(
        %{
          domain: "api.example.com",
          uri: "https://api.example.com/siwa",
          agent_id: 10,
          agent_registry: "eip155:84532:0x8004A818BFB912233c491871b3d84c89A494BD9e",
          chain_id: 84532,
          nonce: nonce.nonce,
          issued_at: "2026-04-17T00:00:00Z",
          not_before: "2026-04-17T01:00:00Z",
          expiration_time: "2026-04-17T02:00:00Z"
        },
        signer
      )

    assert {:ok, rejected} =
             Siwa.verify(
               signed.message,
               signed.signature,
               domain: "api.example.com",
               nonce_token: nonce.nonce_token,
               nonce_secret: "nonce-secret",
               receipt_secret: "receipt-secret",
               chain_client: MockChainClient,
               now: ~U[2026-04-17 00:30:00Z]
             )

    assert rejected.status == "rejected"
    assert rejected.reason == "message_not_yet_valid"
  end
end

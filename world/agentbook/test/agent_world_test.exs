defmodule AgentWorldTest do
  use ExUnit.Case, async: true

  alias AgentWorld
  alias AgentWorld.AgentBook
  alias AgentWorld.Internal.ABI
  alias AgentWorld.Registration
  alias AgentWorld.TxRequest
  alias Siwa.EvmPersonalSign

  @agent "0x1111111111111111111111111111111111111111"
  @contract "0xA23aB2712eA7BBa896930544C7d6636a96b944dA"
  @private_key Base.decode16!("59C6995E998F97A5A0044966F094538C5F6C75A5D9E7F0B6E6A0F9F5D4D17CE4")
  @registration_expires_at ~U[2026-04-28 20:00:00Z]
  @registration_fresh_at ~U[2026-04-28 19:59:00Z]
  @registration_expired_at ~U[2026-04-28 20:00:01Z]

  defmodule RpcStub do
    @contract "0xA23aB2712eA7BBa896930544C7d6636a96b944dA"
    @erc1271_selector "0x1626ba7e"

    def eth_call(_rpc_url, contract, data) do
      lookup_selector = ABI.selector("lookupHuman(address)")
      nonce_selector = ABI.selector("getNextNonce(address)")

      cond do
        contract == @contract and String.starts_with?(data, lookup_selector) ->
          {:ok, "0x" <> String.pad_leading("1234", 64, "0")}

        contract == @contract and String.starts_with?(data, nonce_selector) ->
          {:ok, "0x" <> String.pad_leading("7", 64, "0")}

        contract == @contract and String.starts_with?(data, @erc1271_selector) ->
          {:ok, "0x1626ba7e" <> String.duplicate("0", 64)}

        true ->
          {:error, {:unexpected_call, contract, data}}
      end
    end

    def tx_receipt(_rpc_url, "0x" <> rest = tx_hash) when byte_size(rest) == 64 do
      case String.slice(tx_hash, -1, 1) do
        "1" -> {:ok, %{"status" => "0x1", "transactionHash" => tx_hash, "to" => @contract}}
        "0" -> {:ok, %{"status" => "0x0", "transactionHash" => tx_hash, "to" => @contract}}
        _ -> {:ok, nil}
      end
    end

    def tx_receipt(_rpc_url, _tx_hash), do: {:ok, nil}

    def relay_post(_url, _body, _idempotency_key), do: {:error, :relay_disabled}
  end

  defmodule RelayStub do
    def relay_post(_url, body, idempotency_key) do
      send(self(), {:relay_post, body, idempotency_key})
      {:ok, %{"txHash" => "0x" <> String.duplicate("c", 64)}}
    end
  end

  defmodule WrongContractRpcStub do
    def tx_receipt(_rpc_url, tx_hash) do
      {:ok,
       %{
         "status" => "0x1",
         "transactionHash" => tx_hash,
         "to" => "0x2222222222222222222222222222222222222222"
       }}
    end
  end

  test "lookup_human reads the human id through the shared package" do
    assert {:ok, "0x1234"} =
             AgentBook.lookup_human(@agent, "world",
               rpc_module: RpcStub,
               networks: %{"world" => %{rpc_url: "https://world.example"}}
             )
  end

  test "network overrides keep unknown caller keys as strings" do
    unknown_key = "caller_key_#{System.unique_integer([:positive])}"

    assert {:ok, network} =
             AgentBook.resolve_network("world",
               networks: %{
                 "world" => %{
                   "rpc_url" => "https://world.example",
                   unknown_key => "kept"
                 }
               }
             )

    assert network.rpc_url == "https://world.example"
    assert network[unknown_key] == "kept"

    assert_raise ArgumentError, fn ->
      String.to_existing_atom(unknown_key)
    end
  end

  test "create_session returns the request shape the browser flow expects" do
    assert {:ok, session} =
             Registration.create_session(%{
               "agent_address" => @agent,
               "network" => "world",
               "rpc_module" => RpcStub,
               "world_id" => %{
                 "app_id" => "app_test",
                 "action" => "agentbook-registration",
                 "rp_id" => "app_staging_test",
                 "signing_key" =>
                   "0x59c6995e998f97a5a0044966f094538c5f6c75a5d9e7f0b6e6a0f9f5d4d17ce4",
                 "ttl_seconds" => 300
               },
               "networks" => %{
                 "world" => %{
                   "rpc_url" => "https://world.example",
                   "contract_address" => @contract,
                   "relay_url" => ""
                 }
               }
             })

    assert String.starts_with?(session.session_id, "session_")
    assert session.nonce == 7
    assert session.chain_id == 480
    assert session.contract_address == @contract
    assert session.signal =~ "0x"
    assert session.app_id == "app_test"
    assert session.action == "agentbook-registration"
    assert session.rp_context.rp_id == "app_staging_test"
    assert session.rp_context.created_at < session.rp_context.expires_at
    assert String.starts_with?(session.rp_context.signature, "0x")
  end

  test "submit_proof in manual mode returns the register transaction request" do
    session = registration_session()
    proof = registration_proof()

    assert {:ok, %{status: :proof_ready, tx_request: %TxRequest{} = tx_request}} =
             Registration.submit_proof(session, proof,
               submission: :manual,
               now: @registration_fresh_at
             )

    assert tx_request.to == String.downcase(@contract)
    assert tx_request.chain_id == 480
    assert tx_request.value == "0x0"
    assert tx_request.expected_signer == @agent
    assert tx_request.expires_at == "2026-04-28T20:00:00Z"
    assert tx_request.risk_copy =~ "Only approve"
    assert tx_request.idempotency_key == registration_idempotency_key("session_test_relay")

    assert String.starts_with?(
             tx_request.data,
             ABI.selector("register(address,uint256,uint256,uint256,uint256[8])")
           )
  end

  test "submit_proof rejects expired registration sessions" do
    assert {:error, %AgentWorld.Error{message: message}} =
             Registration.submit_proof(registration_session(), registration_proof(),
               submission: :manual,
               now: @registration_expired_at
             )

    assert message =~ "expired"
  end

  test "generated session ids produce wallet-sized registration request markers" do
    session = registration_session(%{session_id: "session_" <> String.duplicate("a", 128)})

    assert {:ok, %{status: :proof_ready, tx_request: %TxRequest{} = tx_request}} =
             Registration.submit_proof(session, registration_proof(),
               submission: :manual,
               now: @registration_fresh_at
             )

    assert tx_request.idempotency_key == registration_idempotency_key(session.session_id)
    assert String.length(tx_request.idempotency_key) <= 128
    assert tx_request.idempotency_key =~ ~r/\A[A-Za-z0-9._:-]{16,128}\z/
  end

  test "register_transaction waits for confirmation and then succeeds" do
    session = %{
      network: "world",
      rpc_module: RpcStub,
      networks: %{"world" => %{"rpc_url" => "https://world.example"}}
    }

    pending_hash = "0x" <> String.duplicate("a", 63) <> "2"
    confirmed_hash = "0x" <> String.duplicate("b", 63) <> "1"

    assert {:error, {:transaction_pending, ^pending_hash}} =
             Registration.register_transaction(pending_hash, session)

    assert {:ok, %{status: :registered, tx_hash: ^confirmed_hash}} =
             Registration.register_transaction(confirmed_hash, session)
  end

  test "relay submission waits for later chain confirmation" do
    session =
      registration_session(%{
        relay_url: "https://relay.example",
        expires_at: DateTime.utc_now() |> DateTime.add(300, :second)
      })

    assert {:ok, %{status: :submitted, tx_hash: tx_hash, tx_request: %TxRequest{} = tx_request}} =
             Registration.submit_proof(session, registration_proof(), rpc_module: RelayStub)

    assert String.starts_with?(tx_hash, "0x")
    assert tx_request.idempotency_key == registration_idempotency_key("session_test_relay")

    assert_received {:relay_post, relay_body, "session_test_relay"}
    assert relay_body.agent == @agent
    assert relay_body.contract == @contract
    assert relay_body.nullifierHash == "0x" <> String.pad_leading("2", 64, "0")
  end

  test "relay errors do not include protected relay payloads" do
    error =
      AgentWorld.Error.new(
        {:relay_failed,
         {:http_error, 500, %{"signature" => "secret-signature", "payload" => "secret-payload"}}}
      )

    rendered = Exception.message(error) <> inspect(error.details)

    refute rendered =~ "secret-signature"
    refute rendered =~ "secret-payload"
    assert error.message == "Registration relay failed"
  end

  test "register_transaction rejects receipts for a different contract" do
    session = %{
      network: "world",
      rpc_module: WrongContractRpcStub,
      networks: %{"world" => %{"rpc_url" => "https://world.example"}}
    }

    tx_hash = "0x" <> String.duplicate("d", 64)

    assert {:error, %AgentWorld.Error{message: message}} =
             Registration.register_transaction(tx_hash, session)

    assert message =~ "different contract"
  end

  test "verify_agentkit_signature accepts rpc_url from map options for contract wallets" do
    payload = %{
      address: @contract,
      chainId: "eip155:480",
      domain: "world.example",
      issuedAt: "2026-04-22T00:00:00Z",
      nonce: "abc12345",
      signature: "0x" <> String.duplicate("0", 130),
      type: "eip1271",
      uri: "https://world.example/agentbook",
      version: "1"
    }

    assert {:ok, %{valid: true, address: address}} =
             AgentWorld.verify_agentkit_signature(payload, %{
               rpc_module: RpcStub,
               rpc_url: "https://world.example"
             })

    assert address == String.downcase(@contract)
  end

  test "verify_agentkit_signature accepts EOA personal-sign signatures" do
    address = eoa_address()

    payload = %{
      address: address,
      chainId: "eip155:480",
      domain: "world.example",
      issuedAt: "2026-04-22T00:00:00Z",
      nonce: "abc12345",
      signature: sign_agentkit_payload(address),
      type: "eip191",
      uri: "https://world.example/agentbook",
      version: "1"
    }

    assert {:ok, %{valid: true, address: verified_address}} =
             AgentWorld.verify_agentkit_signature(payload)

    assert verified_address == address
  end

  defp eoa_address do
    {:ok, public_key} = ExSecp256k1.create_public_key(@private_key)
    EvmPersonalSign.public_key_to_address(public_key)
  end

  defp registration_idempotency_key(session_id) do
    "agentworld:registration:" <>
      Base.encode16(:crypto.hash(:sha256, session_id), case: :lower)
  end

  defp registration_session(overrides \\ %{}) do
    Map.merge(
      %{
        session_id: "session_test_relay",
        agent_address: @agent,
        network: "world",
        chain_id: 480,
        contract_address: @contract,
        nonce: 7,
        relay_url: "",
        expires_at: @registration_expires_at
      },
      overrides
    )
  end

  defp registration_proof do
    %{
      "merkle_root" => "0x01",
      "nullifier_hash" => "0x02",
      "proof" => Enum.map(1..8, &("0x" <> String.pad_leading(Integer.to_string(&1, 16), 64, "0")))
    }
  end

  defp sign_agentkit_payload(address) do
    message =
      [
        "world.example wants you to sign in with your Ethereum account:",
        address,
        "",
        "URI: https://world.example/agentbook",
        "Version: 1",
        "Chain ID: 480",
        "Nonce: abc12345",
        "Issued At: 2026-04-22T00:00:00Z"
      ]
      |> Enum.join("\n")

    digest = EvmPersonalSign.personal_hash(message)
    {:ok, {signature, recovery_id}} = ExSecp256k1.sign_compact(digest, @private_key)
    "0x" <> Base.encode16(signature <> <<recovery_id + 27>>, case: :lower)
  end
end

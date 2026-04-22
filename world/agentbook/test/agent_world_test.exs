defmodule AgentWorldTest do
  use ExUnit.Case, async: true

  alias AgentWorld
  alias AgentWorld.AgentBook
  alias AgentWorld.Internal.ABI
  alias AgentWorld.Registration
  alias AgentWorld.TxRequest

  @agent "0x1111111111111111111111111111111111111111"
  @contract "0xA23aB2712eA7BBa896930544C7d6636a96b944dA"

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
        "1" -> {:ok, %{"status" => "0x1"}}
        "0" -> {:ok, %{"status" => "0x0"}}
        _ -> {:ok, nil}
      end
    end

    def tx_receipt(_rpc_url, _tx_hash), do: {:ok, nil}

    def relay_post(_url, _body), do: {:error, :relay_disabled}
  end

  test "lookup_human reads the human id through the shared package" do
    assert {:ok, "0x1234"} =
             AgentBook.lookup_human(@agent, "world",
               rpc_module: RpcStub,
               networks: %{"world" => %{rpc_url: "https://world.example"}}
             )
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
    session = %{
      agent_address: @agent,
      network: "world",
      chain_id: 480,
      contract_address: @contract,
      nonce: 7,
      relay_url: ""
    }

    proof = %{
      "merkle_root" => "0x01",
      "nullifier_hash" => "0x02",
      "proof" => Enum.map(1..8, &("0x" <> String.pad_leading(Integer.to_string(&1, 16), 64, "0")))
    }

    assert {:ok, %{status: :proof_ready, tx_request: %TxRequest{} = tx_request}} =
             Registration.submit_proof(session, proof, submission: :manual)

    assert tx_request.to == String.downcase(@contract)
    assert tx_request.chain_id == 480
    assert tx_request.value == "0x0"

    assert String.starts_with?(
             tx_request.data,
             ABI.selector("register(address,uint256,uint256,uint256,uint256[8])")
           )
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
end

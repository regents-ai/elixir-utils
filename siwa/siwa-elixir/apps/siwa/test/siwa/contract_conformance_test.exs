defmodule Siwa.ContractConformanceTest do
  # Runs every case in the generated siwa/contract/fixtures.json through the shared
  # plug and the verifier, as a site and the sign-in server would. The chain
  # answers like Base for a plain wallet: no smart wallet signed anything.
  use ExUnit.Case, async: true
  import Plug.Test

  alias Siwa.{AgentAuthPlug, Contract, RequestAuth, RpcStub}
  alias Siwa.Contract.Fixtures

  @fixtures_path Path.expand("../../../../../contract/fixtures.json", __DIR__)
  @external_resource @fixtures_path
  @fixtures @fixtures_path |> File.read!() |> Jason.decode!()

  defmodule Verifier do
    @moduledoc false
    # Stands in for the sign-in server: verifies the forwarded payload with the
    # library, reads the test's chain and keeps the replay window in the test
    # process.
    @behaviour AgentAuthPlug.Client

    @impl true
    def verify_http_request(payload) do
      replay_store = fn key, _expires ->
        seen = Process.get(:siwa_contract_seen, MapSet.new())
        Process.put(:siwa_contract_seen, MapSet.put(seen, key))
        if key in seen, do: {:error, :replayed_request}, else: :ok
      end

      verify_opts =
        :siwa_contract_audience
        |> Process.get()
        |> Fixtures.verify_opts()
        |> Keyword.merge(
          replay_store: replay_store,
          chain_rpcs: %{8453 => [rpc_url: Process.get(:siwa_contract_rpc)]}
        )

      case RequestAuth.verify_authenticated_request(payload, verify_opts) do
        {:ok, verified} ->
          data = %{
            "wallet_address" => verified.address,
            "chain_id" => verified.claims["chain_id"],
            "key_id" => verified.claims["key_id"],
            "principal" => %{"audience" => verified.claims["aud"]}
          }

          {:ok, %{status: 200, body: %{"code" => "http_envelope_valid", "data" => data}}}

        {:error, reason} ->
          {:error, %{reason: reason, source: :verifier}}
      end
    end
  end

  defmodule Hooks do
    @moduledoc false
    @behaviour AgentAuthPlug.Hooks

    @impl true
    def before_verify(_conn, _headers), do: {:ok, nil}

    @impl true
    # The plug has already matched the verdict's audience to its own; the
    # fixtures name the signer.
    def accept(conn, data, nil),
      do: {:ok, Plug.Conn.assign(conn, :principal, Map.delete(data, "principal"))}

    @impl true
    def deny(conn, deny_meta), do: Plug.Conn.assign(conn, :denied, deny_meta)
  end

  setup do
    Process.put(:siwa_contract_rpc, RpcStub.start(RpcStub.wallet_answers({true, ""})))
    :ok
  end

  test "the fixtures are for this contract" do
    assert @fixtures["contract_id"] == Contract.id()
  end

  for %{"name" => name} = fixture <- @fixtures["signed"] do
    @fixture fixture
    test "signed #{name}: the site accepts it and the message is the one listed" do
      assert send_request(@fixture).assigns.principal == @fixtures["principal"]
      assert RequestAuth.signing_message(request(@fixture)) == {:ok, @fixture["signing_message"]}
    end
  end

  for %{"name" => name} = fixture <- @fixtures["refused"] do
    @fixture fixture
    test "refused #{name}: #{fixture["checked_by"]} refuses it" do
      for _accepted <- 2..Map.get(@fixture, "sends", 1)//1 do
        assert %{principal: _principal} = send_request(@fixture).assigns
      end

      assert send_request(@fixture).assigns.denied == %{
               reason: String.to_existing_atom(@fixture["reason"]),
               source: if(@fixture["checked_by"] == "site_plug", do: :siwa_plug, else: :verifier)
             }
    end
  end

  for %{"name" => name} = fixture <- @fixtures["accepted"] do
    @fixture fixture
    test "accepted #{name}: the site and the verifier accept it with the same principal" do
      assert send_request(@fixture).assigns.principal == @fixtures["principal"]

      assert {:ok, %{address: address}} =
               RequestAuth.verify_authenticated_request(
                 request(@fixture),
                 Keyword.put(Fixtures.verify_opts(), :replay_store, fn _key, _expires -> :ok end)
               )

      assert address == @fixtures["principal"]["wallet_address"]
    end
  end

  defp send_request(%{"request" => request} = fixture) do
    conn =
      case request["body"] do
        nil ->
          conn(request["method"], request["path"])

        body ->
          {:ok, ^body, conn} =
            AgentAuthPlug.read_body(conn(request["method"], request["path"], body), [], 65_536)

          conn
      end

    audience = Map.get(fixture, "audience", @fixtures["verify"]["audience"])
    # The site's verify key names this audience at the sign-in server.
    Process.put(:siwa_contract_audience, audience)

    %{conn | req_headers: Enum.map(request["headers"], &List.to_tuple/1)}
    |> AgentAuthPlug.call(
      client: Verifier,
      hooks: Hooks,
      audience: audience,
      query: %{"refuse" => :refuse, "signed" => :signed}[fixture["query"]]
    )
  end

  defp request(%{"request" => request}) do
    %{
      method: request["method"],
      path: request["path"],
      body_digest: Siwa.content_digest_for_body(request["body"]),
      headers: Map.new(request["headers"], &List.to_tuple/1)
    }
  end
end

defmodule RegentNearIntentsTest do
  use ExUnit.Case, async: false

  @recipient "0x1111111111111111111111111111111111111111"
  @deposit_address "3f6e1b9c0d2a4e5f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f0a9b8c7d6e5f"

  setup do
    previous_options = Application.get_env(:regent_near_intents, :req_options)
    Application.put_env(:regent_near_intents, :req_options, plug: {Req.Test, __MODULE__})
    Req.Test.verify_on_exit!()

    on_exit(fn ->
      case previous_options do
        nil -> Application.delete_env(:regent_near_intents, :req_options)
        options -> Application.put_env(:regent_near_intents, :req_options, options)
      end
    end)
  end

  describe "tokens/0" do
    test "reads every asset from the service's list" do
      fixture = fixture("tokens.json")

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/v0/tokens"
        Req.Test.json(conn, fixture)
      end)

      assert {:ok, tokens} = RegentNearIntents.tokens()
      assert length(tokens) == length(fixture)

      assert hd(tokens) == %{
               asset_id: "nep141:wrap.near",
               symbol: "wNEAR",
               blockchain: "near",
               decimals: 24,
               price: 3.1
             }

      assert %{symbol: "USDC", blockchain: "base", decimals: 6} =
               Enum.find(
                 tokens,
                 &(&1.asset_id ==
                     "nep141:base-0x833589fcd6edb6e08f4c7c32d4f71b54bda02913.omft.near")
               )

      assert Enum.all?(tokens, &is_float(&1.price))
    end
  end

  describe "quote/1" do
    test "sends the NEAR to Base USDC route and reads a dry quote" do
      fixture = fixture("quote_dry.json")

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/v0/quote"

        {deadline, body} = Map.pop(json_body(conn), "deadline")

        assert body == %{
                 "dry" => true,
                 "swapType" => "EXACT_OUTPUT",
                 "slippageTolerance" => 100,
                 "originAsset" => "nep141:wrap.near",
                 "depositType" => "ORIGIN_CHAIN",
                 "destinationAsset" =>
                   "nep141:base-0x833589fcd6edb6e08f4c7c32d4f71b54bda02913.omft.near",
                 "amount" => "5000000",
                 "refundTo" => "test.near",
                 "refundType" => "ORIGIN_CHAIN",
                 "recipient" => @recipient,
                 "recipientType" => "DESTINATION_CHAIN"
               }

        {:ok, deadline, 0} = DateTime.from_iso8601(deadline)
        assert_in_delta DateTime.diff(deadline, DateTime.utc_now()), 3_600, 5

        conn |> Plug.Conn.put_status(201) |> Req.Test.json(fixture)
      end)

      assert {:ok, quote} =
               RegentNearIntents.quote(%{
                 usdc_amount: 5_000_000,
                 recipient: @recipient,
                 refund_to: "test.near",
                 dry: true
               })

      assert quote == %{
               amount_in: 1_651_313_840_569_386_417_635_746,
               amount_in_formatted: "1.651313840569386417635746",
               amount_out: 5_000_000,
               amount_out_formatted: "5.0",
               time_estimate_s: 24,
               deadline: "2026-11-14T23:00:00.000Z",
               deposit_address: nil,
               raw: fixture
             }
    end

    test "returns the deposit address and its deadline from a quote that is not dry" do
      fixture =
        fixture("quote_dry.json")
        |> put_in(["quoteRequest", "dry"], false)
        |> put_in(["quote", "depositAddress"], @deposit_address)
        |> put_in(["quote", "deadline"], "2026-11-14T23:30:00.000Z")

      Req.Test.expect(__MODULE__, fn conn ->
        assert %{"dry" => false} = json_body(conn)
        conn |> Plug.Conn.put_status(201) |> Req.Test.json(fixture)
      end)

      assert {:ok, %{deposit_address: @deposit_address, deadline: "2026-11-14T23:30:00.000Z"}} =
               RegentNearIntents.quote(%{
                 usdc_amount: 5_000_000,
                 recipient: @recipient,
                 refund_to: "test.near",
                 dry: false
               })
    end

    test "a quote that is not dry must carry a deposit address" do
      fixture = put_in(fixture("quote_dry.json"), ["quoteRequest", "dry"], false)
      Req.Test.expect(__MODULE__, &Req.Test.json(&1, fixture))

      assert {:error, %{reason: :unexpected_response, message: message}} =
               RegentNearIntents.quote(valid_request(dry: false))

      assert is_binary(message)
    end

    test "refuses a request outside the contract without calling the service" do
      for request <- [
            valid_request(usdc_amount: 0),
            valid_request(usdc_amount: -5),
            valid_request(usdc_amount: "5000000"),
            valid_request(usdc_amount: 5.0),
            valid_request(recipient: "0x1234"),
            valid_request(recipient: "1111111111111111111111111111111111111111"),
            valid_request(recipient: "0x111111111111111111111111111111111111111g"),
            valid_request(refund_to: ""),
            valid_request(refund_to: nil),
            valid_request(dry: "true"),
            Map.delete(valid_request([]), :dry),
            %{}
          ] do
        assert {:error, %{reason: :invalid_request, message: message}} =
                 RegentNearIntents.quote(request)

        assert is_binary(message)
      end
    end

    test "an answer of 400 becomes an HTTP error" do
      Req.Test.expect(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_status(400)
        |> Req.Test.json(%{"message" => "Amount is too low for bridge, try at least 1000000"})
      end)

      assert {:error, %{reason: :http_error, message: message}} =
               RegentNearIntents.quote(valid_request([]))

      assert is_binary(message)
    end

    test "a request that never reaches the service becomes a transport error" do
      Req.Test.expect(__MODULE__, &Req.Test.transport_error(&1, :econnrefused))

      assert {:error, %{reason: :transport, message: message}} =
               RegentNearIntents.quote(valid_request([]))

      assert is_binary(message)
    end
  end

  describe "status/1" do
    test "reads a finished swap and its first transaction on each chain" do
      fixture = fixture("status_success.json")

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/v0/status"
        assert conn.query_params == %{"depositAddress" => @deposit_address}
        Req.Test.json(conn, fixture)
      end)

      assert RegentNearIntents.status(@deposit_address) ==
               {:ok,
                %{
                  state: :success,
                  origin_tx: "4Fz8Wq2Er6Ty1Ui5Op9As3Df7Gh0Jk4Lz8Xc2Vb6Nm1Qw",
                  destination_tx:
                    "0x5c1e8f2a9b3d4c6e7f0a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f6a",
                  raw: fixture
                }}
    end

    test "maps each of the service's states" do
      for {status, state} <- [
            {"PENDING_DEPOSIT", :pending_deposit},
            {"KNOWN_DEPOSIT_TX", :pending_deposit},
            {"INCOMPLETE_DEPOSIT", :pending_deposit},
            {"PROCESSING", :processing},
            {"SUCCESS", :success},
            {"REFUNDED", :refunded},
            {"FAILED", :failed}
          ] do
        answer = Map.put(fixture("status_success.json"), "status", status)
        Req.Test.expect(__MODULE__, &Req.Test.json(&1, answer))

        assert {:ok, %{state: ^state}} = RegentNearIntents.status(@deposit_address)
      end
    end

    test "a swap with no transactions yet has no hashes" do
      answer =
        fixture("status_success.json")
        |> Map.put("status", "PENDING_DEPOSIT")
        |> put_in(["swapDetails", "originChainTxHashes"], [])
        |> put_in(["swapDetails", "destinationChainTxHashes"], [])

      Req.Test.expect(__MODULE__, &Req.Test.json(&1, answer))

      assert {:ok, %{state: :pending_deposit, origin_tx: nil, destination_tx: nil}} =
               RegentNearIntents.status(@deposit_address)
    end

    test "a state the service has not documented is an error" do
      answer = Map.put(fixture("status_success.json"), "status", "EXPIRED")
      Req.Test.expect(__MODULE__, &Req.Test.json(&1, answer))

      assert {:error, %{reason: :unexpected_response}} =
               RegentNearIntents.status(@deposit_address)
    end

    test "an unknown deposit address is not found" do
      Req.Test.expect(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_status(404)
        |> Req.Test.json(%{"message" => "Deposit address not found"})
      end)

      assert {:error, %{reason: :not_found}} = RegentNearIntents.status(@deposit_address)
    end

    test "refuses an empty deposit address without calling the service" do
      assert {:error, %{reason: :invalid_request}} = RegentNearIntents.status("")
      assert {:error, %{reason: :invalid_request}} = RegentNearIntents.status(nil)
    end
  end

  defp valid_request(overrides) do
    Map.merge(
      %{usdc_amount: 5_000_000, recipient: @recipient, refund_to: "test.near", dry: true},
      Map.new(overrides)
    )
  end

  defp fixture(name) do
    Path.join([__DIR__, "fixtures", name])
    |> File.read!()
    |> Jason.decode!()
  end

  defp json_body(conn) do
    {:ok, body, _conn} = Plug.Conn.read_body(conn)
    Jason.decode!(body)
  end
end

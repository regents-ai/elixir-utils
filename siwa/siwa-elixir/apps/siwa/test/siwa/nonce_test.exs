defmodule Siwa.NonceTest do
  use ExUnit.Case, async: false

  test "issues and consumes a nonce" do
    assert {:ok, issued} =
             Siwa.Nonce.issue(%{
               address: "0x123",
               agent_id: 9,
               agent_registry: "eip155:8453:0xregistry",
               audience: "techtree"
             })

    assert {:ok, _entry} =
             Siwa.Nonce.consume(%{
               address: "0x123",
               agent_id: 9,
               agent_registry: "eip155:8453:0xregistry",
               audience: "techtree",
               nonce: issued.nonce
             })
  end

  test "issues and consumes a nonce from json-style keys" do
    assert {:ok, issued} =
             Siwa.Nonce.issue(%{
               "address" => "0x123",
               "agent_id" => 9,
               "agent_registry" => "eip155:8453:0xregistry",
               "audience" => "techtree"
             })

    assert {:ok, _entry} =
             Siwa.Nonce.consume(%{
               "address" => "0x123",
               "agent_id" => 9,
               "agent_registry" => "eip155:8453:0xregistry",
               "audience" => "techtree",
               "nonce" => issued.nonce
             })
  end

  test "missing audience is rejected cleanly" do
    assert {:error, :audience_required} =
             Siwa.Nonce.issue(%{
               address: "0x123",
               agent_id: 9,
               agent_registry: "eip155:8453:0xregistry"
             })

    assert {:ok, issued} =
             Siwa.Nonce.issue(%{
               address: "0x123",
               agent_id: 9,
               agent_registry: "eip155:8453:0xregistry",
               audience: "techtree"
             })

    assert {:error, :audience_required} =
             Siwa.Nonce.consume(%{
               address: "0x123",
               agent_id: 9,
               agent_registry: "eip155:8453:0xregistry",
               nonce: issued.nonce
             })
  end

  test "stateless nonce tokens stay bound to the agent registry" do
    assert {:ok, issued} =
             Siwa.Nonce.issue(
               %{
                 address: "0x123",
                 agent_id: 9,
                 agent_registry: "eip155:8453:0xregistry",
                 audience: "techtree"
               },
               nonce_secret: "nonce-secret"
             )

    assert {:ok, payload} =
             Siwa.Nonce.verify_nonce_token(issued.nonce_token, nonce_secret: "nonce-secret")

    assert payload["agent_registry"] == "eip155:8453:0xregistry"

    assert {:error, :nonce_registry_mismatch} =
             Siwa.Nonce.consume(
               %{
                 address: "0x123",
                 agent_id: 9,
                 agent_registry: "eip155:8453:0xother",
                 audience: "techtree",
                 nonce: issued.nonce
               },
               nonce_token: issued.nonce_token,
               nonce_secret: "nonce-secret"
             )
  end

  test "stateless nonce tokens are one-time use" do
    assert {:ok, issued} =
             Siwa.Nonce.issue(
               %{
                 address: "0x123",
                 agent_id: 9,
                 agent_registry: "eip155:8453:0xregistry",
                 audience: "techtree"
               },
               nonce_secret: "nonce-secret"
             )

    params = %{
      address: "0x123",
      agent_id: 9,
      agent_registry: "eip155:8453:0xregistry",
      audience: "techtree",
      nonce: issued.nonce
    }

    assert {:ok, _payload} =
             Siwa.Nonce.consume(
               params,
               nonce_token: issued.nonce_token,
               nonce_secret: "nonce-secret"
             )

    assert {:error, :nonce_already_used} =
             Siwa.Nonce.consume(
               params,
               nonce_token: issued.nonce_token,
               nonce_secret: "nonce-secret"
             )
  end

  test "stateless nonce tokens stay one-time use under concurrent first access" do
    assert {:ok, issued} =
             Siwa.Nonce.issue(
               %{
                 address: "0x456",
                 agent_id: 10,
                 agent_registry: "eip155:8453:0xregistry",
                 audience: "techtree"
               },
               nonce_secret: "nonce-secret"
             )

    params = %{
      address: "0x456",
      agent_id: 10,
      agent_registry: "eip155:8453:0xregistry",
      audience: "techtree",
      nonce: issued.nonce
    }

    results =
      1..20
      |> Task.async_stream(
        fn _ ->
          Siwa.Nonce.consume(
            params,
            nonce_token: issued.nonce_token,
            nonce_secret: "nonce-secret"
          )
        end,
        max_concurrency: 20,
        timeout: 5_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1

    assert Enum.all?(
             results,
             &(match?({:ok, _}, &1) or match?({:error, :nonce_already_used}, &1))
           )

    assert Enum.count(results, &match?({:error, :nonce_already_used}, &1)) == 19
  end

  test "token replay consume stays one-time use with many stale entries present" do
    now_ms = System.system_time(:millisecond)
    stale_expires_at_ms = now_ms - 60_000
    fresh_expires_at_ms = now_ms + 60_000
    table = Siwa.Nonce.TokenReplayStore
    expiry_table = Module.concat(Siwa.Nonce.TokenReplayStore, Expiry)

    stale_keys =
      for index <- 1..10_000 do
        :crypto.hash(:sha256, "stale-token-#{System.unique_integer([:positive])}-#{index}")
      end

    :ets.insert(table, Enum.map(stale_keys, &{&1, stale_expires_at_ms}))
    :ets.insert(expiry_table, Enum.map(stale_keys, &{{stale_expires_at_ms, &1}, true}))

    fresh_key =
      :crypto.hash(:sha256, "fresh-token-#{System.unique_integer([:positive])}")

    on_exit(fn ->
      Enum.each(stale_keys, fn key ->
        :ets.delete(table, key)
        :ets.delete(expiry_table, {stale_expires_at_ms, key})
      end)

      :ets.delete(table, fresh_key)
      :ets.delete(expiry_table, {fresh_expires_at_ms, fresh_key})
    end)

    {elapsed_us, result} =
      :timer.tc(fn -> Siwa.Nonce.TokenReplayStore.consume(fresh_key, fresh_expires_at_ms) end)

    assert result == :ok
    assert elapsed_us < 250_000

    assert {:error, :nonce_already_used} =
             Siwa.Nonce.TokenReplayStore.consume(fresh_key, fresh_expires_at_ms)
  end

  describe "verify_nonce_token/2" do
    @nonce_secret "nonce-secret"

    defp issued_token do
      {:ok, issued} =
        Siwa.Nonce.issue(
          %{
            address: "0x123",
            agent_id: 9,
            agent_registry: "eip155:8453:0xregistry",
            audience: "techtree"
          },
          nonce_secret: @nonce_secret
        )

      issued.nonce_token
    end

    test "verifies a valid token" do
      token = issued_token()

      assert {:ok, payload} = Siwa.Nonce.verify_nonce_token(token, nonce_secret: @nonce_secret)
      assert payload["address"] == "0x123"
      assert payload["agent_id"] == 9
      assert payload["agent_registry"] == "eip155:8453:0xregistry"
      assert payload["audience"] == "techtree"
      assert is_integer(payload["exp"])
    end

    test "rejects tokens with extra dot segments" do
      token = issued_token()
      [encoded_body, mac] = String.split(token, ".")

      for bad <- [
            token <> ".extra",
            encoded_body <> ".." <> mac,
            encoded_body <> ".extra." <> mac
          ] do
        assert {:error, :invalid_nonce_token} =
                 Siwa.Nonce.verify_nonce_token(bad, nonce_secret: @nonce_secret)
      end
    end

    test "rejects tokens with empty segments" do
      token = issued_token()
      [encoded_body, mac] = String.split(token, ".")

      for bad <- ["." <> mac, encoded_body <> ".", ".", "", encoded_body] do
        assert {:error, :invalid_nonce_token} =
                 Siwa.Nonce.verify_nonce_token(bad, nonce_secret: @nonce_secret)
      end
    end

    test "rejects tokens with a tampered MAC" do
      token = issued_token()
      [encoded_body, mac] = String.split(token, ".")

      flipped =
        case mac do
          "A" <> rest -> "B" <> rest
          <<_first, rest::binary>> -> "A" <> rest
        end

      assert {:error, :invalid_nonce_token} =
               Siwa.Nonce.verify_nonce_token(encoded_body <> "." <> flipped,
                 nonce_secret: @nonce_secret
               )
    end

    test "rejects tokens signed with a different secret" do
      token = issued_token()

      assert {:error, :invalid_nonce_token} =
               Siwa.Nonce.verify_nonce_token(token, nonce_secret: "other-secret")
    end

    test "rejects expired tokens" do
      token = issued_token()
      future = DateTime.add(DateTime.utc_now(), 6 * 60, :second)

      assert {:error, :invalid_nonce_token} =
               Siwa.Nonce.verify_nonce_token(token, nonce_secret: @nonce_secret, now: future)
    end

    test "rejects tokens without an integer exp claim" do
      for payload <- [%{"nonce" => "n"}, %{"nonce" => "n", "exp" => "9999999999999"}] do
        {:ok, token} = Siwa.Nonce.create_nonce_token(payload, nonce_secret: @nonce_secret)

        assert {:error, :invalid_nonce_token} =
                 Siwa.Nonce.verify_nonce_token(token, nonce_secret: @nonce_secret)
      end
    end

    test "rejects tokens whose body is not base64-encoded JSON" do
      mac_for = fn encoded_body ->
        :crypto.mac(:hmac, :sha256, @nonce_secret, encoded_body)
        |> Base.url_encode64(padding: false)
      end

      not_base64 = "!!!not-base64!!!"
      not_json = Base.url_encode64("not json", padding: false)
      not_map = Base.url_encode64(Jason.encode!([1, 2, 3]), padding: false)

      for encoded_body <- [not_base64, not_json, not_map] do
        token = encoded_body <> "." <> mac_for.(encoded_body)

        assert {:error, :invalid_nonce_token} =
                 Siwa.Nonce.verify_nonce_token(token, nonce_secret: @nonce_secret)
      end
    end

    test "rejects non-binary tokens" do
      assert {:error, :invalid_nonce_token} =
               Siwa.Nonce.verify_nonce_token(nil, nonce_secret: @nonce_secret)

      assert {:error, :invalid_nonce_token} =
               Siwa.Nonce.verify_nonce_token(123, nonce_secret: @nonce_secret)
    end
  end

  test "audience scopes stored nonces" do
    {:ok, first} =
      Siwa.Nonce.issue(%{
        address: "0xabc",
        agent_id: 11,
        agent_registry: "eip155:8453:0xregistry",
        audience: "app-one"
      })

    {:ok, second} =
      Siwa.Nonce.issue(%{
        address: "0xabc",
        agent_id: 11,
        agent_registry: "eip155:8453:0xregistry",
        audience: "app-two"
      })

    assert {:ok, _entry} =
             Siwa.Nonce.consume(%{
               address: "0xabc",
               agent_id: 11,
               agent_registry: "eip155:8453:0xregistry",
               audience: "app-one",
               nonce: first.nonce
             })

    assert {:ok, _entry} =
             Siwa.Nonce.consume(%{
               address: "0xabc",
               agent_id: 11,
               agent_registry: "eip155:8453:0xregistry",
               audience: "app-two",
               nonce: second.nonce
             })
  end
end

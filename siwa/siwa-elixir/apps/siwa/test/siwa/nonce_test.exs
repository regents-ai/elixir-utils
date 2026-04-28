defmodule Siwa.NonceTest do
  use ExUnit.Case, async: false

  test "issues and consumes a nonce" do
    assert {:ok, issued} =
             Siwa.Nonce.issue(%{
               address: "0x123",
               agent_id: 9,
               agent_registry: "eip155:84532:0xregistry",
               audience: "techtree"
             })

    assert {:ok, _entry} =
             Siwa.Nonce.consume(%{
               address: "0x123",
               agent_id: 9,
               agent_registry: "eip155:84532:0xregistry",
               audience: "techtree",
               nonce: issued.nonce
             })
  end

  test "issues and consumes a nonce from json-style keys" do
    assert {:ok, issued} =
             Siwa.Nonce.issue(%{
               "address" => "0x123",
               "agentId" => 9,
               "agentRegistry" => "eip155:84532:0xregistry",
               "audience" => "techtree"
             })

    assert {:ok, _entry} =
             Siwa.Nonce.consume(%{
               "address" => "0x123",
               "agentId" => 9,
               "agentRegistry" => "eip155:84532:0xregistry",
               "audience" => "techtree",
               "nonce" => issued.nonce
             })
  end

  test "missing audience is rejected cleanly" do
    assert {:error, :audience_required} =
             Siwa.Nonce.issue(%{
               address: "0x123",
               agent_id: 9,
               agent_registry: "eip155:84532:0xregistry"
             })

    assert {:ok, issued} =
             Siwa.Nonce.issue(%{
               address: "0x123",
               agent_id: 9,
               agent_registry: "eip155:84532:0xregistry",
               audience: "techtree"
             })

    assert {:error, :audience_required} =
             Siwa.Nonce.consume(%{
               address: "0x123",
               agent_id: 9,
               agent_registry: "eip155:84532:0xregistry",
               nonce: issued.nonce
             })
  end

  test "stateless nonce tokens stay bound to the agent registry" do
    assert {:ok, issued} =
             Siwa.Nonce.issue(
               %{
                 address: "0x123",
                 agent_id: 9,
                 agent_registry: "eip155:84532:0xregistry",
                 audience: "techtree"
               },
               nonce_secret: "nonce-secret"
             )

    assert {:ok, payload} =
             Siwa.Nonce.verify_nonce_token(issued.nonce_token, nonce_secret: "nonce-secret")

    assert payload["agentRegistry"] == "eip155:84532:0xregistry"

    assert {:error, :nonce_registry_mismatch} =
             Siwa.Nonce.consume(
               %{
                 address: "0x123",
                 agent_id: 9,
                 agent_registry: "eip155:84532:0xother",
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
                 agent_registry: "eip155:84532:0xregistry",
                 audience: "techtree"
               },
               nonce_secret: "nonce-secret"
             )

    params = %{
      address: "0x123",
      agent_id: 9,
      agent_registry: "eip155:84532:0xregistry",
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
                 agent_registry: "eip155:84532:0xregistry",
                 audience: "techtree"
               },
               nonce_secret: "nonce-secret"
             )

    params = %{
      address: "0x456",
      agent_id: 10,
      agent_registry: "eip155:84532:0xregistry",
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

  test "audience scopes stored nonces" do
    {:ok, first} =
      Siwa.Nonce.issue(%{
        address: "0xabc",
        agent_id: 11,
        agent_registry: "eip155:84532:0xregistry",
        audience: "app-one"
      })

    {:ok, second} =
      Siwa.Nonce.issue(%{
        address: "0xabc",
        agent_id: 11,
        agent_registry: "eip155:84532:0xregistry",
        audience: "app-two"
      })

    assert {:ok, _entry} =
             Siwa.Nonce.consume(%{
               address: "0xabc",
               agent_id: 11,
               agent_registry: "eip155:84532:0xregistry",
               audience: "app-one",
               nonce: first.nonce
             })

    assert {:ok, _entry} =
             Siwa.Nonce.consume(%{
               address: "0xabc",
               agent_id: 11,
               agent_registry: "eip155:84532:0xregistry",
               audience: "app-two",
               nonce: second.nonce
             })
  end
end

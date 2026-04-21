defmodule Siwa.NonceTest do
  use ExUnit.Case, async: false

  test "issues and consumes a nonce" do
    assert {:ok, issued} =
             Siwa.Nonce.issue(%{
               address: "0x123",
               agent_id: 9,
               agent_registry: "eip155:84532:0xregistry"
             })

    assert {:ok, _entry} =
             Siwa.Nonce.consume(%{
               address: "0x123",
               agent_id: 9,
               agent_registry: "eip155:84532:0xregistry",
               nonce: issued.nonce
             })
  end

  test "issues and consumes a nonce from json-style keys" do
    assert {:ok, issued} =
             Siwa.Nonce.issue(%{
               "address" => "0x123",
               "agentId" => 9,
               "agentRegistry" => "eip155:84532:0xregistry"
             })

    assert {:ok, _entry} =
             Siwa.Nonce.consume(%{
               "address" => "0x123",
               "agentId" => 9,
               "agentRegistry" => "eip155:84532:0xregistry",
               "nonce" => issued.nonce
             })
  end

  test "stateless nonce tokens stay bound to the agent registry" do
    assert {:ok, issued} =
             Siwa.Nonce.issue(
               %{
                 address: "0x123",
                 agent_id: 9,
                 agent_registry: "eip155:84532:0xregistry"
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
                 agent_registry: "eip155:84532:0xregistry"
               },
               nonce_secret: "nonce-secret"
             )

    params = %{
      address: "0x123",
      agent_id: 9,
      agent_registry: "eip155:84532:0xregistry",
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
end

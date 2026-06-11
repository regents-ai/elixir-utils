defmodule Siwa.AgentClaimsTest do
  use ExUnit.Case, async: true

  alias Siwa.AgentClaims

  @wallet "0xF39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
  @registry "0x3333333333333333333333333333333333333333"

  describe "from_headers/2" do
    test "normalizes valid agent headers into canonical claims" do
      headers = %{
        "x-agent-wallet-address" => " #{@wallet} ",
        "x-agent-chain-id" => "8453",
        "x-agent-registry-address" => @registry,
        "x-agent-token-id" => "77",
        "x-agent-label" => "  helios  "
      }

      assert {:ok,
              %{
                "wallet_address" => "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
                "chain_id" => "8453",
                "registry_address" => @registry,
                "token_id" => "77",
                "label" => "helios"
              }} = AgentClaims.from_headers(headers)
    end

    test "label is nil when absent or blank" do
      headers = valid_headers()
      assert {:ok, %{"label" => nil}} = AgentClaims.from_headers(headers)

      headers = Map.put(headers, "x-agent-label", "   ")
      assert {:ok, %{"label" => nil}} = AgentClaims.from_headers(headers)
    end

    test "reports every missing or blank required header" do
      headers = %{
        "x-agent-wallet-address" => @wallet,
        "x-agent-chain-id" => "  "
      }

      assert {:error,
              %{
                reason: :missing_agent_headers,
                source: :request_headers,
                missing_headers: missing
              }} = AgentClaims.from_headers(headers)

      assert Enum.sort(missing) ==
               ["x-agent-chain-id", "x-agent-registry-address", "x-agent-token-id"]
    end

    test "rejects malformed addresses and non-positive integers" do
      assert {:error,
              %{
                reason: :invalid_agent_header,
                source: :request_headers,
                invalid_header: "x-agent-wallet-address"
              }} =
               valid_headers()
               |> Map.put("x-agent-wallet-address", "0x1234")
               |> AgentClaims.from_headers()

      for bad_token <- ["0", "-1", "07", "12abc"] do
        assert {:error, %{invalid_header: "x-agent-token-id"}} =
                 valid_headers()
                 |> Map.put("x-agent-token-id", bad_token)
                 |> AgentClaims.from_headers()
      end
    end

    test "uses the provided source in deny metadata" do
      assert {:error, %{source: :custom}} = AgentClaims.from_headers(%{}, :custom)
    end
  end

  describe "from_claims/2" do
    test "normalizes broker claims with binary and integer values" do
      claims = %{
        "wallet_address" => @wallet,
        "chain_id" => 8453,
        "registry_address" => String.upcase(@registry) |> String.replace("0X", "0x"),
        "token_id" => "77",
        "label" => "helios"
      }

      assert {:ok,
              %{
                "wallet_address" => "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
                "chain_id" => "8453",
                "registry_address" => @registry,
                "token_id" => "77",
                "label" => "helios"
              }} = AgentClaims.from_claims(claims)
    end

    test "reports the first missing claim" do
      claims = %{"wallet_address" => @wallet, "registry_address" => @registry}

      assert {:error,
              %{
                reason: :missing_agent_headers,
                source: :siwa_claims,
                missing_headers: ["chain_id"]
              }} = AgentClaims.from_claims(claims)
    end

    test "rejects malformed claim values" do
      claims = %{
        "wallet_address" => @wallet,
        "chain_id" => "8453",
        "registry_address" => "not-an-address",
        "token_id" => "77"
      }

      assert {:error,
              %{
                reason: :invalid_agent_header,
                source: :siwa_claims,
                invalid_header: "registry_address"
              }} = AgentClaims.from_claims(claims)
    end

    test "rejects non-map claims" do
      assert {:error, %{reason: :missing_agent_headers, source: :siwa_claims}} =
               AgentClaims.from_claims(nil)
    end
  end

  defp valid_headers do
    %{
      "x-agent-wallet-address" => @wallet,
      "x-agent-chain-id" => "8453",
      "x-agent-registry-address" => @registry,
      "x-agent-token-id" => "77"
    }
  end
end

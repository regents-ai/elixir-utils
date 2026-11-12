defmodule RegentPrivy.ProofTest do
  use ExUnit.Case, async: true

  alias RegentPrivy.Proof

  defp conn(headers) do
    Enum.reduce(headers, Plug.Test.conn(:post, "/"), fn {name, value}, conn ->
      %{conn | req_headers: conn.req_headers ++ [{name, value}]}
    end)
  end

  test "the bearer and Privy's identity header make a pair" do
    conn = conn([{"authorization", "Bearer access"}, {"privy-id-token", "identity"}])
    assert Proof.pair(conn) == {:ok, %{access: "access", identity: "identity"}}
  end

  test "a missing, empty or repeated half is named and nothing else is read" do
    assert Proof.pair(conn([{"privy-id-token", "identity"}])) ==
             {:error, {:request_pair, :missing_access_token}}

    assert Proof.pair(conn([{"authorization", "Bearer  "}, {"privy-id-token", "identity"}])) ==
             {:error, {:request_pair, :missing_access_token}}

    assert Proof.pair(conn([{"authorization", "Bearer access"}])) ==
             {:error, {:request_pair, :missing_identity_token}}

    assert Proof.pair(
             conn([
               {"authorization", "Bearer access"},
               {"privy-id-token", "one"},
               {"privy-id-token", "two"}
             ])
           ) == {:error, {:request_pair, :missing_identity_token}}
  end
end

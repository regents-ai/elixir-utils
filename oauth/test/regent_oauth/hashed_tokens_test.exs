defmodule RegentOAuth.HashedTokensTest do
  # Access and refresh tokens are kept only as their SHA-256 hash; the plain
  # tokens reach the connecting app once, in the token answer (27 Oct 2026).
  use RegentOAuth.Case

  alias Boruta.Ecto.Token
  alias RegentOAuth.Repo
  alias RegentOAuth.Test.Flow

  defp stored_anywhere?(plain) do
    %{rows: [[count]]} =
      Repo.query!(
        "SELECT count(*) FROM regent_oauth_test.oauth_tokens WHERE $1 IN (value, refresh_token, previous_token)",
        [plain]
      )

    count > 0
  end

  defp access_row(client_id, hash),
    do: Repo.get_by!(Token, type: "access_token", client_id: client_id, value: hash)

  test "a signed-in app's tokens are stored only as their hashes, and only the plain token is a credential" do
    {client_id, answer} = Flow.sign_in!("did:privy:sol")
    %{"access_token" => access, "refresh_token" => refresh} = answer

    row = access_row(client_id, RegentOAuth.hash_token(access))
    assert row.refresh_token == RegentOAuth.hash_token(refresh)
    assert row.value =~ ~r/\A[0-9a-f]{64}\z/
    refute stored_anywhere?(access)
    refute stored_anywhere?(refresh)

    assert {:ok, %{subject: "did:privy:sol", client_id: ^client_id}} =
             RegentOAuth.verify(access, RegentOAuth.resource())

    assert {:error, :unauthorized} = RegentOAuth.verify(row.value, RegentOAuth.resource())
  end

  test "a refresh hands out new tokens, keeps only the old access token's hash, and a reused refresh token disconnects the app" do
    {client_id, %{"access_token" => access, "refresh_token" => refresh}} =
      Flow.sign_in!("did:privy:sol")

    conn = Flow.refresh(client_id, refresh)
    assert conn.status == 200
    %{"access_token" => fresh, "refresh_token" => fresh_refresh} = Jason.decode!(conn.resp_body)
    assert fresh != access and fresh_refresh != refresh

    successor = access_row(client_id, RegentOAuth.hash_token(fresh))
    assert successor.previous_token == RegentOAuth.hash_token(access)
    refute stored_anywhere?(fresh)
    refute stored_anywhere?(fresh_refresh)
    assert {:ok, _} = RegentOAuth.verify(fresh, RegentOAuth.resource())

    reused = Flow.refresh(client_id, refresh)
    assert reused.status == 400
    assert Jason.decode!(reused.resp_body) == %{"error" => "invalid_grant"}
    assert {:error, :unauthorized} = RegentOAuth.verify(fresh, RegentOAuth.resource())
  end

  test "revoking with the plain refresh token disconnects the app" do
    {client_id, %{"access_token" => access, "refresh_token" => refresh}} =
      Flow.sign_in!("did:privy:sol")

    assert Flow.post(:revoke, %{"client_id" => client_id, "token" => refresh}).status == 200
    assert {:error, :unauthorized} = RegentOAuth.verify(access, RegentOAuth.resource())
    assert Flow.refresh(client_id, refresh).status == 400
  end
end

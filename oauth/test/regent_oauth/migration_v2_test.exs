defmodule RegentOAuth.MigrationV2Test do
  # Version 2 hashes the tokens of connections made before it, in place, so
  # those apps keep working with the plain tokens they already hold.
  use RegentOAuth.Case

  alias Boruta.Ecto.Token
  alias RegentOAuth.Repo
  alias RegentOAuth.Test.{Flow, Schema}

  @schema "regent_oauth_v1_test"

  setup do
    prefix = Application.fetch_env!(:regent_oauth, :prefix)
    Application.put_env(:regent_oauth, :prefix, @schema)
    on_exit(fn -> Application.put_env(:regent_oauth, :prefix, prefix) end)
    Schema.migrate!(@schema, [1])
    :ok
  end

  test "existing access, refresh and previous tokens become their hashes and keep working" do
    client_id = Flow.client!()
    expires_at = System.system_time(:second) + 3600

    row = fn value, refresh, previous ->
      Repo.insert!(%Token{
        type: "access_token",
        value: value,
        refresh_token: refresh,
        previous_token: previous,
        scope: "regent.identity.manage",
        expires_at: expires_at,
        client_id: client_id,
        sub: "did:privy:sol"
      })
    end

    row.("old-access", "old-refresh", nil)
    row.("live-access", "live-refresh", "old-access")
    code = Flow.code!(client_id, "did:privy:sol")

    Schema.migrate!(@schema, [1, 2])

    live =
      Repo.get_by!(Token,
        type: "access_token",
        sub: "did:privy:sol",
        previous_token: RegentOAuth.hash_token("old-access")
      )

    assert live.value == RegentOAuth.hash_token("live-access")
    assert live.refresh_token == RegentOAuth.hash_token("live-refresh")
    assert Repo.get_by!(Token, type: "code", client_id: client_id).value == code

    assert {:ok, %{subject: "did:privy:sol"}} =
             RegentOAuth.verify("live-access", RegentOAuth.resource())

    conn = Flow.refresh(client_id, "live-refresh")
    assert conn.status == 200

    assert {:ok, _} =
             RegentOAuth.verify(
               Jason.decode!(conn.resp_body)["access_token"],
               RegentOAuth.resource()
             )
  end
end

defmodule RegentPrivy.OwnerSessionTest do
  use ExUnit.Case, async: true

  alias RegentPrivy.OwnerSession

  @id "did:privy:owner"

  # Sign-out tells every open page of the sign-in to disconnect.
  defmodule Endpoint do
    def broadcast(topic, event, payload), do: send(self(), {:broadcast, topic, event, payload})
  end

  defp verified(expires_in) do
    %RegentPrivy.Session{
      app_id: "app",
      privy_user_id: @id,
      session_id: "sid",
      wallet_addresses: [],
      expires_at: System.system_time(:second) + expires_in
    }
  end

  defp signed_in_conn(expires_in) do
    Plug.Test.conn(:post, "/session")
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_private(:phoenix_endpoint, Endpoint)
    |> OwnerSession.put(verified(expires_in))
  end

  test "a sign-in lasts until the earlier token expires, then ends" do
    session = signed_in_conn(60) |> Plug.Conn.get_session()

    assert {:ok, @id, held} = OwnerSession.signed_in(session)
    assert {:ok, @id} = OwnerSession.still_signed_in(held)
    assert OwnerSession.browser(session) == %{id: @id, current: true}

    ended = signed_in_conn(0) |> Plug.Conn.get_session()

    assert OwnerSession.signed_in(ended) == :signed_out
    assert OwnerSession.browser(ended) == %{id: @id, current: false}
  end

  test "an empty session is signed out" do
    assert OwnerSession.signed_in(%{}) == :signed_out
    assert OwnerSession.browser(%{}) == nil
  end

  test "signing in names the page's socket and starts a fresh session id" do
    conn = signed_in_conn(60)

    assert Plug.Conn.get_session(conn, :live_socket_id) == "regent_privy_owner:#{@id}"
    assert conn.private.plug_session_info == :renew
  end

  test "sign-out drops the session and disconnects the sign-in's pages" do
    conn = signed_in_conn(60) |> OwnerSession.sign_out()

    assert conn.private.plug_session_info == :drop
    assert_received {:broadcast, "regent_privy_owner:" <> @id, "disconnect", %{}}
  end
end

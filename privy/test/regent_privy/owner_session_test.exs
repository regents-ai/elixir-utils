defmodule RegentPrivy.OwnerSessionTest do
  use ExUnit.Case, async: true

  alias RegentPrivy.OwnerSession

  @id "did:privy:owner"
  @csrf Plug.CSRFProtection.init([])

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

  # A page drawn for a browser: its session and the forms token the page holds.
  defp draw_page do
    conn =
      Plug.Test.conn(:get, "/")
      |> Plug.Test.init_test_session(%{})
      |> Plug.CSRFProtection.call(@csrf)

    token = Plug.CSRFProtection.get_csrf_token()
    {conn |> Plug.Conn.send_resp(200, "") |> Plug.Conn.get_session(), token}
  end

  # One post from that browser, through the forms-token check the app's pipeline
  # runs, answered after `action`.
  defp post(session, token, action \\ & &1) do
    Plug.Test.conn(:post, "/session")
    |> Plug.Test.init_test_session(session)
    |> Plug.Conn.put_req_header("x-csrf-token", token)
    |> Plug.Conn.put_private(:phoenix_endpoint, Endpoint)
    |> Plug.CSRFProtection.call(@csrf)
    |> action.()
    |> Plug.Conn.send_resp(200, "")
  end

  defp sign_in(expires_in) do
    {session, token} = draw_page()
    post(session, token, &OwnerSession.put(&1, verified(expires_in)))
  end

  test "a sign-in lasts until the earlier token expires, then ends" do
    session = sign_in(60) |> Plug.Conn.get_session()

    assert {:ok, @id, held} = OwnerSession.signed_in(session)
    assert {:ok, @id} = OwnerSession.still_signed_in(held)
    assert OwnerSession.browser(session) == %{id: @id, current: true}

    ended = sign_in(0) |> Plug.Conn.get_session()

    assert OwnerSession.signed_in(ended) == :signed_out
    assert OwnerSession.browser(ended) == %{id: @id, current: false}
  end

  test "an empty or missing session is signed out" do
    assert OwnerSession.signed_in(%{}) == :signed_out
    assert OwnerSession.signed_in(nil) == :signed_out
    assert OwnerSession.browser(%{}) == nil
  end

  test "signing in starts a fresh session whose new forms token replaces the page's" do
    {session, page_token} = draw_page()

    conn =
      post(
        Map.put(session, "kept_from_before", true),
        page_token,
        &OwnerSession.put(&1, verified(60))
      )

    signed_in = Plug.Conn.get_session(conn)
    [next_token] = Plug.Conn.get_resp_header(conn, "x-csrf-token")

    assert conn.private.plug_session_info == :renew
    refute Map.has_key?(signed_in, "kept_from_before")
    assert Plug.Conn.get_session(conn, :live_socket_id) == "regent_privy_owner:#{@id}"

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn -> post(signed_in, page_token) end
    assert %Plug.Conn{state: :sent} = post(signed_in, next_token)
  end

  test "each quiet renewal hands over the next forms token" do
    first = sign_in(60)
    [first_token] = Plug.Conn.get_resp_header(first, "x-csrf-token")

    renewed =
      first |> Plug.Conn.get_session() |> post(first_token, &OwnerSession.put(&1, verified(120)))

    [renewed_token] = Plug.Conn.get_resp_header(renewed, "x-csrf-token")
    session = Plug.Conn.get_session(renewed)

    assert {:ok, @id, _held} = OwnerSession.signed_in(session)
    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn -> post(session, first_token) end
    assert %Plug.Conn{state: :sent} = post(session, renewed_token)
  end

  test "sign-out drops the session and disconnects the sign-in's pages" do
    signed_in = sign_in(60)
    [token] = Plug.Conn.get_resp_header(signed_in, "x-csrf-token")

    conn = signed_in |> Plug.Conn.get_session() |> post(token, &OwnerSession.sign_out/1)

    assert conn.private.plug_session_info == :drop
    assert_received {:broadcast, "regent_privy_owner:" <> @id, "disconnect", %{}}
  end
end

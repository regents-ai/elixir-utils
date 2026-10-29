defmodule RegentPrivy.OwnerSession do
  @moduledoc """
  A Privy sign-in kept in the app's cookie session, with no table: the Privy id
  and the time the earlier of its two tokens expires. The sign-in ends then.

  It answers `RegentPrivy.Owners`' two sign-in callbacks, so an app's owners
  module names its owners and hands the rest here:

      @behaviour RegentPrivy.Owners

      def owners, do: ["did:privy:..."]
      defdelegate signed_in(session), to: RegentPrivy.OwnerSession
      defdelegate still_signed_in(held), to: RegentPrivy.OwnerSession

  The app's sign-in route verifies the pair (`RegentPrivy.Proof.pair/1`, then
  `RegentPrivy.Session.verify/2`) and calls `put/2`; its sign-out route calls
  `sign_out/1`, which also disconnects every open page of that sign-in. The page
  hands `browser/1` to `startPrivySignIn` as `session`, so the browser signs the
  same person back in from Privy's next token once this sign-in ends.
  """

  @key "regent_privy_owner"

  @doc "Keeps the verified sign-in in the session, under a fresh session id."
  @spec put(Plug.Conn.t(), RegentPrivy.Session.t()) :: Plug.Conn.t()
  def put(conn, %RegentPrivy.Session{privy_user_id: id, expires_at: expires_at}) do
    conn
    |> Plug.Conn.configure_session(renew: true)
    |> Plug.Conn.put_session(@key, %{"id" => id, "expires_at" => expires_at})
    |> Plug.Conn.put_session(:live_socket_id, socket_id(id))
  end

  @doc "Ends the sign-in and disconnects every page it has open."
  @spec sign_out(Plug.Conn.t()) :: Plug.Conn.t()
  def sign_out(conn) do
    case Plug.Conn.get_session(conn, @key) do
      %{"id" => id} ->
        Phoenix.Controller.endpoint_module(conn).broadcast(socket_id(id), "disconnect", %{})

      nil ->
        :ok
    end

    Plug.Conn.configure_session(conn, drop: true)
  end

  @doc "The sign-in `session` holds, while it lasts: a `RegentPrivy.Owners` callback."
  @spec signed_in(map()) :: {:ok, String.t(), {String.t(), integer()}} | :signed_out
  def signed_in(%{@key => %{"id" => id, "expires_at" => expires_at}}) do
    case still_signed_in({id, expires_at}) do
      {:ok, id} -> {:ok, id, {id, expires_at}}
      :signed_out -> :signed_out
    end
  end

  def signed_in(_session), do: :signed_out

  @doc "Whether that sign-in still lasts: a `RegentPrivy.Owners` callback."
  @spec still_signed_in({String.t(), integer()}) :: {:ok, String.t()} | :signed_out
  def still_signed_in({id, expires_at}) do
    if System.system_time(:second) < expires_at, do: {:ok, id}, else: :signed_out
  end

  @doc """
  What the page tells `startPrivySignIn`: whose sign-in this session holds and
  whether it still lasts, or nil when no one has signed in.
  """
  @spec browser(map()) :: %{id: String.t(), current: boolean()} | nil
  def browser(%{@key => %{"id" => id} = held}),
    do: %{id: id, current: signed_in(%{@key => held}) != :signed_out}

  def browser(_session), do: nil

  defp socket_id(id), do: "regent_privy_owner:" <> id
end

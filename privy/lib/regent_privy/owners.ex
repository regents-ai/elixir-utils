defmodule RegentPrivy.Owners do
  @moduledoc """
  Keeps pages for the Privy accounts an app names, its owners. Anyone else gets
  the app's ordinary not-found page, so the page's existence is not shown either.

  The app names one module that implements this behaviour: the owners' Privy
  ids, who a session is signed in as, and whether that sign-in still holds.

      plug RegentPrivy.Owners, sign_in: MyAppWeb.Owner, router: MyAppWeb.Router

      live_session :owner, on_mount: [{RegentPrivy.Owners, MyAppWeb.Owner}] do
        ...
      end

  As a plug it checks the request. As an `on_mount` hook it checks the session
  the page connects with (the endpoint's socket passes `connect_info: [session:
  ...]`), then checks again on every navigation, press and message the page
  receives, so a sign-in that ends or lapses cannot keep acting on the page; a
  page that fails a check is sent to `/`. A press aimed at a LiveComponent
  (`phx-target={@myself}`) skips the page's hooks and is not checked, so an
  owner page handles its presses on the page itself. A signed-in account that is not an owner is logged with its Privy id when
  it asks for a page, so an owner's id can be read from the log the first time
  they sign in.
  """

  @behaviour Plug

  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, get_connect_info: 2, redirect: 2]

  require Logger

  @doc "The owners' Privy ids."
  @callback owners() :: [String.t()]

  @doc """
  Who `session` is signed in as, and what `c:still_signed_in/1` needs to check
  that sign-in again later.
  """
  @callback signed_in(session :: map()) :: {:ok, String.t(), held :: term()} | :signed_out

  @doc "Who the sign-in `c:signed_in/1` found is signed in as now, if it still holds."
  @callback still_signed_in(held :: term()) :: {:ok, String.t()} | :signed_out

  @impl Plug
  def init(opts), do: Keyword.validate!(opts, [:sign_in, :router])

  @impl Plug
  def call(conn, opts) do
    sign_in = Keyword.fetch!(opts, :sign_in)

    case sign_in.signed_in(Plug.Conn.get_session(conn)) do
      {:ok, id, _held} ->
        if id in sign_in.owners(), do: conn, else: refuse(conn, opts, id)

      :signed_out ->
        not_found(conn, opts)
    end
  end

  def on_mount(sign_in, _params, session, socket) do
    session = if connected?(socket), do: get_connect_info(socket, :session), else: session

    with {:ok, id, held} <- sign_in.signed_in(session),
         true <- id in sign_in.owners() do
      recheck = fn socket -> recheck(socket, sign_in, held) end

      {:cont,
       socket
       |> attach_hook(:regent_privy_owner_params, :handle_params, fn _params, _uri, socket ->
         recheck.(socket)
       end)
       |> attach_hook(:regent_privy_owner_event, :handle_event, fn _event, _params, socket ->
         recheck.(socket)
       end)
       |> attach_hook(:regent_privy_owner_info, :handle_info, fn _message, socket ->
         recheck.(socket)
       end)}
    else
      _signed_out_or_not_an_owner -> leave(socket)
    end
  end

  defp recheck(socket, sign_in, held) do
    with {:ok, id} <- sign_in.still_signed_in(held),
         true <- id in sign_in.owners() do
      {:cont, socket}
    else
      _ended_or_no_longer_an_owner -> leave(socket)
    end
  end

  defp leave(socket), do: {:halt, redirect(socket, to: "/")}

  defp refuse(conn, opts, id) do
    Logger.info("Privy account #{id} is not an owner")
    not_found(conn, opts)
  end

  defp not_found(conn, opts),
    do: raise(Phoenix.Router.NoRouteError, conn: conn, router: Keyword.fetch!(opts, :router))
end

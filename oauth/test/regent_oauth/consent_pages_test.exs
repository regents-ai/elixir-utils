defmodule RegentOAuth.ConsentPagesTest do
  # The Connect screen shows one row for each permission the app asks for, in
  # the site's words, then the Never row when the site gives one, and names only
  # the host it returns to. Connected apps lists each of the person's apps with
  # the day it connected and its Disconnect form (Sean, 14 Nov 2026: "three
  # short rows of what the app may do ... Connected apps as rows with
  # Disconnect").
  use RegentOAuth.Case

  import Ecto.Query
  import Plug.Conn
  import Plug.Test

  alias RegentOAuth.Test.{Flow, Repo, Site}

  @verifier String.duplicate("v", 43)
  @rooms "regent.rooms.read"

  defmodule WiderSite do
    @moduledoc "The test site with a second permission."
    @behaviour RegentOAuth

    @impl true
    def config,
      do:
        Keyword.put(Site.config(), :additional_scopes, %{
          "regent.rooms.read" => {"Reads", "rooms"}
        })

    @impl true
    defdelegate repo, to: Site
    @impl true
    defdelegate current_subject(conn), to: Site
    @impl true
    defdelegate active_subject?(subject), to: Site
  end

  defmodule NoNeverSite do
    @moduledoc "The test site with no Never line."
    @behaviour RegentOAuth

    @impl true
    def config, do: Keyword.delete(Site.config(), :never)

    @impl true
    defdelegate repo, to: Site
    @impl true
    defdelegate current_subject(conn), to: Site
    @impl true
    defdelegate active_subject?(subject), to: Site
  end

  defp as(site, fun) do
    Application.put_env(:regent_oauth, :site, site)
    fun.()
  after
    Application.put_env(:regent_oauth, :site, Site)
  end

  defp client!(redirect_uris) do
    conn =
      Flow.post(:register, %{
        "client_name" => "Claude",
        "redirect_uris" => redirect_uris,
        "token_endpoint_auth_method" => "none"
      })

    201 = conn.status
    Jason.decode!(conn.resp_body)["client_id"]
  end

  defp connect_page(client_id, redirect_uri, scope) do
    query =
      URI.encode_query(%{
        "client_id" => client_id,
        "redirect_uri" => redirect_uri,
        "response_type" => "code",
        "scope" => scope,
        "state" => "state",
        "resource" => RegentOAuth.resource(),
        "code_challenge" => :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false),
        "code_challenge_method" => "S256"
      })

    page =
      conn(:get, "/oauth/authorize?" <> query)
      |> init_test_session(%{})
      |> assign(:subject, "did:privy:sol")
      |> RegentOAuth.Consent.authorize()

    200 = page.status
    page
  end

  defp connections_page(subject) do
    page =
      conn(:get, "/oauth/connections")
      |> init_test_session(%{})
      |> assign(:subject, subject)
      |> RegentOAuth.Consent.connections()

    200 = page.status
    page.resp_body
  end

  # Each row of the Connect screen's list, as the {lead, detail} it shows.
  defp rows(page) do
    ~r{<li><span><strong>(.*?)</strong> (.*?)</span></li>}
    |> Regex.scan(page.resp_body, capture: :all_but_first)
    |> Enum.map(&List.to_tuple/1)
  end

  defp never, do: {"Never", Keyword.fetch!(Site.config(), :never)}

  defp access_tokens(client_id),
    do:
      from(t in Boruta.Ecto.Token, where: t.client_id == ^client_id and t.type == "access_token")

  test "the Connect screen has a row for each permission asked for, then the Never row" do
    callback = "https://claude.ai/api/mcp/auth_callback"
    client_id = as(WiderSite, fn -> client!([callback]) end)
    identity = Keyword.fetch!(Site.config(), :permission)
    rooms = WiderSite.config()[:additional_scopes][@rooms]

    as(WiderSite, fn ->
      assert rows(connect_page(client_id, callback, RegentOAuth.scope())) == [identity, never()]

      assert rows(connect_page(client_id, callback, "#{RegentOAuth.scope()} #{@rooms}")) ==
               [identity, rooms, never()]

      assert rows(connect_page(client_id, callback, @rooms)) == [rooms, never()]
    end)
  end

  test "a site with no Never line shows only the permissions" do
    callback = "https://claude.ai/api/mcp/auth_callback"
    client_id = client!([callback])
    identity = Keyword.fetch!(Site.config(), :permission)

    as(NoNeverSite, fn ->
      assert rows(connect_page(client_id, callback, RegentOAuth.scope())) == [identity]
    end)
  end

  test "the Connect screen names only the host of the return the request will use" do
    first = "https://claude.ai/api/mcp/auth_callback"
    second = "https://desktop.claude.example/oauth/done"
    client_id = client!([first, second])

    for {callback, other} <- [{first, second}, {second, first}] do
      page = connect_page(client_id, callback, RegentOAuth.scope())

      [links] =
        Regex.run(~r{<ul class="rg-utility__links">(.*?)</ul>}s, page.resp_body,
          capture: :all_but_first
        )

      assert links =~ URI.parse(callback).host
      refute links =~ URI.parse(other).host
      refute page.resp_body =~ URI.parse(callback).path
      refute page.resp_body =~ "https://" <> URI.parse(callback).host
    end
  end

  test "Allow and Cancel post the decision with this consent's own key and the form token" do
    callback = "https://claude.ai/api/mcp/auth_callback"
    page = connect_page(client!([callback]), callback, RegentOAuth.scope())
    pending = get_session(page, :regent_oauth_request)

    [form] =
      Regex.run(~r{<form method="post" action="/oauth/authorize".*?</form>}s, page.resp_body)

    assert Regex.scan(~r{name="(\w+)" value="([^"]*)"}, form, capture: :all_but_first) == [
             ["_csrf_token", Plug.CSRFProtection.get_csrf_token()],
             ["approval_key", pending["nonce"]],
             ["decision", "allow"],
             ["decision", "deny"]
           ]
  end

  test "Connected apps lists each of the person's apps, newest first, with the day it connected and its Disconnect" do
    {earlier, _} = Flow.sign_in!("did:privy:sol")
    {later, %{"refresh_token" => refresh}} = Flow.sign_in!("did:privy:sol")
    {elsewhere, _} = Flow.sign_in!("did:privy:luna")

    # A refresh adds a newer token; the app still connected on its first one's day.
    200 = Flow.refresh(later, refresh).status

    Repo.update_all(access_tokens(earlier), set: [inserted_at: ~U[2026-11-02 23:59:00.000000Z]])

    Repo.update_all(
      where(access_tokens(later), [t], not is_nil(t.refresh_token_revoked_at)),
      set: [inserted_at: ~U[2026-11-14 00:01:00.000000Z]]
    )

    page = connections_page("did:privy:sol")

    assert Regex.scan(~r{<time datetime="([\d-]+)"}, page, capture: :all_but_first) ==
             [["2026-11-14"], ["2026-11-02"]]

    assert Regex.scan(
             ~r{<form method="post" action="/oauth/connections/revoke">\s*<input type="hidden" name="_csrf_token" value="[^"]+">\s*<input type="hidden" name="client_id" value="([^"]+)">},
             page,
             capture: :all_but_first
           ) == [[later], [earlier]]

    refute page =~ elsewhere

    # Disconnecting and connecting again starts the day anew.
    {:ok, :ok} = RegentOAuth.revoke_client("did:privy:sol", earlier)
    200 = Flow.exchange(earlier, Flow.code!(earlier, "did:privy:sol")).status
    today = Date.to_iso8601(Date.utc_today())

    assert Regex.scan(~r{<time datetime="([\d-]+)"}, connections_page("did:privy:sol"),
             capture: :all_but_first
           ) == [[today], ["2026-11-14"]]
  end
end

defmodule RegentOAuth.ClientScopesTest do
  # An app keeps the scopes it was registered with; the consent page only reads
  # it. When the site starts offering a scope, its migration gives every app the
  # scopes it lacks (`RegentOAuth.Migration.ClientScopes`), and only adds.
  use RegentOAuth.Case

  import Ecto.Query

  alias Boruta.Ecto.{Client, Scope}
  alias Boruta.Oauth.Authorization
  alias RegentOAuth.Repo
  alias RegentOAuth.Test.{Flow, Schema, Site}

  @schema "regent_oauth_scopes_test"
  @both "regent.identity.manage regent.rooms.read"

  defmodule WiderSite do
    @moduledoc "The test site after it starts offering a second scope."
    @behaviour RegentOAuth

    @impl true
    def config,
      do: Keyword.put(Site.config(), :additional_scopes, %{"regent.rooms.read" => "Read rooms."})

    @impl true
    defdelegate repo, to: Site
    @impl true
    defdelegate current_subject(conn), to: Site
    @impl true
    defdelegate active_subject?(subject), to: Site
  end

  setup do
    prefix = Application.fetch_env!(:regent_oauth, :prefix)
    Application.put_env(:regent_oauth, :prefix, @schema)

    on_exit(fn ->
      Application.put_env(:regent_oauth, :prefix, prefix)
      Application.put_env(:regent_oauth, :site, Site)
    end)

    Schema.migrate!(@schema, [1, 2])
    :ok
  end

  defp as(site, fun) do
    Application.put_env(:regent_oauth, :site, site)
    fun.()
  after
    Application.put_env(:regent_oauth, :site, Site)
  end

  defp links do
    from(link in "oauth_clients_scopes",
      join: scope in Scope,
      on: scope.id == link.scope_id,
      select: {link.id, type(link.client_id, Ecto.UUID), scope.name},
      order_by: link.id
    )
    |> Repo.all()
  end

  defp scope_rows, do: Scope |> Repo.all() |> Enum.map(&{&1.id, &1.name}) |> Enum.sort()
  defp clients, do: Client |> Repo.all() |> Enum.sort_by(& &1.id)

  # As a machine of the new release does when it starts.
  defp check_scopes(client_id, scopes) do
    Boruta.Ecto.Clients.invalidate(%Boruta.Oauth.Client{id: client_id})

    Authorization.Scope.authorize(
      scope: scopes,
      against: %{client: Boruta.ClientsAdapter.get_client(client_id)}
    )
  end

  test "each app gains the scopes it lacks; every other row stays as it was" do
    earlier = Flow.client!()
    later = as(WiderSite, &Flow.client!/0)
    private = Flow.client!()
    Repo.update_all(where(Client, id: ^private), set: [confidential: true])

    # A scope the site no longer offers, still on the app that had it.
    retired = Repo.insert!(%Scope{name: "regent.retired"})

    Repo.insert_all("oauth_clients_scopes", [
      %{client_id: Ecto.UUID.dump!(earlier), scope_id: Ecto.UUID.dump!(retired.id)}
    ])

    before = %{links: links(), scopes: scope_rows(), clients: clients()}
    assert {:error, %{error: :invalid_scope}} = check_scopes(earlier, @both)

    Schema.migrate!(@schema, [1, 2, 3])

    assert [{_id, ^earlier, "regent.rooms.read"}] = links() -- before.links
    assert before.links -- links() == []
    assert scope_rows() == before.scopes
    assert clients() == before.clients
    assert {:ok, _} = check_scopes(earlier, @both)
    assert {:ok, _} = check_scopes(later, @both)
    assert {:ok, "regent.retired"} = check_scopes(earlier, "regent.retired")
  end

  test "a scope no app has yet gets its row, and every app gets it" do
    earlier = Flow.client!()
    before = scope_rows()

    Schema.migrate!(@schema, [1, 2, 3])

    assert [{_id, "regent.rooms.read"}] = scope_rows() -- before
    assert {:ok, _} = check_scopes(earlier, @both)
  end

  test "the consent page reads the app and writes nothing, even when a scope was added" do
    client_id = Flow.client!()
    before = {clients(), links()}

    assert {:ok, %Client{id: ^client_id}} =
             as(WiderSite, fn ->
               RegentOAuth.Protocol.request_client(%{
                 "client_id" => client_id,
                 "redirect_uri" => "https://claude.ai/api/mcp/auth_callback"
               })
             end)

    assert {clients(), links()} == before
  end
end

defmodule RegentOAuth.Migration.ClientScopes do
  @moduledoc """
  Gives every app the consent page serves the named scopes it lacks. Called by
  the owning site's migration when the site starts offering a scope, naming the
  site's full list of scopes as they stand then:

      def up do
        RegentOAuth.Migration.ClientScopes.up(["regent.identity.manage", "site.agent"])
      end

  It only inserts: a scope row for a name the table lacks, and a link from each
  public PKCE app (the only kind the consent page serves) to each named scope it
  lacks. Rows already there are left as they are, nothing is updated or deleted,
  and a scope taken out of the configuration stays on the apps that have it. An
  app gains no access by it: every token still needs the person's consent for
  each scope, and only the running site's configured scopes are ever granted.

  Boruta keeps apps in memory, so this runs in the release step, before the new
  release serves; each machine then reads the apps afresh as it starts. It has
  no `down`: it keeps no record of which links it made.
  """
  use Ecto.Migration

  @name ~r/\A[a-z][a-z0-9_.:-]{0,127}\z/

  def up([_ | _] = names) do
    for name <- names, !(is_binary(name) and Regex.match?(@name, name)) do
      raise ArgumentError, "not a scope name: #{inspect(name)}"
    end

    # A site names its schema in `migration_default_prefix`, which `prefix/0`
    # does not report.
    prefix = prefix() || repo().config()[:migration_default_prefix]
    table = fn name -> if prefix, do: ~s("#{prefix}".#{name}), else: name end
    # Every name matched @name, so none can close the quotes.
    names = "ARRAY[" <> Enum.map_join(names, ", ", &"'#{&1}'") <> "]::varchar[]"

    execute("""
    INSERT INTO #{table.("oauth_scopes")} (id, name, public, inserted_at, updated_at)
    SELECT gen_random_uuid(), name, false, now(), now() FROM unnest(#{names}) AS name
    ON CONFLICT (name) DO NOTHING
    """)

    execute("""
    INSERT INTO #{table.("oauth_clients_scopes")} (client_id, scope_id)
    SELECT client.id, scope.id
    FROM #{table.("oauth_clients")} AS client
    JOIN #{table.("oauth_scopes")} AS scope ON scope.name = ANY(#{names})
    WHERE client.confidential = false AND client.pkce = true
    ON CONFLICT (client_id, scope_id) DO NOTHING
    """)
  end
end

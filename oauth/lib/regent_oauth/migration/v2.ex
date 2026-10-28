defmodule RegentOAuth.Migration.V2 do
  @moduledoc """
  Version 2 of the provider's schema: access and refresh tokens are kept only
  as their SHA-256 hash (`RegentOAuth.hash_token/1`). Called by the owning
  site's migration after version 1 (`RegentOAuth.Migration`):

      def up, do: RegentOAuth.Migration.V2.up()

  It rewrites every access token row in place: `value`, `refresh_token` and
  `previous_token` become the hash of what they held, so a connection made
  before it keeps working, its client still presenting the plain token. No
  plain token is left in the table. Authorization codes, which live a minute
  and are spent once, are left as Boruta keeps them.

  The issuer and resource columns lose the defaults version 1 once gave them:
  the provider now writes both on each code and token as it is issued, from the
  running site's configuration, so no migration needs the site's address. Rows
  already there keep the values they have.

  It cannot be undone, because a hash does not give back its token. It changes
  existing rows, so it is a protected change on any shared database.
  """
  use Ecto.Migration

  def up do
    # A site names its schema in `migration_default_prefix`, which `prefix/0`
    # does not report.
    prefix = prefix() || repo().config()[:migration_default_prefix]
    table = if prefix, do: ~s("#{prefix}".oauth_tokens), else: "oauth_tokens"

    execute("""
    ALTER TABLE #{table}
      ALTER COLUMN oauth_issuer DROP DEFAULT,
      ALTER COLUMN oauth_issuer DROP NOT NULL,
      ALTER COLUMN mcp_resource DROP DEFAULT,
      ALTER COLUMN mcp_resource DROP NOT NULL
    """)

    execute("""
    UPDATE #{table}
    SET value = #{hash("value")},
        refresh_token = #{hash("refresh_token")},
        previous_token = #{hash("previous_token")}
    WHERE type = 'access_token'
    """)
  end

  # The same lowercase hex SHA-256 as RegentOAuth.hash_token/1; NULL stays NULL.
  defp hash(column), do: "encode(sha256(convert_to(#{column}, 'UTF8')), 'hex')"
end

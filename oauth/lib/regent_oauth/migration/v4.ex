defmodule RegentOAuth.Migration.V4 do
  @moduledoc """
  Version 4 of the provider's schema: every column an accepted request can
  fill past 255 characters loses that limit. A code's `state` and callback
  (`oauth_tokens.state` and `redirect_uri`) are as long as the app sends them,
  and OpenAI's apps send a `state` longer than 255 characters, which made Allow
  fail. An app's callbacks (`oauth_clients.redirect_uris`) and the address of
  its keys (`jwks_uri`) may each be a longer address, and its `name`, at most
  100 characters as a person reads them, may hold more as the database counts
  them. Called by the owning site's migration after version 3:

      def up, do: RegentOAuth.Migration.V4.up()

  Each column becomes `text`, and the callbacks become `varchar[]`, a list of
  strings without a limit: changing a list's type to `text[]` would rewrite
  every row, since each stored list names the type of what it holds. Dropping
  the limit changes no stored row and rewrites nothing in PostgreSQL, and no
  index covers these columns. Nothing is dropped, renamed or narrowed. Each of
  the two tables is locked exclusively while its definition changes, which
  waits for transactions already using it and holds back requests that arrive
  meanwhile, for a moment. A machine already serving keeps queries prepared
  for the old types: each such query fails once on each of its database
  connections ("cached plan must not change result type") and is prepared
  afresh on the next try. A machine started after the migration is not
  affected.
  """
  use Ecto.Migration

  def up do
    alter table(:oauth_tokens) do
      modify(:state, :text)
      modify(:redirect_uri, :text)
    end

    alter table(:oauth_clients) do
      modify(:name, :text)
      modify(:redirect_uris, {:array, :varchar})
      modify(:jwks_uri, :text)
    end
  end
end

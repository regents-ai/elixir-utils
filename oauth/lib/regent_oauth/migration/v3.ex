defmodule RegentOAuth.Migration.V3 do
  @moduledoc """
  Version 3 of the provider's schema: `oauth_client_documents`, the addresses
  of apps that publish their own identity (`RegentOAuth.ClientDocuments`), each
  naming the client row it was recorded as and when to read it again. Called by
  the owning site's migration after version 2:

      def up, do: RegentOAuth.Migration.V3.up()

  It only adds a table and its index; no existing row or column changes. The
  table is new and empty, so its reference to `oauth_clients` is checked at
  once without scanning anything.
  """
  use Ecto.Migration

  def up do
    create table(:oauth_client_documents, primary_key: false) do
      add(:url, :text, primary_key: true)

      add(:client_id, references(:oauth_clients, type: :uuid, on_delete: :delete_all),
        null: false
      )

      add(:refresh_at, :utc_datetime_usec, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:oauth_client_documents, [:client_id]))
  end
end

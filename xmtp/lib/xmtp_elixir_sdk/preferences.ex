defmodule XmtpElixirSdk.Preferences do
  @moduledoc """
  Consent and inbox-state operations.
  """

  alias XmtpElixirSdk.Client
  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Events
  alias XmtpElixirSdk.Internal.{ConversationServer, IdentityServer, StatsServer}
  alias XmtpElixirSdk.Types

  @spec sync(Client.t()) :: {:ok, Types.SyncResult.t()} | {:error, Error.t()}
  def sync(%Client{} = client) do
    with {:ok, inbox_state} <- IdentityServer.inbox_state(client, false) do
      synced = length(inbox_state.identifiers)
      StatsServer.bump_api(client.runtime, :query_commit_log)

      Events.emit(
        client.runtime,
        {:preferences, client.id},
        %Events.PreferenceUpdated{
          updates: [
            %{
              type: :hmac_key_update,
              key: client.installation_id_bytes,
              installation_id: client.installation_id
            }
          ]
        }
      )

      {:ok, %Types.SyncResult{synced: synced, eligible: synced}}
    end
  end

  @spec inbox_state(Client.t()) :: {:ok, Types.InboxState.t()} | {:error, Error.t()}
  def inbox_state(%Client{} = client), do: IdentityServer.inbox_state(client, false)

  @spec fetch_inbox_state(Client.t()) :: {:ok, Types.InboxState.t()} | {:error, Error.t()}
  def fetch_inbox_state(%Client{} = client), do: IdentityServer.inbox_state(client, true)

  @spec get_inbox_states(Client.t(), [String.t()]) ::
          {:ok, [Types.InboxState.t()]} | {:error, Error.t()}
  def get_inbox_states(%Client{} = client, inbox_ids) do
    IdentityServer.inbox_state_from_inbox_ids(client, inbox_ids, false)
  end

  @spec fetch_inbox_states(Client.t(), [String.t()]) ::
          {:ok, [Types.InboxState.t()]} | {:error, Error.t()}
  def fetch_inbox_states(%Client{} = client, inbox_ids) do
    IdentityServer.inbox_state_from_inbox_ids(client, inbox_ids, true)
  end

  @spec set_consent_states(Client.t(), [map()]) :: {:ok, :ok} | {:error, Error.t()}
  def set_consent_states(%Client{} = client, records) do
    with {:ok, :ok} <- IdentityServer.apply_consent_records(client, records) do
      :ok = ConversationServer.apply_consent_records(client, records)
      {:ok, :ok}
    end
  end

  @spec get_consent_state(Client.t(), Types.consent_entity_type(), String.t()) ::
          {:ok, Types.consent_state()} | {:error, Error.t()}
  def get_consent_state(%Client{} = client, :group_id, entity) do
    ConversationServer.consent_for_group(client, entity)
  end

  def get_consent_state(%Client{} = client, :inbox_id, entity) do
    IdentityServer.consent_for_inbox(client, entity)
  end
end

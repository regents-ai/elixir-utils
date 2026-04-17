defmodule XmtpElixirSdk.Preferences do
  @moduledoc """
  Consent, inbox-state, and preference-sync operations.

  This module deals with information that is about the client or inbox rather
  than about one specific conversation.

  Use it to:

  - sync preference state
  - inspect inbox state
  - fetch inbox states for other inbox ids
  - set and read consent state

  Consent updates use one canonical shape:

  - inbox consent: `%{entity: "inbox-id", state: :allowed | :denied | :unknown}`
  - group consent: `%{group_id: "group-id", state: :allowed | :denied | :unknown}`

  Preference events emit `XmtpElixirSdk.Types.PreferenceUpdate` structs only.
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
          updates: [%Types.PreferenceUpdate{kind: :hmac_key, consent: nil}]
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

  @spec set_consent_states(Client.t(), [Types.consent_record()]) ::
          {:ok, :ok} | {:error, Error.t()}
  def set_consent_states(%Client{} = client, records) do
    with {:ok, normalized_records} <- normalize_consent_records(records),
         {:ok, :ok} <- IdentityServer.apply_consent_records(client, normalized_records) do
      :ok = ConversationServer.apply_consent_records(client, normalized_records)
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

  defp normalize_consent_records(records) when is_list(records) do
    Enum.reduce_while(records, {:ok, []}, fn record, {:ok, acc} ->
      case normalize_consent_record(record) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      {:error, error} -> {:error, error}
    end
  end

  defp normalize_consent_records(_records) do
    {:error, Error.invalid_argument("invalid consent records", %{})}
  end

  defp normalize_consent_record(%{group_id: group_id, state: state} = record)
       when is_binary(group_id) and state in [:unknown, :allowed, :denied] do
    if map_size(Map.take(record, [:group_id, :state])) == map_size(record) do
      {:ok, %{group_id: group_id, state: state}}
    else
      {:error, Error.invalid_argument("invalid consent record", %{record: record})}
    end
  end

  defp normalize_consent_record(%{entity: entity, state: state} = record)
       when is_binary(entity) and state in [:unknown, :allowed, :denied] do
    if map_size(Map.take(record, [:entity, :state])) == map_size(record) do
      {:ok, %{entity: entity, state: state}}
    else
      {:error, Error.invalid_argument("invalid consent record", %{record: record})}
    end
  end

  defp normalize_consent_record(record) do
    {:error, Error.invalid_argument("invalid consent record", %{record: record})}
  end
end

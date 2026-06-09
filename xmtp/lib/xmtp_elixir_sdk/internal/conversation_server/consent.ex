defmodule XmtpElixirSdk.Internal.ConversationServer.Consent do
  @moduledoc "Consent record application and consent-state lookup for conversation server state."

  alias XmtpElixirSdk.Internal.ConversationServer.Conversations

  def apply_records(state, records) do
    Enum.reduce(records, state, &apply_record(&2, &1))
  end

  def for_group(state, group_id) do
    case Conversations.fetch(state, group_id) do
      {:ok, conversation} -> {:ok, conversation.consent_state}
      {:error, _} -> {:ok, :unknown}
    end
  end

  defp apply_record(state, record) do
    entity = Map.get(record, :group_id) || Map.get(record, :entity)
    state_value = Map.get(record, :state, :unknown)

    cond do
      Map.has_key?(state.conversations, entity) ->
        update_in(state.conversations[entity], fn conversation ->
          %{conversation | consent_state: state_value}
        end)

      is_binary(entity) ->
        update_members_by_inbox(state, entity, fn member ->
          %{member | consent_state: state_value}
        end)

      true ->
        state
    end
  end

  defp update_members_by_inbox(state, inbox_id, updater) do
    conversations =
      Enum.into(state.conversations, %{}, fn {id, conversation} ->
        updated_members =
          Enum.map(conversation.members, fn member ->
            if member.inbox_id == inbox_id, do: updater.(member), else: member
          end)

        {id, %{conversation | members: updated_members}}
      end)

    %{state | conversations: conversations}
  end
end

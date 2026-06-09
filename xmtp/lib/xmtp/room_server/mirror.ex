defmodule Xmtp.RoomServer.Mirror do
  @moduledoc "Persists the local room mirror (messages, snapshots, tombstones) and broadcasts refreshes."

  alias Xmtp.Log
  alias Xmtp.Manager
  alias Xmtp.Room
  alias Xmtp.RoomServer.Membership
  alias XmtpElixirSdk.Messages
  alias XmtpElixirSdk.Types

  def persist_streamed_message(%{repo: repo, room: room} = state, message) do
    sender_membership = Membership.fetch_membership_for_inbox(repo, room, message.sender_inbox_id)

    _ =
      Log.append_message(repo, room, message, %{
        wallet_address: sender_membership && sender_membership.wallet_address,
        kind: sender_membership && sender_membership.principal_kind,
        label: sender_membership && sender_membership.display_name
      })

    updated_room =
      room
      |> Room.changeset(%{last_activity_ns: message.sent_at_ns})
      |> repo.update!()

    %{state | room: updated_room}
  end

  def persist_room_snapshot(
        %{repo: repo, room: room} = state,
        %{id: _conversation_id} = conversation
      ) do
    updated_room =
      room
      |> Room.changeset(%{
        room_name: Map.get(conversation, :name),
        description: Map.get(conversation, :description),
        app_data: Map.get(conversation, :app_data),
        last_activity_ns: Map.get(conversation, :last_activity_ns),
        snapshot: room_snapshot(conversation)
      })
      |> repo.update!()

    %{state | room: updated_room, public_room: conversation}
  end

  def room_snapshot(%{id: _conversation_id} = conversation) do
    %{
      name: Map.get(conversation, :name),
      description: Map.get(conversation, :description),
      app_data: Map.get(conversation, :app_data),
      created_at_ns: Map.get(conversation, :created_at_ns),
      last_activity_ns: Map.get(conversation, :last_activity_ns),
      image_url: Map.get(conversation, :image_url),
      added_by_inbox_id: Map.get(conversation, :added_by_inbox_id)
    }
  end

  def tombstone_room_message(%{repo: repo, room: room}, message_id, moderator_wallet) do
    case Log.tombstone_message(repo, room, message_id, moderator_wallet) do
      {:ok, entry} -> {:ok, entry}
      {:error, :message_not_found} -> {:error, :message_not_found}
      {:error, _changeset} -> {:error, :message_not_found}
    end
  end

  def fetch_message(client, message_id) do
    case Messages.get_by_id(client, message_id) do
      {:ok, %Types.Message{} = message} -> {:ok, message}
      {:ok, nil} -> {:error, :message_not_found}
      {:error, error} -> {:error, error}
    end
  end

  def broadcast_refresh!(state) do
    Phoenix.PubSub.broadcast(
      state.pubsub,
      Manager.topic(state.manager, state.definition.key),
      {:xmtp_public_room, :refresh}
    )
  end
end

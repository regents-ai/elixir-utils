defmodule Xmtp.RoomServer.Panel do
  @moduledoc "Builds the room panel presentation (status, copy, messages) from room server state."

  alias Xmtp.Log
  alias Xmtp.MessageLog
  alias Xmtp.Principal
  alias Xmtp.RoomPanel
  alias Xmtp.RoomServer.Membership

  @message_limit 24

  def build(state, principal, copy_override \\ nil, pending_request_id \\ nil)

  def build(
        %{mode: :unavailable, definition: definition},
        principal,
        copy_override,
        pending_request_id
      ) do
    connected_wallet = principal && Principal.wallet(principal)

    RoomPanel.new!(%{
      room_key: definition.key,
      xmtp_group_id: nil,
      name: definition.name,
      status: :disabled,
      membership: if(connected_wallet, do: :not_joined, else: :not_connected),
      connected_wallet: connected_wallet,
      can_join: false,
      can_send: false,
      can_moderate: Membership.moderator_wallet?(definition, connected_wallet),
      pending_signature_request_id: pending_request_id,
      member_count: 0,
      active_member_count: 0,
      capacity: definition.capacity,
      seats_remaining: definition.capacity,
      presence_ttl_seconds: div(definition.presence_timeout_ms, 1_000),
      last_synced_at: nil,
      messages: [],
      user_copy: RoomPanel.copy(copy_override || "This room is unavailable right now.")
    })
  end

  def build(
        %{mode: :ready, room: room, definition: definition} = state,
        principal,
        copy_override,
        pending_signature_request_id
      ) do
    connected_wallet = principal && Principal.wallet(principal)

    membership =
      membership(state, principal, connected_wallet, pending_signature_request_id)

    joined? = membership == :joined
    moderator? = Membership.moderator_wallet?(definition, connected_wallet)
    capacity = room.capacity
    member_count = Membership.human_member_count(state.repo, room)
    active_member_count = Membership.active_human_member_count(state.repo, room, definition)
    seats_remaining = max(capacity - member_count, 0)

    pending_request_id =
      pending_signature_request_id || pending_request_id_for_wallet(state, connected_wallet)

    RoomPanel.new!(%{
      room_key: definition.key,
      xmtp_group_id: room.conversation_id,
      name: room.room_name,
      status: :ready,
      membership: membership,
      connected_wallet: connected_wallet,
      can_join: can_join?(membership, principal),
      can_send: joined?,
      can_moderate: moderator?,
      pending_signature_request_id: pending_request_id,
      member_count: member_count,
      active_member_count: active_member_count,
      capacity: capacity,
      seats_remaining: seats_remaining,
      presence_ttl_seconds: div(definition.presence_timeout_ms, 1_000),
      last_synced_at: room.updated_at,
      user_copy:
        RoomPanel.copy(copy_override || default_copy(membership, principal, seats_remaining)),
      messages: list_panel_messages(state, connected_wallet, moderator?)
    })
  end

  defp list_panel_messages(%{repo: repo, room: room}, connected_wallet, moderator?) do
    repo
    |> Log.list_messages(room)
    |> Enum.reject(&membership_change_message?/1)
    |> Enum.take(-@message_limit)
    |> Enum.map(fn message ->
      sender_wallet = Principal.normalize_wallet(message.sender_wallet)
      moderated? = message.website_visibility_state == "moderator_deleted"

      %{
        key: message.xmtp_message_id,
        author: author_label(message.sender_label, sender_wallet, message.sender_inbox_id),
        body: Log.website_body(message),
        stamp: format_stamp(message.sent_at),
        side: if(connected_wallet && sender_wallet == connected_wallet, do: :self, else: :other),
        sender_inbox_id: message.sender_inbox_id,
        sender_wallet: sender_wallet,
        sender_kind: normalize_sender_kind(message.sender_kind),
        website_state: if(moderated?, do: :moderator_deleted, else: :visible),
        can_delete?: moderator? and not moderated?,
        can_kick?: moderator? and sender_wallet != nil and sender_wallet != connected_wallet
      }
    end)
  end

  defp membership_change_message?(%MessageLog{message_snapshot: %{"kind" => :membership_change}}),
    do: true

  defp membership_change_message?(%MessageLog{
         message_snapshot: %{"kind" => "membership_change"}
       }),
       do: true

  defp membership_change_message?(%MessageLog{
         message_snapshot: %{"content_type_id" => "groupUpdated"}
       }),
       do: true

  defp membership_change_message?(%MessageLog{message_snapshot: %{"content_type_id" => type_id}}),
    do: type_id == "groupUpdated"

  defp membership_change_message?(%MessageLog{}), do: false

  defp membership(_state, nil, _wallet_address, _pending_request_id), do: :not_connected

  defp membership(state, principal, wallet_address, pending_request_id) do
    cond do
      Membership.joined?(state, wallet_address) ->
        :joined

      is_binary(pending_request_id) or pending_request_id_for_wallet(state, wallet_address) ->
        :pending_signature

      Membership.kicked?(state, wallet_address) ->
        :removed

      Membership.room_full?(state, principal) ->
        :blocked

      true ->
        :not_joined
    end
  end

  defp can_join?(:not_joined, %Principal{}), do: true
  defp can_join?(:removed, %Principal{}), do: true
  defp can_join?(_, _), do: false

  defp default_copy(:not_connected, nil, _seats_remaining), do: "Sign in to join this room."

  defp default_copy(:not_joined, principal, seats_remaining),
    do:
      "Connected as #{Principal.short(Principal.wallet(principal))}. #{seats_remaining} seats are open."

  defp default_copy(:pending_signature, _principal, _seats_remaining),
    do: "Check your wallet to finish joining."

  defp default_copy(:joined, principal, _seats_remaining),
    do: "Connected as #{Principal.short(Principal.wallet(principal))}. You are in the room."

  defp default_copy(:blocked, _principal, _seats_remaining),
    do: "This room is full right now. You can still read along."

  defp default_copy(:removed, _principal, seats_remaining),
    do:
      "You were removed from the room. Join again later if a seat opens. #{seats_remaining} seats are open."

  defp pending_request_id_for_wallet(_state, nil), do: nil

  defp pending_request_id_for_wallet(state, wallet_address) do
    Enum.find_value(state.pending_signatures, fn {request_id, pending} ->
      if pending.wallet_address == wallet_address, do: request_id, else: nil
    end)
  end

  defp author_label(label, _wallet_address, _inbox_id) when is_binary(label) and label != "",
    do: label

  defp author_label(_label, nil, inbox_id), do: Principal.short(inbox_id)
  defp author_label(_label, wallet_address, _inbox_id), do: Principal.short(wallet_address)

  defp format_stamp(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%b %-d %H:%M")

  defp normalize_sender_kind("agent"), do: :agent
  defp normalize_sender_kind(_), do: :human
end

defmodule Xmtp.RoomPanel do
  @moduledoc """
  Product-safe room state for Phoenix UIs.

  Host apps render this struct and send user actions back through `Xmtp.Rooms`.
  Product code should not infer XMTP group, membership, or send permissions from
  lower-level client state.
  """

  @type room_status :: :ready | :syncing | :bootstrapping | :disabled

  @type membership ::
          :not_connected
          | :not_joined
          | :pending_signature
          | :joined
          | :blocked
          | :removed

  @type copy :: %{required(:primary) => String.t(), optional(:detail) => String.t() | nil}

  @type t :: %__MODULE__{
          room_key: String.t() | nil,
          xmtp_group_id: String.t() | nil,
          name: String.t() | nil,
          status: room_status(),
          membership: membership(),
          can_join: boolean(),
          can_send: boolean(),
          can_moderate: boolean(),
          pending_signature_request_id: String.t() | nil,
          member_count: non_neg_integer(),
          active_member_count: non_neg_integer(),
          capacity: pos_integer() | nil,
          seats_remaining: non_neg_integer(),
          presence_ttl_seconds: non_neg_integer(),
          last_synced_at: DateTime.t() | nil,
          connected_wallet: String.t() | nil,
          messages: [map()],
          user_copy: copy()
        }

  defstruct room_key: nil,
            xmtp_group_id: nil,
            name: nil,
            status: :disabled,
            membership: :not_connected,
            can_join: false,
            can_send: false,
            can_moderate: false,
            pending_signature_request_id: nil,
            member_count: 0,
            active_member_count: 0,
            capacity: nil,
            seats_remaining: 0,
            presence_ttl_seconds: 0,
            last_synced_at: nil,
            connected_wallet: nil,
            messages: [],
            user_copy: %{primary: "This room is unavailable right now.", detail: nil}

  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs) do
    %__MODULE__{
      room_key: Map.get(attrs, :room_key),
      xmtp_group_id: Map.get(attrs, :xmtp_group_id),
      name: Map.get(attrs, :name),
      status: Map.fetch!(attrs, :status),
      membership: Map.fetch!(attrs, :membership),
      can_join: Map.get(attrs, :can_join, false),
      can_send: Map.get(attrs, :can_send, false),
      can_moderate: Map.get(attrs, :can_moderate, false),
      pending_signature_request_id: Map.get(attrs, :pending_signature_request_id),
      member_count: Map.get(attrs, :member_count, 0),
      active_member_count: Map.get(attrs, :active_member_count, 0),
      capacity: Map.get(attrs, :capacity),
      seats_remaining: Map.get(attrs, :seats_remaining, 0),
      presence_ttl_seconds: Map.get(attrs, :presence_ttl_seconds, 0),
      last_synced_at: Map.get(attrs, :last_synced_at),
      connected_wallet: Map.get(attrs, :connected_wallet),
      messages: Map.get(attrs, :messages, []),
      user_copy: normalize_copy(Map.get(attrs, :user_copy))
    }
  end

  @spec copy(String.t(), String.t() | nil) :: copy()
  def copy(primary, detail \\ nil) when is_binary(primary),
    do: %{primary: primary, detail: detail}

  defp normalize_copy(%{primary: primary} = copy) when is_binary(primary) do
    %{primary: primary, detail: Map.get(copy, :detail)}
  end

  defp normalize_copy(_copy), do: %{primary: "This room is unavailable right now.", detail: nil}
end

defmodule Xmtp.RoomPanelTest do
  use ExUnit.Case, async: true

  alias Xmtp.RoomPanel

  test "builds the canonical product room panel" do
    panel =
      RoomPanel.new!(%{
        room_key: "techtree:node:1",
        xmtp_group_id: "group-1",
        name: "Node Room",
        status: :ready,
        membership: :joined,
        can_send: true,
        user_copy: RoomPanel.copy("You are in the room.")
      })

    assert panel.room_key == "techtree:node:1"
    assert panel.xmtp_group_id == "group-1"
    assert panel.membership == :joined
    assert panel.can_send
    assert panel.user_copy.primary == "You are in the room."
  end
end

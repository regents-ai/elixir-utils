defmodule Xmtp.InstallationsTest do
  use ExUnit.Case, async: true

  import XmtpElixirSdk.TestSupport

  alias Xmtp.Installations
  alias XmtpElixirSdk.Preferences

  setup :start_runtime

  test "reports product-safe device status" do
    assert {:ok, alice} = create_client("alice")
    assert {:ok, _sibling} = create_client("alice")
    assert {:ok, inbox_state} = Preferences.inbox_state(alice)

    assert {:ok, status} = Installations.status(inbox_state, device_limit: 1)
    assert status.status == :too_many_devices
    assert status.installation_count == 2
    assert status.user_copy == "This wallet has too many chat devices connected."

    assert {:ok, cleanup} =
             Installations.recommend_cleanup(inbox_state,
               device_limit: 1,
               current_installation_id: alice.installation_id
             )

    assert length(cleanup.installation_ids) == 1
    refute alice.installation_id in cleanup.installation_ids
  end
end

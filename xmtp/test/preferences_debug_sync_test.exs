defmodule XmtpElixirSdk.PreferencesDebugSyncTest do
  use ExUnit.Case, async: true

  import XmtpElixirSdk.TestSupport

  alias XmtpElixirSdk.Debug
  alias XmtpElixirSdk.Events
  alias XmtpElixirSdk.Messages
  alias XmtpElixirSdk.Preferences
  alias XmtpElixirSdk.Sync
  alias XmtpElixirSdk.Internal.Names
  alias XmtpElixirSdk.Types

  setup :start_runtime

  test "preferences sync and consent updates emit events" do
    assert {:ok, alice} = create_client("alice")
    preferences_topic = {:preferences, alice.id}
    consent_topic = {:consent, alice.id}

    :ok = Events.subscribe(alice, preferences_topic)
    :ok = Events.subscribe(alice, consent_topic)

    assert {:ok, _summary} = Preferences.sync(alice)
    assert_receive {:xmtp, ^preferences_topic, %Events.PreferenceUpdated{}}, 500

    assert {:ok, :ok} =
             Preferences.set_consent_states(alice, [%{inbox_id: alice.inbox_id, state: :allowed}])

    assert_receive {:xmtp, ^consent_topic, %Events.ConsentUpdated{}}, 500
    assert {:ok, :allowed} = Preferences.get_consent_state(alice, :inbox_id, alice.inbox_id)
  end

  test "debug counters can be inspected and cleared" do
    assert {:ok, alice} = create_client("alice")
    assert {:ok, _bob} = create_client("bob")
    assert {:ok, group} = create_group(alice, ["bob"])
    assert {:ok, _message_id} = Messages.send_text(group, "stats")

    assert {:ok, api_stats} = Debug.api_statistics(alice)
    assert (api_stats.send_group_messages || 0) >= 1

    assert :ok = Debug.clear_all_statistics(alice)
    assert {:ok, cleared} = Debug.api_statistics(alice)
    assert is_nil(cleared.send_group_messages)
  end

  test "sync archives can be created, inspected, imported, and applied" do
    assert {:ok, alice} = create_client("alice")
    assert {:ok, _bob} = create_client("bob")
    assert {:ok, group} = create_group(alice, ["bob"])
    assert {:ok, _message_id} = Messages.send_text(group, "archive me")

    key = <<1, 2, 3>>
    assert {:ok, archive} = Sync.create_archive(alice, key)
    assert {:ok, metadata} = Sync.archive_metadata(alice, archive, key)
    assert metadata.item_count >= 1

    assert {:ok, restored} = build_client("alice")
    assert {:ok, :ok} = Sync.import_archive(restored, archive, key)
    assert {:ok, groups} = XmtpElixirSdk.Conversations.list_groups(restored)
    assert length(groups) >= 1
  end

  test "device sync can create and apply archives across installations" do
    assert {:ok, alice} = create_client("alice")
    assert {:ok, sibling} = build_client("alice")
    assert {:ok, _bob} = create_client("bob")
    assert {:ok, group} = create_group(alice, ["bob"])
    assert {:ok, _message_id} = Messages.send_text(group, "sync me")

    assert {:ok, :ok} = Sync.send_sync_request(sibling)
    assert {:ok, summary} = Sync.sync_all_device_sync_groups(alice)
    assert summary.synced >= 0

    assert {:ok, :ok} = Sync.process_sync_archive(sibling, nil)
    assert {:ok, groups} = XmtpElixirSdk.Conversations.list_groups(sibling)
    assert length(groups) >= 1
  end

  test "unsafe archive terms are rejected cleanly" do
    assert {:ok, alice} = create_client("alice")

    assert {:error, error} =
             Sync.archive_metadata(alice, :erlang.term_to_binary(make_ref()), <<1, 2, 3>>)

    assert error.kind == :invalid_argument
    assert error.message == "invalid archive data"
  end

  test "archive listing respects the day cutoff using nanosecond timestamps" do
    assert {:ok, alice} = create_client("alice")

    now = System.system_time(:nanosecond)

    recent_archive = %{
      pin: "recent",
      inbox_id: alice.inbox_id,
      creator_installation_id: alice.installation_id,
      server_url: "https://recent.example",
      created_at_ns: now - System.convert_time_unit(6 * 60 * 60, :second, :nanosecond),
      item_count: 1,
      options: %Types.ArchiveOptions{},
      conversations: []
    }

    stale_archive = %{
      pin: "stale",
      inbox_id: alice.inbox_id,
      creator_installation_id: alice.installation_id,
      server_url: "https://stale.example",
      created_at_ns: now - System.convert_time_unit(25 * 60 * 60, :second, :nanosecond),
      item_count: 1,
      options: %Types.ArchiveOptions{},
      conversations: []
    }

    :sys.replace_state(Names.sync_server(alice), fn state ->
      %{
        state
        | archives: %{recent_archive.pin => recent_archive, stale_archive.pin => stale_archive}
      }
    end)

    assert {:ok, archives} = Sync.list_available_archives(alice, 1)
    assert Enum.map(archives, & &1.pin) == ["recent"]
  end
end

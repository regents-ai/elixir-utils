defmodule Xmtp.RoomServerTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias Xmtp.RoomDefinition
  alias Xmtp.RoomServer

  defmodule FakeRepo do
    # No room record exists for any key.
    def get_by(Xmtp.Room, _clauses), do: nil
  end

  defp definition(attrs) do
    RoomDefinition.new!(
      Keyword.merge(
        [key: "test:room", name: "Test Room", presence_check_interval_ms: :timer.minutes(5)],
        attrs
      )
    )
  end

  defp start_room!(definition) do
    registry = :"room_registry_#{System.unique_integer([:positive])}"
    start_supervised!({Registry, keys: :unique, name: registry})

    start_supervised!(
      {RoomServer,
       manager: :room_server_test_manager,
       repo: FakeRepo,
       pubsub: :room_server_test_pubsub,
       registry: registry,
       runtime_name: :room_server_test_runtime,
       definition: definition}
    )
  end

  test "starts degraded when the agent private key is missing" do
    pid = start_room!(definition(agent_private_key: nil))

    assert {:ok, panel} = GenServer.call(pid, {:public_room_panel, nil, %{}})
    assert panel.status == :disabled
    refute panel.can_join
    refute panel.can_send

    assert {:error, :room_unavailable} =
             GenServer.call(pid, {:send_public_message, nil, "hello"})

    assert Process.alive?(pid)
  end

  test "add_remote_member fails cleanly when the room is not ready" do
    private_key = "0x" <> String.duplicate("11", 32)
    pid = start_room!(definition(agent_private_key: private_key))

    target = Xmtp.Principal.agent(%{wallet_address: "0x" <> String.duplicate("22", 20)})

    assert {:error, :room_unavailable} =
             GenServer.call(pid, {:add_remote_member, target, %{}})

    assert Process.alive?(pid)
  end

  test "starts degraded when the room record is not bootstrapped" do
    private_key = "0x" <> String.duplicate("11", 32)
    pid = start_room!(definition(agent_private_key: private_key))

    assert {:ok, panel} = GenServer.call(pid, {:public_room_panel, nil, %{}})
    assert panel.status == :disabled

    assert {:error, :room_unavailable} =
             GenServer.call(pid, {:request_join, nil, %{}})

    assert Process.alive?(pid)
  end
end

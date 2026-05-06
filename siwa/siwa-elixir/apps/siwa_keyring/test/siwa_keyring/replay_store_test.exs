defmodule SiwaKeyring.ReplayStoreTest do
  use ExUnit.Case, async: false

  setup do
    original = Application.get_env(:siwa_keyring, :replay_store)

    on_exit(fn ->
      case original do
        nil -> Application.delete_env(:siwa_keyring, :replay_store)
        value -> Application.put_env(:siwa_keyring, :replay_store, value)
      end
    end)

    :ok
  end

  test "delegates replay consumption to a configured shared store" do
    parent = self()

    Application.put_env(:siwa_keyring, :replay_store, fn request_id, expires_at_ms ->
      send(parent, {:replay_consumed, request_id, expires_at_ms})
      :ok
    end)

    assert :ok = SiwaKeyring.ReplayStore.consume("request-00000001", 1_777_978_831_438)
    assert_receive {:replay_consumed, "request-00000001", 1_777_978_831_438}
  end
end

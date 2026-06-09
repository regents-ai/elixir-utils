defmodule XmtpElixirSdk.NativePortTest do
  use ExUnit.Case, async: true

  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Internal.NativePort

  @moduletag :tmp_dir
  @moduletag :capture_log

  defp write_script!(tmp_dir, name, body) do
    path = Path.join(tmp_dir, name)
    File.write!(path, body)
    File.chmod!(path, 0o755)
    path
  end

  # Replies ok to every request line, echoing the request id.
  defp echo_bridge!(tmp_dir) do
    write_script!(tmp_dir, "echo_bridge.sh", """
    #!/bin/sh
    while read -r line; do
      id=$(printf '%s' "$line" | sed -n 's/.*"id":"\\([^"]*\\)".*/\\1/p')
      printf '{"id":"%s","ok":true,"result":{"status":"ok"}}\\n' "$id"
    done
    """)
  end

  # Consumes the first request and exits without replying.
  defp dying_bridge!(tmp_dir) do
    write_script!(tmp_dir, "dying_bridge.sh", """
    #!/bin/sh
    read -r line
    exit 1
    """)
  end

  # Exits immediately on first launch, then behaves like echo_bridge.
  defp flaky_bridge!(tmp_dir) do
    marker = Path.join(tmp_dir, "flaky_marker")

    write_script!(tmp_dir, "flaky_bridge.sh", """
    #!/bin/sh
    if [ ! -f "#{marker}" ]; then
      touch "#{marker}"
      exit 1
    fi
    while read -r line; do
      id=$(printf '%s' "$line" | sed -n 's/.*"id":"\\([^"]*\\)".*/\\1/p')
      printf '{"id":"%s","ok":true,"result":{"status":"ok"}}\\n' "$id"
    done
    """)
  end

  # Reads requests but never replies.
  defp silent_bridge!(tmp_dir) do
    write_script!(tmp_dir, "silent_bridge.sh", """
    #!/bin/sh
    while read -r line; do
      :
    done
    """)
  end

  defp start_port!(executable) do
    name = :"native_port_test_#{System.unique_integer([:positive])}"
    start_supervised!({NativePort, name: name, executable: executable})
    name
  end

  defp await_healthy(name, deadline_ms \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + deadline_ms
    do_await_healthy(name, deadline)
  end

  defp do_await_healthy(name, deadline) do
    case NativePort.request(name, "health") do
      {:ok, _result} = ok ->
        ok

      {:error, _reason} ->
        if System.monotonic_time(:millisecond) > deadline do
          flunk("native bridge did not recover before the deadline")
        else
          Process.sleep(25)
          do_await_healthy(name, deadline)
        end
    end
  end

  test "answers requests through a healthy bridge", %{tmp_dir: tmp_dir} do
    name = start_port!(echo_bridge!(tmp_dir))

    assert {:ok, %{"status" => "ok"}} = NativePort.request(name, "health")
    assert {:ok, %{"status" => "ok"}} = NativePort.request(name, "health")
  end

  test "pending requests get {:error, :bridge_down} when the bridge dies", %{tmp_dir: tmp_dir} do
    name = start_port!(dying_bridge!(tmp_dir))

    assert {:error, :bridge_down} = NativePort.request(name, "health")
  end

  test "requests while the bridge is down fail fast and the server survives", %{tmp_dir: tmp_dir} do
    name = start_port!(dying_bridge!(tmp_dir))
    pid = Process.whereis(name)

    assert {:error, :bridge_down} = NativePort.request(name, "health")
    # The port owner must still be alive (no supervisor cascade) and reply
    # immediately while the port is closed.
    assert Process.alive?(pid)
    assert {:error, :bridge_down} = NativePort.request(name, "health")
    assert Process.whereis(name) == pid
  end

  test "reopens the bridge with backoff after it exits", %{tmp_dir: tmp_dir} do
    name = start_port!(flaky_bridge!(tmp_dir))

    # First launch exits immediately; after the backoff the port is reopened
    # against the now-healthy script and requests succeed again.
    assert {:ok, %{"status" => "ok"}} = await_healthy(name)
  end

  test "request times out with a structured error when the bridge stalls", %{tmp_dir: tmp_dir} do
    name = start_port!(silent_bridge!(tmp_dir))

    assert {:error, %Error{kind: :internal, message: "native bridge request timed out"}} =
             NativePort.request(name, "health", %{}, 100)
  end

  test "stops with a descriptive reason when the executable is missing", %{tmp_dir: tmp_dir} do
    name = :"native_port_test_#{System.unique_integer([:positive])}"
    missing = Path.join(tmp_dir, "does_not_exist")

    Process.flag(:trap_exit, true)

    assert {:error, {:xmtp_native_missing, _message}} =
             NativePort.start_link(name: name, executable: missing)
  end
end

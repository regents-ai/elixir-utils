defmodule XmtpElixirSdk.BrowserShim.AsyncStreamTest do
  use ExUnit.Case, async: true

  alias XmtpElixirSdk.BrowserShim.AsyncStream

  test "delivers pushed values in order" do
    {:ok, pid} = AsyncStream.start_link()

    assert {:error, :timeout} == AsyncStream.next(pid, 10)

    AsyncStream.push(pid, "one")
    AsyncStream.push(pid, "two")

    assert {:ok, "one"} = AsyncStream.next(pid)
    assert {:ok, "two"} = AsyncStream.next(pid)
  end

  test "done closes pending consumers and halts the enumerable" do
    {:ok, pid} = AsyncStream.start_link()
    task = Task.async(fn -> AsyncStream.next(pid, :infinity) end)

    AsyncStream.done(pid)

    assert {:done, :closed} = Task.await(task)
    assert {:done, :closed} = AsyncStream.next(pid)
    assert [] == Enum.to_list(AsyncStream.stream(pid))
  end

  test "stream enumerates queued values before closing" do
    {:ok, pid} = AsyncStream.start_link()

    AsyncStream.push(pid, 1)
    AsyncStream.push(pid, 2)
    AsyncStream.done(pid)

    assert [] == Enum.to_list(AsyncStream.stream(pid))
  end
end

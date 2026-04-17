defmodule XmtpElixirSdk.BrowserShim.ActionTest do
  use ExUnit.Case, async: true

  alias XmtpElixirSdk.BrowserShim
  alias XmtpElixirSdk.BrowserShim.Action

  test "builds request envelopes with generated ids" do
    request = BrowserShim.request("opfs.listFiles")

    assert %Action.Request{action: "opfs.listFiles", data: %{}} = request
    assert byte_size(request.id) == 32
  end

  test "builds response, error, and stream envelopes" do
    response = BrowserShim.response("opfs.fileCount", "abc", 2)
    error = BrowserShim.error("opfs.fileCount", "abc", :boom)
    stream_event = BrowserShim.stream_event("stream.value", "stream-1", [1, 2, 3])
    stream_error = BrowserShim.stream_error("stream.value", "stream-1", :boom)

    assert %Action.Response{id: "abc", action: "opfs.fileCount", result: 2} = response
    assert %Action.Error{id: "abc", action: "opfs.fileCount", error: :boom} = error

    assert %Action.StreamEvent{
             action: "stream.value",
             streamId: "stream-1",
             result: [1, 2, 3]
           } = stream_event

    assert %Action.StreamError{
             action: "stream.value",
             streamId: "stream-1",
             error: :boom
           } = stream_error
  end
end

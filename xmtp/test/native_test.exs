defmodule XmtpElixirSdk.NativeTest do
  use ExUnit.Case, async: true

  import XmtpElixirSdk.TestSupport

  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Native

  setup :start_runtime

  test "supervised native bridge answers health and version requests", %{runtime: runtime} do
    assert {:ok, %{"status" => "ok"}} = Native.request(runtime, "health")
    assert {:ok, version} = Native.libxmtp_version(runtime)
    assert is_binary(version)
    assert version != ""
  end

  test "unknown native operation returns a structured SDK error", %{runtime: runtime} do
    assert {:error, %Error{kind: :internal, message: message}} =
             Native.request(runtime, "not_a_real_operation")

    assert message == "unknown operation: not_a_real_operation"
  end
end

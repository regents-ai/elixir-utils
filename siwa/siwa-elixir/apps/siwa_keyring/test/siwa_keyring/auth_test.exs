defmodule SiwaKeyring.AuthTest do
  use ExUnit.Case, async: true

  alias SiwaKeyring.Auth

  @secret "auth-test-secret"
  @method "POST"
  @path "/internal/keyring/sign-message"
  @body ~s({"message":"Sign in to Regent"})

  defp signed_headers(opts \\ []) do
    Auth.compute_hmac(@secret, @method, @path, @body, opts)
  end

  defp verify(method, path, headers) do
    Auth.verify_hmac(
      @secret,
      method,
      path,
      @body,
      headers["x-keyring-request-id"],
      headers["x-keyring-timestamp"],
      headers["x-keyring-signature"]
    )
  end

  test "verifies a well-formed request unchanged" do
    headers = signed_headers()
    assert :ok = verify(@method, @path, headers)
  end

  test "rejects an empty method" do
    headers = signed_headers()
    assert {:error, :invalid_method} = verify("", @path, headers)
  end

  test "rejects a non-binary method" do
    headers = signed_headers()
    assert {:error, :invalid_method} = verify(nil, @path, headers)
  end

  test "rejects an oversized method" do
    headers = signed_headers()
    assert {:error, :invalid_method} = verify(String.duplicate("A", 17), @path, headers)
  end

  test "rejects a method containing control characters" do
    headers = signed_headers()
    assert {:error, :invalid_method} = verify("PO\nST", @path, headers)
  end

  test "rejects an empty path" do
    headers = signed_headers()
    assert {:error, :invalid_path} = verify(@method, "", headers)
  end

  test "rejects a non-binary path" do
    headers = signed_headers()
    assert {:error, :invalid_path} = verify(@method, nil, headers)
  end

  test "rejects a path containing control characters" do
    headers = signed_headers()
    assert {:error, :invalid_path} = verify(@method, "/sign\x00message", headers)
  end

  test "rejects an oversized path" do
    headers = signed_headers()
    assert {:error, :invalid_path} = verify(@method, "/" <> String.duplicate("a", 4096), headers)
  end
end

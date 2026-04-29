defmodule SiwaKeyring.RouterUsageTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog
  import Plug.Conn
  import Plug.Test

  @prefix "/internal/keyring"

  defp call_router(conn) do
    SiwaKeyring.Router.call(conn, SiwaKeyring.Router.init([]))
  end

  defp signed_conn(method, path, body, secret, timestamp \\ nil) do
    headers = SiwaKeyring.Auth.compute_hmac(secret, method, path, body, timestamp)

    conn(method, path, body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-keyring-timestamp", headers["x-keyring-timestamp"])
    |> put_req_header("x-keyring-signature", headers["x-keyring-signature"])
  end

  defp with_keyring_env(fun) do
    path = Path.join(System.tmp_dir!(), "siwa-keyring-#{System.unique_integer([:positive])}.json")
    old_env = Application.get_all_env(:siwa_keyring)

    Application.put_env(:siwa_keyring, :path, path)
    Application.put_env(:siwa_keyring, :password, "router-password")
    Application.put_env(:siwa_keyring, :secret, "router-secret")

    try do
      fun.(path)
    after
      File.rm(path)
      Enum.each(old_env, fn {key, value} -> Application.put_env(:siwa_keyring, key, value) end)
    end
  end

  test "router supports the normal wallet lifecycle" do
    path = Path.join(System.tmp_dir!(), "siwa-keyring-#{System.unique_integer([:positive])}.json")
    old_env = Application.get_all_env(:siwa_keyring)

    Application.put_env(:siwa_keyring, :path, path)
    Application.put_env(:siwa_keyring, :password, "router-password")
    Application.put_env(:siwa_keyring, :secret, "router-secret")

    on_exit(fn ->
      File.rm(path)
      Enum.each(old_env, fn {key, value} -> Application.put_env(:siwa_keyring, key, value) end)
    end)

    create_conn = signed_conn("POST", @prefix <> "/create-wallet", "{}", "router-secret")
    create_response = call_router(create_conn)
    assert create_response.status == 200
    create_payload = Jason.decode!(create_response.resp_body)
    refute Map.has_key?(create_payload, "private_key")
    assert is_binary(create_payload["address"])
    assert is_binary(create_payload["public_key"])

    address_conn = signed_conn("POST", @prefix <> "/get-address", "{}", "router-secret")
    address_response = call_router(address_conn)
    assert address_response.status == 200
    %{"address" => address} = Jason.decode!(address_response.resp_body)
    assert is_binary(address)

    message_body = "{\n  \"message\": \"hello from keyring\"\n}"

    sign_conn = signed_conn("POST", @prefix <> "/sign-message", message_body, "router-secret")
    sign_response = call_router(sign_conn)
    assert sign_response.status == 200

    %{"signature" => signature} = Jason.decode!(sign_response.resp_body)
    assert is_binary(signature)
    assert String.starts_with?(signature, "0x")
    assert byte_size(signature) == 132
  end

  test "router rejects requests with a bad signature" do
    conn =
      conn("POST", @prefix <> "/has-wallet", "{}")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-keyring-timestamp", "123")
      |> put_req_header("x-keyring-signature", "bad")

    response = call_router(conn)
    assert response.status == 401
    assert Jason.decode!(response.resp_body) == %{"error" => "unauthorized"}
  end

  test "router rejects requests with a stale timestamp" do
    timestamp = System.system_time(:millisecond) - 60_000

    response =
      signed_conn(
        "POST",
        @prefix <> "/has-wallet",
        "{}",
        "router-secret",
        Integer.to_string(timestamp)
      )
      |> call_router()

    assert response.status == 401
    assert Jason.decode!(response.resp_body) == %{"error" => "unauthorized"}
  end

  test "router returns json for malformed request bodies" do
    response =
      signed_conn("POST", @prefix <> "/sign-message", ~s({"message":), "router-secret")
      |> call_router()

    assert response.status == 400
    assert Jason.decode!(response.resp_body) == %{"error" => "malformed_json"}
  end

  test "router returns json for oversized request bodies" do
    body = Jason.encode!(%{message: String.duplicate("a", SiwaKeyring.Router.max_body_bytes())})

    response =
      signed_conn("POST", @prefix <> "/sign-message", body, "router-secret")
      |> call_router()

    assert response.status == 413
    assert Jason.decode!(response.resp_body) == %{"error" => "request_body_too_large"}
  end

  test "router accepts signed requests with no body" do
    path = Path.join(System.tmp_dir!(), "siwa-keyring-#{System.unique_integer([:positive])}.json")
    old_env = Application.get_all_env(:siwa_keyring)

    Application.put_env(:siwa_keyring, :path, path)
    Application.put_env(:siwa_keyring, :password, "router-password")
    Application.put_env(:siwa_keyring, :secret, "router-secret")

    on_exit(fn ->
      File.rm(path)
      Enum.each(old_env, fn {key, value} -> Application.put_env(:siwa_keyring, key, value) end)
    end)

    headers = SiwaKeyring.Auth.compute_hmac("router-secret", "POST", @prefix <> "/has-wallet", "")

    response =
      conn("POST", @prefix <> "/has-wallet")
      |> put_req_header("x-keyring-timestamp", headers["x-keyring-timestamp"])
      |> put_req_header("x-keyring-signature", headers["x-keyring-signature"])
      |> call_router()

    assert response.status == 200
    assert Jason.decode!(response.resp_body) == %{"has_wallet" => false}
  end

  test "router accepts signed requests with an empty json body" do
    path = Path.join(System.tmp_dir!(), "siwa-keyring-#{System.unique_integer([:positive])}.json")
    old_env = Application.get_all_env(:siwa_keyring)

    Application.put_env(:siwa_keyring, :path, path)
    Application.put_env(:siwa_keyring, :password, "router-password")
    Application.put_env(:siwa_keyring, :secret, "router-secret")

    on_exit(fn ->
      File.rm(path)
      Enum.each(old_env, fn {key, value} -> Application.put_env(:siwa_keyring, key, value) end)
    end)

    headers = SiwaKeyring.Auth.compute_hmac("router-secret", "POST", @prefix <> "/has-wallet", "")

    response =
      conn("POST", @prefix <> "/has-wallet", "")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-keyring-timestamp", headers["x-keyring-timestamp"])
      |> put_req_header("x-keyring-signature", headers["x-keyring-signature"])
      |> call_router()

    assert response.status == 200
    assert Jason.decode!(response.resp_body) == %{"has_wallet" => false}
  end

  test "router rejects empty signing inputs" do
    path = Path.join(System.tmp_dir!(), "siwa-keyring-#{System.unique_integer([:positive])}.json")
    old_env = Application.get_all_env(:siwa_keyring)

    Application.put_env(:siwa_keyring, :path, path)
    Application.put_env(:siwa_keyring, :password, "router-password")
    Application.put_env(:siwa_keyring, :secret, "router-secret")

    on_exit(fn ->
      File.rm(path)
      Enum.each(old_env, fn {key, value} -> Application.put_env(:siwa_keyring, key, value) end)
    end)

    message_response =
      signed_conn("POST", @prefix <> "/sign-message", "{}", "router-secret")
      |> call_router()

    assert message_response.status == 400
    assert Jason.decode!(message_response.resp_body) == %{"error" => "message_required"}

    transaction_response =
      signed_conn(
        "POST",
        @prefix <> "/sign-transaction",
        ~s({"transaction":{}}),
        "router-secret"
      )
      |> call_router()

    assert transaction_response.status == 400
    assert Jason.decode!(transaction_response.resp_body) == %{"error" => "transaction_required"}
  end

  test "router returns stable error codes when a wallet is missing" do
    path = Path.join(System.tmp_dir!(), "siwa-keyring-#{System.unique_integer([:positive])}.json")
    old_env = Application.get_all_env(:siwa_keyring)

    Application.put_env(:siwa_keyring, :path, path)
    Application.put_env(:siwa_keyring, :password, "router-password")
    Application.put_env(:siwa_keyring, :secret, "router-secret")

    on_exit(fn ->
      File.rm(path)
      Enum.each(old_env, fn {key, value} -> Application.put_env(:siwa_keyring, key, value) end)
    end)

    response =
      signed_conn("POST", @prefix <> "/get-address", "{}", "router-secret")
      |> call_router()

    assert response.status == 404
    assert Jason.decode!(response.resp_body) == %{"error" => "wallet_not_found"}
  end

  test "router redacts signer failure details from logs" do
    with_keyring_env(fn path ->
      File.write!(path, "secret-signing-payload")

      log =
        capture_log(fn ->
          response =
            signed_conn(
              "POST",
              @prefix <> "/sign-message",
              Jason.encode!(%{message: "secret-message"}),
              "router-secret"
            )
            |> call_router()

          assert response.status == 422
          assert Jason.decode!(response.resp_body) == %{"error" => "message_sign_failed"}
        end)

      assert log =~ "keyring sign_message failed: redacted"
      refute log =~ "secret-message"
      refute log =~ "secret-signing-payload"
      refute log =~ "keystore_decrypt_failed"
    end)
  end

  test "router supports concurrent create read and sign requests after the wallet exists" do
    with_keyring_env(fn _path ->
      create_response =
        signed_conn("POST", @prefix <> "/create-wallet", "{}", "router-secret")
        |> call_router()

      assert create_response.status == 200
      create_payload = Jason.decode!(create_response.resp_body)
      %{"address" => address} = create_payload
      refute Map.has_key?(create_payload, "private_key")

      results =
        1..20
        |> Enum.map(fn index ->
          Task.async(fn ->
            if rem(index, 2) == 0 do
              signed_conn("POST", @prefix <> "/get-address", "{}", "router-secret")
              |> call_router()
            else
              body = Jason.encode!(%{message: "hello #{index}"})

              signed_conn("POST", @prefix <> "/sign-message", body, "router-secret")
              |> call_router()
            end
          end)
        end)
        |> Task.await_many(10_000)

      assert Enum.all?(results, &(&1.status == 200))

      for response <- results do
        payload = Jason.decode!(response.resp_body)

        case payload do
          %{"address" => ^address} ->
            :ok

          %{"signature" => signature} when is_binary(signature) ->
            assert String.starts_with?(signature, "0x")
            assert byte_size(signature) == 132
            :ok
        end
      end
    end)
  end

  test "body reader preserves the full raw body across multiple reads" do
    raw_body = String.duplicate("a", 20)
    conn = conn("POST", @prefix <> "/sign-message", raw_body)

    assert {:more, "aaaaa", conn} = SiwaKeyring.Router.read_body(conn, length: 5)
    assert conn.private[:raw_body] == "aaaaa"

    assert {:more, "aaaaa", conn} = SiwaKeyring.Router.read_body(conn, length: 5)
    assert conn.private[:raw_body] == "aaaaaaaaaa"

    assert {:more, "aaaaa", conn} = SiwaKeyring.Router.read_body(conn, length: 5)
    assert conn.private[:raw_body] == "aaaaaaaaaaaaaaa"

    assert {:ok, "aaaaa", conn} = SiwaKeyring.Router.read_body(conn, length: 5)
    assert conn.private[:raw_body] == raw_body
  end
end

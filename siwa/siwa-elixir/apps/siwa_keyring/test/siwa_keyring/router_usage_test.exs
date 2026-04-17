defmodule SiwaKeyring.RouterUsageTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Plug.Test

  defp call_router(conn) do
    SiwaKeyring.Router.call(conn, SiwaKeyring.Router.init([]))
  end

  defp signed_conn(method, path, body, secret) do
    headers = SiwaKeyring.Auth.compute_hmac(secret, method, path, body)

    conn(method, path, body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-keyring-timestamp", headers["x-keyring-timestamp"])
    |> put_req_header("x-keyring-signature", headers["x-keyring-signature"])
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

    create_conn = signed_conn("POST", "/create-wallet", "{}", "router-secret")
    create_response = call_router(create_conn)
    assert create_response.status == 200

    address_conn = signed_conn("POST", "/get-address", "{}", "router-secret")
    address_response = call_router(address_conn)
    assert address_response.status == 200
    %{"address" => address} = Jason.decode!(address_response.resp_body)
    assert is_binary(address)

    message_body = Jason.encode!(%{message: "hello from keyring"})

    sign_conn = signed_conn("POST", "/sign-message", message_body, "router-secret")
    sign_response = call_router(sign_conn)
    assert sign_response.status == 200

    %{"signature" => signature} = Jason.decode!(sign_response.resp_body)
    assert signature["address"] == address
    assert signature["purpose"] == "personal_sign"
  end

  test "router rejects requests with a bad signature" do
    conn =
      conn("POST", "/has-wallet", "{}")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-keyring-timestamp", "123")
      |> put_req_header("x-keyring-signature", "bad")

    response = call_router(conn)
    assert response.status == 401
  end
end

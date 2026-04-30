defmodule SiwaKeyring.ClientTest do
  use ExUnit.Case, async: false

  import Plug.Conn

  alias SiwaKeyring.{Auth, Client}

  @secret "client-secret"

  test "client sends signed JSON requests through Req and Finch" do
    finch = :"siwa_keyring_client_test_#{System.unique_integer([:positive])}"
    start_supervised!({Finch, name: finch})

    server =
      start_supervised!(
        {Bandit,
         plug: fn conn, _opts ->
           {:ok, body, conn} = Plug.Conn.read_body(conn)

           assert conn.method == "POST"
           assert conn.request_path == "/internal/keyring/create-wallet"
           assert get_req_header(conn, "content-type") == ["application/json"]

           assert :ok =
                    Auth.verify_hmac(
                      @secret,
                      conn.method,
                      conn.request_path,
                      body,
                      conn |> get_req_header("x-keyring-request-id") |> List.first(),
                      conn |> get_req_header("x-keyring-timestamp") |> List.first(),
                      conn |> get_req_header("x-keyring-signature") |> List.first()
                    )

           conn
           |> put_resp_content_type("application/json")
           |> send_resp(
             200,
             Jason.encode!(%{
               address: "0x123",
               public_key: "0xabc",
               signer_type: "eoa"
             })
           )
         end,
         scheme: :http,
         port: 0}
      )

    {:ok, {_address, port}} = ThousandIsland.listener_info(server)

    client =
      Client.new(
        base_url: "http://127.0.0.1:#{port}",
        secret: @secret,
        finch: finch
      )

    assert {:ok,
            %{
              "address" => "0x123",
              "public_key" => "0xabc",
              "signer_type" => "eoa"
            }} = Client.create_wallet(client)
  end
end

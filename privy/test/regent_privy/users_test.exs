defmodule RegentPrivy.UsersTest do
  use ExUnit.Case, async: true

  alias RegentPrivy.Users

  @wallet "0xAbCdEf0123456789abcdef0123456789ABCDEF01"
  @opts [
    app_id: "test-privy-app",
    app_secret: "test-secret",
    req_options: [plug: {Req.Test, Users}]
  ]

  defp answer(status, body) do
    Req.Test.stub(Users, fn conn ->
      send(self(), {:privy, conn.method, conn.request_path, request(conn)})
      conn |> Plug.Conn.put_status(status) |> Req.Test.json(body)
    end)
  end

  defp linked(address),
    do: %{"type" => "wallet", "address" => address, "chain_type" => "ethereum"}

  defp request(conn) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)

    %{
      body: JSON.decode!(body),
      app_id: Plug.Conn.get_req_header(conn, "privy-app-id"),
      authorization: Plug.Conn.get_req_header(conn, "authorization")
    }
  end

  test "by_wallet asks Privy for the wallet's user with the app's own key" do
    answer(200, %{"id" => "did:privy:agent-1", "linked_accounts" => [linked(@wallet)]})

    assert {:ok, %{privy_user_id: "did:privy:agent-1", only_wallet: true}} =
             Users.by_wallet(@wallet, @opts)

    assert_received {:privy, "POST", "/v1/users/wallet/address", request}
    assert request.body == %{"address" => String.downcase(@wallet)}
    assert request.app_id == ["test-privy-app"]
    assert request.authorization == ["Basic " <> Base.encode64("test-privy-app:test-secret")]
  end

  test "a user that links anything besides the wallet is not the wallet's alone" do
    other = "0x" <> String.duplicate("1", 40)

    for accounts <- [
          [linked(@wallet), %{"type" => "email", "address" => "person@example.com"}],
          [linked(other)],
          []
        ] do
      answer(200, %{"id" => "did:privy:person", "linked_accounts" => accounts})

      assert {:ok, %{privy_user_id: "did:privy:person", only_wallet: false}} =
               Users.by_wallet(@wallet, @opts)
    end
  end

  test "by_wallet says when no user has the wallet" do
    answer(404, %{"error" => "User not found"})
    assert {:error, :not_found} = Users.by_wallet(@wallet, @opts)
  end

  test "create_with_wallet links only the wallet" do
    answer(200, %{"id" => "did:privy:agent-2", "linked_accounts" => [linked(@wallet)]})

    assert {:ok, %{privy_user_id: "did:privy:agent-2", only_wallet: true}} =
             Users.create_with_wallet(@wallet, @opts)

    assert_received {:privy, "POST", "/v1/users", request}

    assert request.body == %{
             "linked_accounts" => [
               %{
                 "type" => "wallet",
                 "address" => String.downcase(@wallet),
                 "chain_type" => "ethereum"
               }
             ]
           }
  end

  test "a refusal and a failure are told apart, and neither carries Privy's words" do
    answer(400, %{"error" => "Wallet already linked"})
    assert {:error, :privy_refused} = Users.create_with_wallet(@wallet, @opts)

    answer(500, %{"error" => "boom"})
    assert {:error, :privy_unavailable} = Users.create_with_wallet(@wallet, @opts)

    Req.Test.stub(Users, &Req.Test.transport_error(&1, :timeout))
    assert {:error, :privy_unavailable} = Users.by_wallet(@wallet, @opts)
  end

  test "an answer without a Privy user id is a failure" do
    answer(200, %{"id" => "someone"})
    assert {:error, :privy_unavailable} = Users.by_wallet(@wallet, @opts)
  end

  test "nothing is sent without the app's settings or for a malformed wallet" do
    Req.Test.stub(Users, fn _conn -> flunk("Privy was called") end)

    assert {:error, :missing_privy_config} =
             Users.by_wallet(@wallet, Keyword.delete(@opts, :app_secret))

    assert {:error, :missing_privy_config} =
             Users.create_with_wallet(@wallet, Keyword.put(@opts, :app_id, ""))

    assert {:error, :invalid_wallet_address} = Users.by_wallet("0x123", @opts)
    assert {:error, :invalid_wallet_address} = Users.create_with_wallet(nil, @opts)
  end
end

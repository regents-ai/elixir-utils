defmodule RegentChatGPT.DeviceTest do
  use ExUnit.Case, async: true

  alias RegentChatGPT.{Config, Device, DeviceCode, Error}

  test "requests a device code and normalizes the response" do
    parent = self()

    config =
      Config.resolve(
        http_client: fn request ->
          send(parent, {:request, request})

          {:ok,
           %{
             status: 200,
             body: %{"device_auth_id" => "dev_1", "usercode" => "ABCD-EFGH", "interval" => "7"}
           }}
        end
      )

    assert {:ok, %DeviceCode{} = device} =
             Device.request_device_code(config, now: fn -> 1_000 end)

    assert device.device_auth_id == "dev_1"
    assert device.user_code == "ABCD-EFGH"
    assert device.interval == 7
    assert device.expires_at == 901_000
    assert device.verification_url == "https://auth.openai.com/codex/device"

    assert_receive {:request, request}
    assert request[:method] == :post
    assert request[:url] == "https://auth.openai.com/api/accounts/deviceauth/usercode"
    assert Jason.decode!(request[:body]) == %{"client_id" => "app_EMoamEEZ73f0CkXaXp7hrann"}
  end

  test "treats documented pending poll statuses as pending" do
    for status <- [403, 404, 429] do
      config = Config.resolve(http_client: fn _request -> {:ok, %{status: status, body: ""}} end)

      device = %DeviceCode{
        device_auth_id: "dev",
        user_code: "CODE",
        verification_url: "url",
        interval: 5,
        expires_at: 10
      }

      assert {:ok, %{status: :pending}} = Device.poll_device_code(config, device)
    end
  end

  test "returns authorization code and PKCE values when polling completes" do
    config =
      Config.resolve(
        http_client: fn _request ->
          {:ok,
           %{
             status: 200,
             body: %{
               "authorization_code" => "auth_code",
               "code_challenge" => "challenge",
               "code_verifier" => "verifier"
             }
           }}
        end
      )

    device = %DeviceCode{
      device_auth_id: "dev",
      user_code: "CODE",
      verification_url: "url",
      interval: 5,
      expires_at: 10
    }

    assert {:ok,
            %{
              status: :authorized,
              authorization_code: "auth_code",
              code_challenge: "challenge",
              code_verifier: "verifier"
            }} = Device.poll_device_code(config, device)
  end

  test "reports disabled device flow" do
    config =
      Config.resolve(http_client: fn _request -> {:ok, %{status: 404, body: "not found"}} end)

    assert {:error, %Error{code: :device_code_disabled, status: 404}} =
             Device.request_device_code(config)
  end
end

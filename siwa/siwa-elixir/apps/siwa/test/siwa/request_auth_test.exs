defmodule Siwa.RequestAuthTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Plug.Test

  test "signs and verifies an authenticated request" do
    {:ok, signer} = Siwa.LocalSigner.new()

    {:ok, receipt} =
      Siwa.Receipt.create(
        %{
          "address" => signer.address,
          "agentId" => 1,
          "agentRegistry" => "eip155:84532:0xregistry",
          "chainId" => 84532
        },
        secret: "secret"
      )

    request = %{
      method: "POST",
      path: "/protected",
      host: "api.example.com",
      query: "",
      body: "{}",
      headers: %{}
    }

    assert {:ok, signed_request} =
             Siwa.RequestAuth.sign_authenticated_request(request, receipt.token, signer)

    assert {:ok, verified} =
             Siwa.RequestAuth.verify_authenticated_request(signed_request, secret: "secret")

    assert verified.address == signer.address
  end

  test "rejects a request when the signer does not match the receipt" do
    {:ok, receipt_signer} = Siwa.LocalSigner.new()
    {:ok, request_signer} = Siwa.LocalSigner.new()

    {:ok, receipt} =
      Siwa.Receipt.create(
        %{
          "address" => receipt_signer.address,
          "agentId" => 1,
          "agentRegistry" => "eip155:84532:0xregistry",
          "chainId" => 84532
        },
        secret: "secret"
      )

    request = %{
      method: "POST",
      path: "/protected",
      host: "api.example.com",
      query: "",
      body: "{}",
      headers: %{}
    }

    assert {:ok, signed_request} =
             Siwa.RequestAuth.sign_authenticated_request(request, receipt.token, request_signer)

    assert {:error, :receipt_signer_mismatch} =
             Siwa.RequestAuth.verify_authenticated_request(signed_request, secret: "secret")
  end

  test "failed receipt matching does not consume the replay window for the valid request" do
    {:ok, signer} = Siwa.LocalSigner.new()
    {:ok, other_signer} = Siwa.LocalSigner.new()

    {:ok, good_receipt} =
      Siwa.Receipt.create(
        %{
          "address" => signer.address,
          "agentId" => 1,
          "agentRegistry" => "eip155:84532:0xregistry",
          "chainId" => 84532
        },
        secret: "secret"
      )

    {:ok, bad_receipt} =
      Siwa.Receipt.create(
        %{
          "address" => other_signer.address,
          "agentId" => 1,
          "agentRegistry" => "eip155:84532:0xregistry",
          "chainId" => 84532
        },
        secret: "secret"
      )

    request = %{
      method: "POST",
      path: "/protected",
      host: "api.example.com",
      query: "",
      body: "{}",
      headers: %{}
    }

    assert {:ok, signed_request} =
             Siwa.RequestAuth.sign_authenticated_request(request, good_receipt.token, signer)

    tampered_request = put_in(signed_request, [:headers, "x-siwa-receipt"], bad_receipt.token)

    assert {:error, :receipt_signer_mismatch} =
             Siwa.RequestAuth.verify_authenticated_request(tampered_request, secret: "secret")

    assert {:ok, verified} =
             Siwa.RequestAuth.verify_authenticated_request(signed_request, secret: "secret")

    assert verified.address == signer.address
  end

  test "plug accepts a request body preserved in conn.private" do
    {:ok, signer} = Siwa.LocalSigner.new()

    {:ok, receipt} =
      Siwa.Receipt.create(
        %{
          "address" => signer.address,
          "agentId" => 1,
          "agentRegistry" => "eip155:84532:0xregistry",
          "chainId" => 84532
        },
        secret: "secret"
      )

    body = ~s({"hello":"world"})

    request = %{
      method: "POST",
      path: "/protected",
      host: "www.example.com",
      query: "",
      body: body,
      headers: %{}
    }

    assert {:ok, signed_request} =
             Siwa.RequestAuth.sign_authenticated_request(request, receipt.token, signer)

    conn =
      Enum.reduce(
        signed_request.headers,
        conn("POST", "/protected", body)
        |> Map.put(:host, "www.example.com")
        |> put_private(:raw_body, body),
        fn {key, value}, acc -> put_req_header(acc, key, value) end
      )

    result = Siwa.Plug.call(conn, secret: "secret")

    assert result.halted == false
    assert result.assigns.siwa_agent.address == signer.address
  end
end

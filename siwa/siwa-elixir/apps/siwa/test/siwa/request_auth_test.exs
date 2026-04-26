defmodule Siwa.RequestAuthTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Plug.Test

  @request_auth_opts [secret: "secret", audience: "techtree"]

  test "signs and verifies an authenticated request" do
    {:ok, signer} = Siwa.LocalSigner.new()
    {:ok, receipt} = receipt_for(signer)

    assert {:ok, signed_request} =
             Siwa.RequestAuth.sign_authenticated_request(
               request(),
               receipt.token,
               signer,
               @request_auth_opts
             )

    assert signed_request.headers["x-siwa-receipt"] == receipt.token
    assert signed_request.headers["signature-input"] =~ ~s("content-digest")
    assert signed_request.headers["signature"] =~ ~r/^sig1=:[A-Za-z0-9+\/=]+:$/

    assert {:ok, verified} =
             Siwa.RequestAuth.verify_authenticated_request(signed_request, @request_auth_opts)

    assert verified.address == signer.address
    assert verified.claims["sub"] == signer.address
    assert verified.claims["registry_address"] == registry_address()
    assert verified.claims["token_id"] == "1"
  end

  test "rejects signed requests without Agent account binding headers" do
    {:ok, signer} = Siwa.LocalSigner.new()
    {:ok, receipt} = receipt_for(signer)

    assert {:ok, signed_request} =
             Siwa.RequestAuth.sign_authenticated_request(
               request(),
               receipt.token,
               signer,
               @request_auth_opts
             )

    missing_header_request =
      put_in(signed_request, [:headers], Map.delete(signed_request.headers, "x-agent-token-id"))

    assert {:error, :missing_signed_headers} =
             Siwa.RequestAuth.verify_authenticated_request(
               missing_header_request,
               @request_auth_opts
             )
  end

  test "rejects signed requests without Agent account covered components" do
    {:ok, signer} = Siwa.LocalSigner.new()
    {:ok, receipt} = receipt_for(signer)

    assert {:ok, signed_request} =
             Siwa.RequestAuth.sign_authenticated_request(
               request(),
               receipt.token,
               signer,
               @request_auth_opts
             )

    signature_input =
      String.replace(
        signed_request.headers["signature-input"],
        ~s( "x-agent-token-id"),
        ""
      )

    missing_component_request =
      put_in(signed_request, [:headers, "signature-input"], signature_input)

    assert {:error, :missing_covered_components} =
             Siwa.RequestAuth.verify_authenticated_request(
               missing_component_request,
               @request_auth_opts
             )
  end

  test "rejects a request when the signer does not match the receipt" do
    {:ok, receipt_signer} = Siwa.LocalSigner.new()
    {:ok, request_signer} = Siwa.LocalSigner.new()
    {:ok, receipt} = receipt_for(receipt_signer)

    assert {:ok, signed_request} =
             Siwa.RequestAuth.sign_authenticated_request(
               request(),
               receipt.token,
               request_signer,
               @request_auth_opts
             )

    assert {:error, :invalid_signature} =
             Siwa.RequestAuth.verify_authenticated_request(signed_request, @request_auth_opts)
  end

  test "failed receipt matching does not consume the replay window for the valid request" do
    {:ok, signer} = Siwa.LocalSigner.new()
    {:ok, other_signer} = Siwa.LocalSigner.new()
    {:ok, good_receipt} = receipt_for(signer)
    {:ok, bad_receipt} = receipt_for(other_signer)

    assert {:ok, signed_request} =
             Siwa.RequestAuth.sign_authenticated_request(
               request(),
               good_receipt.token,
               signer,
               @request_auth_opts
             )

    tampered_request = put_in(signed_request, [:headers, "x-siwa-receipt"], bad_receipt.token)

    assert {:error, :receipt_binding_mismatch} =
             Siwa.RequestAuth.verify_authenticated_request(tampered_request, @request_auth_opts)

    assert {:ok, verified} =
             Siwa.RequestAuth.verify_authenticated_request(signed_request, @request_auth_opts)

    assert verified.address == signer.address
  end

  test "plug accepts a request body preserved in conn.private" do
    {:ok, signer} = Siwa.LocalSigner.new()
    {:ok, receipt} = receipt_for(signer)
    body = ~s({"hello":"world"})

    request = %{
      method: "POST",
      path: "/protected?mode=test",
      host: "www.example.com",
      body: body,
      headers: %{}
    }

    assert {:ok, signed_request} =
             Siwa.RequestAuth.sign_authenticated_request(
               request,
               receipt.token,
               signer,
               @request_auth_opts
             )

    conn =
      Enum.reduce(
        signed_request.headers,
        conn("POST", "/protected?mode=test", body)
        |> Map.put(:host, "www.example.com")
        |> put_private(:raw_body, body),
        fn {key, value}, acc -> put_req_header(acc, key, value) end
      )

    result = Siwa.Plug.call(conn, @request_auth_opts)

    assert result.halted == false
    assert result.assigns.siwa_agent.address == signer.address
  end

  test "rejects a signed request that is older than the freshness window" do
    {:ok, signer} = Siwa.LocalSigner.new()
    {:ok, receipt} = receipt_for(signer)
    created_at = ~U[2026-04-20 00:00:00Z]

    assert {:ok, signed_request} =
             Siwa.RequestAuth.sign_authenticated_request(
               request(),
               receipt.token,
               signer,
               Keyword.merge(@request_auth_opts,
                 created_at: created_at,
                 expires_in_seconds: 600
               )
             )

    assert {:error, :request_too_old} =
             Siwa.RequestAuth.verify_authenticated_request(
               signed_request,
               Keyword.merge(@request_auth_opts, now: ~U[2026-04-20 00:06:00Z])
             )
  end

  defp receipt_for(signer) do
    Siwa.Receipt.create(
      %{
        "typ" => "siwa_receipt",
        "jti" => "receipt-#{System.unique_integer([:positive])}",
        "sub" => signer.address,
        "aud" => "techtree",
        "chain_id" => 84532,
        "nonce" => "nonce-#{System.unique_integer([:positive])}",
        "key_id" => signer.address,
        "registry_address" => registry_address(),
        "token_id" => "1"
      },
      secret: "secret"
    )
  end

  defp request do
    %{
      method: "POST",
      path: "/protected",
      host: "api.example.com",
      body: "{}",
      headers: %{}
    }
  end

  defp registry_address, do: "0x8004a818bfb912233c491871b3d84c89a494bd9e"
end

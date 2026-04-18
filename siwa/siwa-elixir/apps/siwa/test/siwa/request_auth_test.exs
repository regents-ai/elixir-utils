defmodule Siwa.RequestAuthTest do
  use ExUnit.Case, async: true

  test "signs and verifies an authenticated request" do
    {:ok, signer} = Siwa.LocalSigner.new()
    {:ok, receipt} =
      Siwa.Receipt.create(%{
        "address" => signer.address,
        "agentId" => 1,
        "agentRegistry" => "eip155:84532:0xregistry",
        "chainId" => 84532
      }, secret: "secret")

    request = %{method: "POST", path: "/protected", host: "api.example.com", query: "", body: "{}", headers: %{}}

    assert {:ok, signed_request} = Siwa.RequestAuth.sign_authenticated_request(request, receipt.token, signer)
    assert {:ok, verified} = Siwa.RequestAuth.verify_authenticated_request(signed_request, secret: "secret")
    assert verified.address == signer.address
  end

  test "rejects a request when the signer does not match the receipt" do
    {:ok, receipt_signer} = Siwa.LocalSigner.new()
    {:ok, request_signer} = Siwa.LocalSigner.new()

    {:ok, receipt} =
      Siwa.Receipt.create(%{
        "address" => receipt_signer.address,
        "agentId" => 1,
        "agentRegistry" => "eip155:84532:0xregistry",
        "chainId" => 84532
      }, secret: "secret")

    request = %{method: "POST", path: "/protected", host: "api.example.com", query: "", body: "{}", headers: %{}}

    assert {:ok, signed_request} =
             Siwa.RequestAuth.sign_authenticated_request(request, receipt.token, request_signer)

    assert {:error, :receipt_signer_mismatch} =
             Siwa.RequestAuth.verify_authenticated_request(signed_request, secret: "secret")
  end
end

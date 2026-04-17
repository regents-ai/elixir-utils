defmodule SiwaKeyring.Client do
  alias SiwaKeyring.Auth

  defstruct [:base_url, :secret]

  def new(opts) do
    %__MODULE__{
      base_url: Keyword.fetch!(opts, :base_url),
      secret: Keyword.fetch!(opts, :secret)
    }
  end

  def create_wallet(client), do: request(client, :post, "/create-wallet", %{})
  def has_wallet?(client), do: request(client, :post, "/has-wallet", %{})
  def get_address(client), do: request(client, :post, "/get-address", %{})
  def sign_message(client, message), do: request(client, :post, "/sign-message", %{message: message})
  def sign_raw_message(client, payload), do: request(client, :post, "/sign-raw-message", %{payload: payload})
  def sign_transaction(client, tx), do: request(client, :post, "/sign-transaction", %{transaction: tx})
  def sign_authorization(client, authorization), do: request(client, :post, "/sign-authorization", %{authorization: authorization})

  def proxy_signer(client) do
    {:ok, %{"address" => address}} = get_address(client)

    Siwa.RemoteSigner.new(
      address: address,
      sign_message: fn message -> with {:ok, %{"signature" => sig}} <- sign_message(client, message), do: {:ok, sig} end,
      sign_raw_message: fn payload -> with {:ok, %{"signature" => sig}} <- sign_raw_message(client, payload), do: {:ok, sig} end,
      sign_transaction: fn tx -> sign_transaction(client, tx) end,
      sign_authorization: fn authorization -> sign_authorization(client, authorization) end
    )
  end

  defp request(client, method, path, payload) do
    body = Jason.encode!(payload)
    headers =
      Auth.compute_hmac(client.secret, String.upcase(to_string(method)), path, body)
      |> Enum.map(fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)
      |> Kernel.++([{~c"content-type", ~c"application/json"}])

    url = String.to_charlist(client.base_url <> path)

    case :httpc.request(method, {url, headers, ~c"application/json", body}, [], body_format: :binary) do
      {:ok, {{_, status, _}, _resp_headers, response_body}} when status in 200..299 -> Jason.decode(response_body)
      {:ok, {{_, status, _}, _resp_headers, response_body}} -> {:error, {status, response_body}}
      error -> {:error, error}
    end
  end
end

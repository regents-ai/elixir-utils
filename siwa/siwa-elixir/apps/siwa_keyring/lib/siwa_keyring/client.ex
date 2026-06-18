defmodule SiwaKeyring.Client do
  alias SiwaKeyring.Auth

  defstruct [:base_url, :secret, :finch, timeout_ms: 5_000]

  @prefix "/api/shared/keyring"

  def new(opts) do
    %__MODULE__{
      base_url: Keyword.fetch!(opts, :base_url),
      secret: Keyword.fetch!(opts, :secret),
      finch: Keyword.get(opts, :finch),
      timeout_ms: Keyword.get(opts, :timeout_ms, 5_000)
    }
  end

  def create_wallet(client), do: request(client, :post, @prefix <> "/create-wallet", %{})
  def has_wallet?(client), do: request(client, :post, @prefix <> "/has-wallet", %{})
  def get_address(client), do: request(client, :post, @prefix <> "/get-address", %{})

  def sign_message(client, message),
    do: request(client, :post, @prefix <> "/sign-message", %{message: message})

  def sign_raw_message(client, payload),
    do: request(client, :post, @prefix <> "/sign-raw-message", %{payload: payload})

  def sign_transaction(client, tx),
    do: request(client, :post, @prefix <> "/sign-transaction", %{transaction: tx})

  def sign_authorization(client, authorization),
    do: request(client, :post, @prefix <> "/sign-authorization", %{authorization: authorization})

  def proxy_signer(client) do
    {:ok, %{"address" => address}} = get_address(client)

    Siwa.RemoteSigner.new(
      address: address,
      sign_message: fn message ->
        with {:ok, %{"signature" => sig}} <- sign_message(client, message), do: {:ok, sig}
      end,
      sign_raw_message: fn payload ->
        with {:ok, %{"signature" => sig}} <- sign_raw_message(client, payload), do: {:ok, sig}
      end,
      sign_transaction: fn tx -> sign_transaction(client, tx) end,
      sign_authorization: fn authorization -> sign_authorization(client, authorization) end
    )
  end

  defp request(client, method, path, payload) do
    body = Jason.encode!(payload)
    request_id = Auth.request_id()

    headers =
      Auth.compute_hmac(client.secret, String.upcase(to_string(method)), path, body,
        request_id: request_id
      )
      |> Map.put("content-type", "application/json")

    request_opts =
      [
        method: method,
        url: client.base_url <> path,
        headers: headers,
        body: body,
        receive_timeout: client.timeout_ms,
        retry: false
      ]
      |> maybe_put_finch(client.finch)

    case request_opts |> Req.new() |> Req.request() do
      {:ok, %{status: status, body: response_body}} when status in 200..299 ->
        decode_body(response_body)

      {:ok, %{status: status, body: response_body}} ->
        {:error, {status, response_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_put_finch(opts, nil), do: opts
  defp maybe_put_finch(opts, finch), do: Keyword.put(opts, :finch, finch)

  defp decode_body(body) when is_map(body), do: {:ok, body}
  defp decode_body(body) when is_binary(body), do: Jason.decode(body)
  defp decode_body(_body), do: {:error, :invalid_response_body}
end

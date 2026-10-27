defmodule RegentCredits.Stripe do
  @moduledoc """
  The Stripe calls behind card purchases (`RegentCredits.CardPurchase`): opening
  a Checkout Session for the Payment Element, reading one back, and checking that
  a webhook notice came from Stripe.

  A site turns card purchases on by setting the keys of its Stripe account:

      config :regent_credits, :stripe,
        secret_key: "sk_live_...",
        webhook_secret: "whsec_..."

  Every Regent site uses the same Stripe account, so every site's webhook hears
  every site's card payments, and any of them can credit one: the card purchases
  are in the shared ledger. `req_options` are added to every request, which is how
  tests answer for Stripe (`plug: {Req.Test, RegentCredits.Stripe}`).
  """

  @version "2026-09-30.endive"
  @tolerance_seconds 300

  @doc "Whether this site has Stripe keys, so it offers card purchases."
  @spec configured?() :: boolean()
  def configured?, do: Application.get_env(:regent_credits, :stripe) != nil

  @doc "Whether the keys are Stripe's live keys rather than its test keys."
  @spec live?() :: boolean()
  def live?, do: String.starts_with?(setting(:secret_key), ["sk_live_", "rk_live_"])

  @doc """
  Opens a Checkout Session for the Payment Element. `id` is the card purchase it
  pays for: Stripe gives it back as `client_reference_id`, and it keys the request,
  so sending it again opens nothing new.
  """
  @spec open_session(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def open_session(id, params) do
    request(
      method: :post,
      url: "/v1/checkout/sessions",
      form: form(params),
      headers: [{"idempotency-key", "card-purchase-" <> id}]
    )
  end

  @doc "Reads a Checkout Session as Stripe holds it now."
  @spec session(String.t()) :: {:ok, map()} | {:error, term()}
  def session(id), do: request(method: :get, url: "/v1/checkout/sessions/" <> URI.encode(id))

  @doc """
  The event a webhook notice carries, once its `Stripe-Signature` header proves
  Stripe signed this exact body within the last five minutes.
  """
  @spec event(String.t(), String.t()) :: {:ok, map()} | :error
  def event(payload, header) when is_binary(payload) and is_binary(header) do
    with {:ok, timestamp, signatures} <- parse_signature(header),
         true <- abs(System.system_time(:second) - timestamp) <= @tolerance_seconds,
         expected = sign(timestamp, payload),
         true <- Enum.any?(signatures, &:crypto.hash_equals(&1, expected)),
         {:ok, %{"type" => _type, "data" => %{"object" => _object}} = event} <-
           JSON.decode(payload) do
      {:ok, event}
    else
      _unsigned -> :error
    end
  end

  @doc false
  # The signature Stripe sends for a body at a time; tests sign their notices with it.
  def sign(timestamp, payload) do
    :hmac
    |> :crypto.mac(:sha256, setting(:webhook_secret), "#{timestamp}.#{payload}")
    |> Base.encode16(case: :lower)
  end

  defp parse_signature(header) do
    parts =
      header
      |> String.split(",", trim: true)
      |> Enum.map(&String.split(&1, "=", parts: 2))

    with [timestamp] <- for(["t", value] <- parts, do: value),
         {timestamp, ""} <- Integer.parse(timestamp),
         [_ | _] = signatures <- for(["v1", value] <- parts, do: value) do
      {:ok, timestamp, signatures}
    else
      _malformed -> :error
    end
  end

  defp request(options) do
    [
      base_url: "https://api.stripe.com",
      auth: {:bearer, setting(:secret_key)},
      headers: [{"stripe-version", @version}],
      retry: :transient
    ]
    |> Req.new()
    |> Req.merge(Keyword.get(Application.fetch_env!(:regent_credits, :stripe), :req_options, []))
    |> Req.request(options)
    |> case do
      {:ok, %Req.Response{status: 200, body: %{} = body}} -> {:ok, body}
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:stripe, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp setting(key), do: Keyword.fetch!(Application.fetch_env!(:regent_credits, :stripe), key)

  # Stripe reads nested fields as `a[b][0][c]=value`.
  defp form(params), do: params |> flatten(nil) |> List.flatten()

  defp flatten(map, prefix) when is_map(map),
    do: Enum.map(map, fn {key, value} -> flatten(value, nest(prefix, key)) end)

  defp flatten(list, prefix) when is_list(list),
    do:
      list |> Enum.with_index() |> Enum.map(fn {value, i} -> flatten(value, nest(prefix, i)) end)

  defp flatten(value, prefix), do: {prefix, to_string(value)}

  defp nest(nil, key), do: to_string(key)
  defp nest(prefix, key), do: "#{prefix}[#{key}]"
end

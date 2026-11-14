defmodule RegentNearIntents do
  @moduledoc """
  NEAR Intents 1Click for Regent Elixir apps: one route, NEAR on NEAR to USDC on Base.

  `quote/1` prices an exact amount of USDC on Base in NEAR and, unless it is a dry
  quote, returns the deposit address the person sends their NEAR to. `status/1`
  reads how that deposit is going. `tokens/0` lists the assets 1Click supports.

  The service needs no key. Nothing here keeps state, holds funds or retries: every
  call is made once and the site decides when to ask again. The site keeps its own
  record of each funding.

  Every failure is `{:error, %{reason: reason, message: text}}`, with `reason` one of
  `:invalid_request`, `:not_found`, `:http_error`, `:transport` or
  `:unexpected_response`.

  Tests stub the service with a `Req.Test` plug:

      Application.put_env(:regent_near_intents, :req_options, plug: {Req.Test, MyTest})
  """

  @base_url "https://1click.chaindefuser.com"
  @receive_timeout 15_000

  @origin_asset "nep141:wrap.near"
  @destination_asset "nep141:base-0x833589fcd6edb6e08f4c7c32d4f71b54bda02913.omft.near"
  @slippage_tolerance 100
  @deadline_seconds 3_600

  @states %{
    "PENDING_DEPOSIT" => :pending_deposit,
    "KNOWN_DEPOSIT_TX" => :pending_deposit,
    "INCOMPLETE_DEPOSIT" => :pending_deposit,
    "PROCESSING" => :processing,
    "SUCCESS" => :success,
    "REFUNDED" => :refunded,
    "FAILED" => :failed
  }

  @type error :: %{reason: atom(), message: String.t()}

  @type token :: %{
          asset_id: String.t(),
          symbol: String.t(),
          blockchain: String.t(),
          decimals: non_neg_integer(),
          price: float()
        }

  @type quote_request :: %{
          usdc_amount: pos_integer(),
          recipient: String.t(),
          refund_to: String.t(),
          dry: boolean()
        }

  @type quote_result :: %{
          amount_in: non_neg_integer(),
          amount_in_formatted: String.t(),
          amount_out: non_neg_integer(),
          amount_out_formatted: String.t(),
          time_estimate_s: non_neg_integer(),
          deadline: String.t(),
          deposit_address: String.t() | nil,
          raw: map()
        }

  @type state :: :pending_deposit | :processing | :success | :refunded | :failed

  @type status_result :: %{
          state: state(),
          origin_tx: String.t() | nil,
          destination_tx: String.t() | nil,
          raw: map()
        }

  @doc """
  Lists the assets 1Click supports, each with its USD price as a float.
  """
  @spec tokens() :: {:ok, [token()]} | {:error, error()}
  def tokens do
    with {:ok, body} <- request(method: :get, url: "/v0/tokens") do
      read_tokens(body)
    end
  end

  @doc """
  Quotes `usdc_amount` (USDC base units, 6 decimals) delivered on Base to
  `recipient`, paid in NEAR, with any refund going back to the NEAR account
  `refund_to`.

  A dry quote only prices the swap and has no deposit address. A quote with
  `dry: false` returns the deposit address the NEAR must be sent to before its
  `deadline`, one hour from the request.
  """
  @spec quote(quote_request()) :: {:ok, quote_result()} | {:error, error()}
  def quote(%{usdc_amount: amount, recipient: recipient, refund_to: refund_to, dry: dry} = params)
      when is_integer(amount) and amount > 0 and is_binary(recipient) and is_binary(refund_to) and
             refund_to != "" and is_boolean(dry) do
    if Regex.match?(~r/\A0x[0-9a-fA-F]{40}\z/, recipient) do
      with {:ok, body} <- request(method: :post, url: "/v0/quote", json: quote_body(params)) do
        read_quote(body, dry)
      end
    else
      invalid("recipient must be a 0x address of 40 hex characters")
    end
  end

  def quote(_request) do
    invalid(
      "quote needs usdc_amount (a positive integer), recipient (a 0x address), " <>
        "refund_to (a NEAR account) and dry (true or false)"
    )
  end

  @doc """
  Reads the progress of the swap behind `deposit_address`.

  `state` is `:pending_deposit` until a full deposit has arrived (1Click's
  `PENDING_DEPOSIT`, `KNOWN_DEPOSIT_TX` and `INCOMPLETE_DEPOSIT`), then
  `:processing`, and finally `:success`, `:refunded` or `:failed`. `origin_tx`
  and `destination_tx` are the first transaction hash on each chain, or nil.
  """
  @spec status(String.t()) :: {:ok, status_result()} | {:error, error()}
  def status(deposit_address) when is_binary(deposit_address) and deposit_address != "" do
    with {:ok, body} <-
           request(method: :get, url: "/v0/status", params: [depositAddress: deposit_address]) do
      read_status(body)
    end
  end

  def status(_deposit_address), do: invalid("status needs a deposit address")

  defp quote_body(%{usdc_amount: amount, recipient: recipient, refund_to: refund_to, dry: dry}) do
    %{
      dry: dry,
      swapType: "EXACT_OUTPUT",
      slippageTolerance: @slippage_tolerance,
      originAsset: @origin_asset,
      depositType: "ORIGIN_CHAIN",
      destinationAsset: @destination_asset,
      amount: Integer.to_string(amount),
      refundTo: refund_to,
      refundType: "ORIGIN_CHAIN",
      recipient: recipient,
      recipientType: "DESTINATION_CHAIN",
      deadline: deadline()
    }
  end

  defp deadline do
    DateTime.utc_now()
    |> DateTime.add(@deadline_seconds)
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp read_tokens(body) when is_list(body) do
    Enum.reduce_while(body, {:ok, []}, fn
      %{
        "assetId" => asset_id,
        "symbol" => symbol,
        "blockchain" => blockchain,
        "decimals" => decimals,
        "price" => price
      },
      {:ok, tokens}
      when is_binary(asset_id) and is_binary(symbol) and is_binary(blockchain) and
             is_integer(decimals) and is_number(price) ->
        token = %{
          asset_id: asset_id,
          symbol: symbol,
          blockchain: blockchain,
          decimals: decimals,
          price: price / 1
        }

        {:cont, {:ok, [token | tokens]}}

      _entry, _acc ->
        {:halt, unexpected("a token in the list is missing a field")}
    end)
    |> case do
      {:ok, tokens} -> {:ok, Enum.reverse(tokens)}
      error -> error
    end
  end

  defp read_tokens(_body), do: unexpected("the token list is not a list")

  defp read_quote(
         %{
           "quote" =>
             %{
               "amountIn" => amount_in,
               "amountInFormatted" => amount_in_formatted,
               "amountOut" => amount_out,
               "amountOutFormatted" => amount_out_formatted,
               "timeEstimate" => time_estimate
             } = quote,
           "quoteRequest" => quote_request
         } = body,
         dry
       )
       when is_binary(amount_in_formatted) and is_binary(amount_out_formatted) and
              is_number(time_estimate) do
    with {:ok, amount_in} <- base_units(amount_in),
         {:ok, amount_out} <- base_units(amount_out),
         {:ok, deadline} <- deadline(quote, quote_request),
         {:ok, deposit_address} <- deposit_address(dry, quote) do
      {:ok,
       %{
         amount_in: amount_in,
         amount_in_formatted: amount_in_formatted,
         amount_out: amount_out,
         amount_out_formatted: amount_out_formatted,
         time_estimate_s: round(time_estimate),
         deadline: deadline,
         deposit_address: deposit_address,
         raw: body
       }}
    end
  end

  defp read_quote(_body, _dry), do: unexpected("the quote is missing a field")

  # 1Click sets the deposit address's deadline in the quote it answers; a dry quote
  # has none, so its deadline is the one the request asked for.
  defp deadline(%{"deadline" => deadline}, _request) when is_binary(deadline), do: {:ok, deadline}
  defp deadline(_quote, %{"deadline" => deadline}) when is_binary(deadline), do: {:ok, deadline}
  defp deadline(_quote, _request), do: unexpected("the quote has no deadline")

  defp deposit_address(true, _quote), do: {:ok, nil}

  defp deposit_address(false, %{"depositAddress" => address})
       when is_binary(address) and address != "",
       do: {:ok, address}

  defp deposit_address(false, _quote), do: unexpected("the quote has no deposit address")

  defp base_units(amount) when is_binary(amount) do
    case Integer.parse(amount) do
      {units, ""} when units >= 0 -> {:ok, units}
      _other -> unexpected("an amount is not a whole number of base units")
    end
  end

  defp base_units(_amount), do: unexpected("an amount is not a string")

  defp read_status(%{"status" => status, "swapDetails" => details} = body)
       when is_map_key(@states, status) and is_map(details) do
    with {:ok, origin_tx} <- first_hash(details["originChainTxHashes"]),
         {:ok, destination_tx} <- first_hash(details["destinationChainTxHashes"]) do
      {:ok,
       %{
         state: Map.fetch!(@states, status),
         origin_tx: origin_tx,
         destination_tx: destination_tx,
         raw: body
       }}
    end
  end

  defp read_status(%{"status" => status}) when is_binary(status),
    do: unexpected("1Click reported a status this package does not know: #{status}")

  defp read_status(_body), do: unexpected("the status answer is missing a field")

  defp first_hash([]), do: {:ok, nil}
  defp first_hash([%{"hash" => hash} | _rest]) when is_binary(hash), do: {:ok, hash}
  defp first_hash(_hashes), do: unexpected("a transaction list is not in the documented shape")

  defp request(options) do
    [base_url: @base_url, retry: false, receive_timeout: @receive_timeout]
    |> Keyword.merge(options)
    |> Keyword.merge(Application.get_env(:regent_near_intents, :req_options, []))
    |> Req.request()
    |> answer()
  end

  # The published spec says a quote answers 200; the live service answers 201.
  defp answer({:ok, %Req.Response{status: status, body: body}}) when status in 200..299,
    do: {:ok, body}

  defp answer({:ok, %Req.Response{status: 404, body: body}}),
    do: error(:not_found, "1Click answered 404" <> service_message(body))

  defp answer({:ok, %Req.Response{status: status, body: body}}),
    do: error(:http_error, "1Click answered #{status}" <> service_message(body))

  defp answer({:error, exception}),
    do: error(:transport, "1Click could not be reached: " <> Exception.message(exception))

  defp service_message(%{"message" => message}) when is_binary(message), do: ": " <> message
  defp service_message(_body), do: ""

  defp invalid(message), do: error(:invalid_request, message)
  defp unexpected(message), do: error(:unexpected_response, message)

  defp error(reason, message), do: {:error, %{reason: reason, message: message}}
end

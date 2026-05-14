defmodule Siwa.X402 do
  @behaviour Siwa.PaymentGate

  @headers %{
    payment_required: "Payment-Required",
    payment_signature: "Payment-Signature",
    payment_response: "Payment-Response"
  }

  def headers, do: @headers

  def encode_header(data) do
    data
    |> Jason.encode!()
    |> Base.encode64()
  end

  def decode_header(header) do
    with {:ok, body} <- Base.decode64(header),
         {:ok, data} <- Jason.decode(body) do
      {:ok, data}
    else
      _ -> {:error, :invalid_x402_header}
    end
  end

  def create_memory_session_store do
    table = :ets.new(__MODULE__, [:set, :public])

    %{
      get: fn address, resource ->
        case :ets.lookup(table, {address, resource}) do
          [{{^address, ^resource}, value, expires_at}] ->
            if expires_at > System.system_time(:millisecond), do: {:ok, value}, else: {:ok, nil}

          _ ->
            {:ok, nil}
        end
      end,
      set: fn address, resource, value, ttl_ms ->
        :ets.insert(
          table,
          {{address, resource}, value, System.system_time(:millisecond) + ttl_ms}
        )

        :ok
      end
    }
  end

  def process_payment(payload, accepts, facilitator) do
    with {:ok, verify_result} <- call_facilitator(facilitator, :verify, [payload, accepts]),
         true <- verify_result["valid"],
         {:ok, payment} <- accepted_payment(payload, accepts),
         {:ok, settle_result} <- call_facilitator(facilitator, :settle, [payload, accepts]),
         true <- settle_result["success"],
         {:ok, tx_hash} <- settlement_tx_hash(settle_result) do
      {:ok,
       %{
         valid: true,
         payment: %{
           scheme: payment.scheme,
           network: payment.network,
           amount: payment.amount,
           asset: payment.asset,
           payTo: payment.pay_to,
           txHash: tx_hash
         }
       }}
    else
      false -> {:error, :x402_invalid_payment}
      {:error, reason} -> {:error, reason}
    end
  end

  def verify(_request, opts \\ []) do
    required = Keyword.get(opts, :required, false)
    amount = Keyword.get(opts, :amount, "0")

    cond do
      not required -> {:ok, %{status: "payment_not_required"}}
      true -> {:error, %{status: "payment_required", amount: amount}}
    end
  end

  defp accepted_payment(payload, accepts) when is_list(accepts) do
    payment = payload["payment"] || %{}

    normalized_payment = %{
      scheme: payment["scheme"],
      network: payment["network"],
      amount: payment["amount"],
      asset: payment["asset"],
      pay_to: payment["payTo"]
    }

    if Enum.any?(accepts, &payment_matches_accept?(normalized_payment, &1)) do
      {:ok, normalized_payment}
    else
      {:error, :x402_payment_not_accepted}
    end
  end

  defp accepted_payment(_payload, _accepts), do: {:error, :x402_payment_not_accepted}

  defp payment_matches_accept?(payment, accept) when is_map(accept) do
    payment.scheme == accept["scheme"] and
      payment.network == accept["network"] and
      payment.amount == accept["amount"] and
      payment.asset == accept["asset"] and
      payment.pay_to == accept["payTo"]
  end

  defp payment_matches_accept?(_payment, _accept), do: false

  defp settlement_tx_hash(settle_result) do
    case settle_result["txHash"] do
      "0x" <> rest = tx_hash when byte_size(rest) == 64 ->
        if Regex.match?(~r/\A[0-9a-fA-F]{64}\z/, rest) do
          {:ok, String.downcase(tx_hash)}
        else
          {:error, :x402_invalid_settlement_hash}
        end

      "0x" <> _rest ->
        {:error, :x402_invalid_settlement_hash}

      _value ->
        {:error, :x402_missing_settlement_hash}
    end
  end

  defp call_facilitator(facilitator, name, args) when is_map(facilitator) do
    case Map.fetch(facilitator, name) do
      {:ok, fun} when is_function(fun) -> {:ok, apply(fun, args)}
      :error -> {:error, {:missing_facilitator_callback, name}}
    end
  end

  defp call_facilitator(facilitator, name, args) do
    {:ok, apply(facilitator, name, args)}
  end
end

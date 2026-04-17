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

          _ -> {:ok, nil}
        end
      end,
      set: fn address, resource, value, ttl_ms ->
        :ets.insert(table, {{address, resource}, value, System.system_time(:millisecond) + ttl_ms})
        :ok
      end
    }
  end

  def process_payment(payload, accepts, facilitator) do
    with {:ok, verify_result} <- call_facilitator(facilitator, :verify, [payload, accepts]),
         true <- verify_result.valid || verify_result["valid"],
         {:ok, settle_result} <- call_facilitator(facilitator, :settle, [payload, accepts]),
         true <- settle_result.success || settle_result["success"] do
      payment = payload[:payment] || payload["payment"] || %{}

      {:ok,
       %{
         valid: true,
         payment: %{
           scheme: payment[:scheme] || payment["scheme"],
           network: payment[:network] || payment["network"],
           amount: payment[:amount] || payment["amount"],
           asset: payment[:asset] || payment["asset"],
           payTo: payment[:payTo] || payment["payTo"],
           txHash: settle_result[:txHash] || settle_result["txHash"]
         }
       }}
    else
      false -> {:error, :x402_invalid_payment}
      {:error, reason} -> {:error, reason}
    end
  end

  def verify(request, opts \\ []) do
    required = Keyword.get(opts, :required, false)
    amount = Keyword.get(opts, :amount, "0")
    headers = request[:headers] || request["headers"] || %{}
    normalized = Map.new(headers, fn {k, v} -> {String.downcase(to_string(k)), v} end)

    cond do
      not required -> {:ok, %{status: "payment_not_required"}}
      normalized["payment-response"] == amount -> {:ok, %{status: "paid", amount: amount}}
      true -> {:error, %{status: "payment_required", amount: amount}}
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

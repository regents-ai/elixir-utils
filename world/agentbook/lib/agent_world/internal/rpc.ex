defmodule AgentWorld.Internal.RPC do
  @moduledoc false

  @http_timeout_ms 5_000

  def eth_call(rpc_url, to, data) do
    rpc_request(rpc_url, "eth_call", [%{"to" => String.downcase(to), "data" => data}, "latest"])
  end

  def tx_receipt(rpc_url, tx_hash) do
    rpc_request(rpc_url, "eth_getTransactionReceipt", [tx_hash])
  end

  def relay_post(url, body, idempotency_key) do
    case Req.post(
           url: url,
           json: body,
           headers: [{"idempotency-key", idempotency_key}],
           receive_timeout: @http_timeout_ms,
           connect_options: [timeout: @http_timeout_ms],
           retry: false
         ) do
      {:ok, %{status: status, body: payload}} when status in 200..299 ->
        {:ok, payload}

      {:ok, %{status: status, body: _payload}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp rpc_request(rpc_url, method, params) do
    case Siwa.RPCClient.call(rpc_url, method, params) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end
end

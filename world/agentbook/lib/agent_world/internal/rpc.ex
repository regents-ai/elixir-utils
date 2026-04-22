defmodule AgentWorld.Internal.RPC do
  @moduledoc false

  def eth_call(rpc_url, to, data) do
    rpc_request(rpc_url, "eth_call", [%{"to" => String.downcase(to), "data" => data}, "latest"])
  end

  def tx_receipt(rpc_url, tx_hash) do
    rpc_request(rpc_url, "eth_getTransactionReceipt", [tx_hash])
  end

  def relay_post(url, body) do
    case Req.post(url: url, json: body) do
      {:ok, %{status: status, body: payload}} when status in 200..299 ->
        {:ok, payload}

      {:ok, %{status: status, body: payload}} ->
        {:error, {:http_error, status, payload}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp rpc_request(rpc_url, method, params) do
    payload = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => method,
      "params" => params
    }

    case Req.post(url: rpc_url, json: payload) do
      {:ok, %{body: %{"result" => result}}} ->
        {:ok, result}

      {:ok, %{body: %{"error" => error}}} ->
        {:error, {:rpc_error, error}}

      {:ok, %{body: body}} ->
        {:error, {:unexpected_body, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end

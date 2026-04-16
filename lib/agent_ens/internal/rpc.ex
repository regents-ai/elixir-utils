defmodule AgentEns.Internal.RPC do
  @moduledoc false

  @callback eth_call(String.t(), String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}

  @spec eth_call(String.t(), String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def eth_call(rpc_url, to, data) do
    payload = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "eth_call",
      "params" => [%{"to" => String.downcase(to), "data" => data}, "latest"]
    }

    case Req.post(url: rpc_url, json: payload) do
      {:ok, %{body: %{"result" => result}}} when is_binary(result) ->
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

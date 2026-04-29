defmodule AgentEns.Internal.RPC do
  @moduledoc false

  @callback eth_call(String.t(), String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}

  @spec eth_call(String.t(), String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def eth_call(rpc_url, to, data) do
    case Siwa.RPCClient.call(rpc_url, "eth_call", [
           %{"to" => String.downcase(to), "data" => data},
           "latest"
         ]) do
      {:ok, result} when is_binary(result) ->
        {:ok, result}

      {:ok, result} ->
        {:error, {:unexpected_body, result}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end

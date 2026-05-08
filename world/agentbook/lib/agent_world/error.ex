defmodule AgentWorld.Error do
  @moduledoc """
  Structured error used by the shared AgentBook helpers.
  """

  defexception [:kind, :message, details: %{}]

  @type kind :: :invalid_argument | :unsupported | :io | :internal

  @type t :: %__MODULE__{
          kind: kind(),
          message: String.t(),
          details: map()
        }

  @spec new(term()) :: t()
  def new(reason), do: from_reason(reason)

  @spec invalid_argument(String.t(), map()) :: t()
  def invalid_argument(message, details \\ %{}),
    do: %__MODULE__{kind: :invalid_argument, message: message, details: details}

  @spec unsupported(String.t(), map()) :: t()
  def unsupported(message, details \\ %{}),
    do: %__MODULE__{kind: :unsupported, message: message, details: details}

  @spec io(String.t(), map()) :: t()
  def io(message, details \\ %{}), do: %__MODULE__{kind: :io, message: message, details: details}

  @spec internal(String.t(), map()) :: t()
  def internal(message, details \\ %{}),
    do: %__MODULE__{kind: :internal, message: message, details: details}

  defp from_reason({:missing_required_input, field}) do
    invalid_argument("Missing required input: #{field}", %{field: field})
  end

  defp from_reason({:invalid_address, value}) do
    invalid_argument("Invalid address: #{value}", %{value: value})
  end

  defp from_reason({:invalid_network, value}) do
    invalid_argument("Invalid network: #{inspect(value)}", %{value: value})
  end

  defp from_reason({:invalid_tx_hash, value}) do
    invalid_argument("Invalid transaction hash: #{inspect(value)}", %{value: value})
  end

  defp from_reason({:invalid_uint256, value}) do
    invalid_argument("Invalid uint256 value: #{inspect(value)}", %{value: value})
  end

  defp from_reason({:invalid_agentkit_header, message}) do
    invalid_argument(message, %{})
  end

  defp from_reason({:invalid_agentkit_message, message}) do
    invalid_argument(message, %{})
  end

  defp from_reason({:invalid_signature, message}) do
    invalid_argument(message, %{})
  end

  defp from_reason({:missing_network_rpc, network}) do
    io("Missing RPC URL for AgentBook network #{network}", %{network: network})
  end

  defp from_reason({:missing_world_id_config, key}) do
    io("Missing World ID configuration: #{key}", %{key: key})
  end

  defp from_reason({:rpc_error, reason}) do
    io("RPC request failed: #{inspect(reason)}", %{reason: reason})
  end

  defp from_reason({:unexpected_body, body}) do
    io("Unexpected HTTP response body: #{inspect(body)}", %{body: body})
  end

  defp from_reason({:invalid_rpc_result, result}) do
    io("Invalid RPC result: #{inspect(result)}", %{result: result})
  end

  defp from_reason({:relay_failed, reason}) do
    io("Registration relay failed", relay_error_details(reason))
  end

  defp from_reason({:relay_missing_tx_hash, _body}) do
    io("Registration relay did not return a transaction hash", %{})
  end

  defp from_reason(:missing_registration_expiry) do
    invalid_argument("Registration session is missing an expiry.", %{})
  end

  defp from_reason({:invalid_registration_expiry, value}) do
    invalid_argument("Registration session has an invalid expiry.", %{expires_at: inspect(value)})
  end

  defp from_reason({:expired_registration_session, expires_at}) do
    invalid_argument("Registration session has expired.", %{expires_at: expires_at})
  end

  defp from_reason({:unsupported_chain_namespace, chain_id}) do
    unsupported("Unsupported chain namespace: #{chain_id}", %{chain_id: chain_id})
  end

  defp from_reason({:unsupported_signature_type, type}) do
    unsupported("Unsupported signature type: #{inspect(type)}", %{type: type})
  end

  defp from_reason({:registration_failed, message}) when is_binary(message) do
    io(message, %{})
  end

  defp from_reason({:abi_error, reason}) do
    invalid_argument("ABI encoding error: #{inspect(reason)}", %{reason: reason})
  end

  defp from_reason(reason) do
    internal("Unexpected AgentBook error: #{inspect(reason)}", %{reason: reason})
  end

  defp relay_error_details({:http_error, status}) when is_integer(status), do: %{status: status}
  defp relay_error_details(_reason), do: %{}
end

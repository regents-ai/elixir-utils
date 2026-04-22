defmodule AgentWorld do
  @moduledoc """
  Shared entry point for AgentBook lookup, registration, and AgentKit verification.
  """

  alias AgentWorld.Agentkit

  @spec parse_agentkit_header(String.t()) :: {:ok, map()} | {:error, AgentWorld.Error.t()}
  def parse_agentkit_header(header), do: Agentkit.parse_agentkit_header(header)

  @spec validate_agentkit_message(map(), String.t(), map() | keyword()) ::
          {:ok, %{valid: true}} | {:error, AgentWorld.Error.t()}
  def validate_agentkit_message(payload, resource_uri, opts \\ %{}) do
    Agentkit.validate_agentkit_message(payload, resource_uri, opts)
  end

  @spec verify_agentkit_signature(map(), map() | keyword()) ::
          {:ok, %{address: String.t(), valid: true}} | {:error, AgentWorld.Error.t()}
  def verify_agentkit_signature(payload, opts \\ %{}) do
    Agentkit.verify_agentkit_signature(payload, opts)
  end
end

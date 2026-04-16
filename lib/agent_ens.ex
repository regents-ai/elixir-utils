defmodule AgentEns do
  @moduledoc """
  Elixir implementation of ENSIP-25.

  The package ports the core surface of [`qntx/ensip25`](https://github.com/qntx/ensip25):

  - `AgentEns.ERC7930` for interoperable address encoding and decoding
  - `AgentEns.RecordKey` for ENSIP-25 text record key construction
  - `AgentEns.Verify` for RPC-backed ENS text-record verification
  - `AgentEns.Error` for typed error values
  - `AgentEns.Plan` for read-only link planning
  - `AgentEns.Tx` for unsigned transaction builders
  - `AgentEns.Link` for high-level orchestration
  """

  alias AgentEns.ERC7930
  alias AgentEns.Link
  alias AgentEns.Plan
  alias AgentEns.RecordKey
  alias AgentEns.Verify

  @doc """
  Convenience wrapper for `AgentEns.RecordKey.evm_record_key/3`.
  """
  @spec evm_record_key(non_neg_integer(), String.t(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, AgentEns.Error.t()}
  def evm_record_key(chain_id, registry_address, agent_id) do
    RecordKey.evm_record_key(chain_id, registry_address, agent_id)
  end

  @doc """
  Convenience wrapper for `AgentEns.ERC7930.evm/2`.
  """
  @spec interoperable_address(non_neg_integer(), String.t()) ::
          {:ok, ERC7930.t()} | {:error, AgentEns.Error.t()}
  def interoperable_address(chain_id, address) do
    ERC7930.evm(chain_id, address)
  end

  @doc """
  Convenience wrapper for `AgentEns.Plan.plan_link/1`.
  """
  @spec plan_link(map()) :: {:ok, Plan.LinkPlan.t()} | {:error, AgentEns.Error.t()}
  def plan_link(input), do: Plan.plan_link(input)

  @doc """
  Convenience wrapper for `AgentEns.Verify.verify/6`.
  """
  @spec verify(
          String.t(),
          String.t(),
          non_neg_integer(),
          String.t(),
          non_neg_integer(),
          keyword()
        ) ::
          {:ok, Verify.verification_status()} | {:error, AgentEns.Error.t()}
  def verify(rpc_url, ens_name, chain_id, registry_address, agent_id, opts \\ []) do
    Verify.verify(rpc_url, ens_name, chain_id, registry_address, agent_id, opts)
  end

  @doc """
  Convenience wrapper for `AgentEns.Verify.verify_agent/5`.
  """
  @spec verify_agent(String.t(), atom(), non_neg_integer(), String.t(), keyword()) ::
          {:ok, Verify.verification_status()} | {:error, AgentEns.Error.t()}
  def verify_agent(rpc_url, network, agent_id, ens_name, opts \\ []) do
    Verify.verify_agent(rpc_url, network, agent_id, ens_name, opts)
  end

  @doc """
  Convenience wrapper for `AgentEns.Link.prepare_ensip25_update/1`.
  """
  @spec prepare_ensip25_update(map()) ::
          {:ok, %{plan: Plan.LinkPlan.t(), tx: AgentEns.TxRequest.t()}}
          | {:error, AgentEns.Error.t()}
  def prepare_ensip25_update(input), do: Link.prepare_ensip25_update(input)

  @doc """
  Convenience wrapper for `AgentEns.Link.prepare_erc8004_update/1`.
  """
  @spec prepare_erc8004_update(map()) ::
          {:ok, %{plan: Plan.LinkPlan.t(), new_registration: map(), tx: AgentEns.TxRequest.t()}}
          | {:error, AgentEns.Error.t()}
  def prepare_erc8004_update(input), do: Link.prepare_erc8004_update(input)

  @doc """
  Convenience wrapper for `AgentEns.Link.prepare_bidirectional_link/1`.
  """
  @spec prepare_bidirectional_link(map()) ::
          {:ok, map()} | {:error, AgentEns.Error.t()}
  def prepare_bidirectional_link(input), do: Link.prepare_bidirectional_link(input)
end

defmodule AgentEns.Link do
  @moduledoc """
  High-level orchestration for planning and preparing ENS <-> ERC-8004 linking.
  """

  alias AgentEns.Error
  alias AgentEns.ERC8004.Registration
  alias AgentEns.Plan
  alias AgentEns.Tx

  @spec plan(map()) :: {:ok, Plan.LinkPlan.t()} | {:error, Error.t()}
  def plan(input), do: Plan.plan_link(input)

  @spec prepare_erc8004_update(map()) ::
          {:ok, %{plan: Plan.LinkPlan.t(), new_registration: map(), tx: AgentEns.TxRequest.t()}}
          | {:error, Error.t()}
  def prepare_erc8004_update(input) when is_map(input) do
    with {:ok, plan} <- Plan.plan_link(input),
         :ok <- ensure_action_ready(plan, :update_erc8004_registration),
         {:ok, prepared} <-
           Registration.prepare_updated_registration(%{
             current_agent_uri: plan.erc8004_token_uri,
             ens_name: plan.normalized_ens_name,
             fetcher: Map.get(input, :erc8004_fetcher) || Map.get(input, "erc8004_fetcher"),
             publisher:
               Map.get(input, :publisher) ||
                 Map.get(input, "publisher") ||
                 Registration.DataUriPublisher,
             opts:
               Map.get(input, :erc8004_fetch_opts) || Map.get(input, "erc8004_fetch_opts") || []
           }),
         {:ok, tx} <-
           Tx.build_set_agent_uri_tx(%{
             chain_id: Map.get(input, :chain_id) || Map.get(input, "chain_id"),
             registry_address:
               Map.get(input, :registry_address) || Map.get(input, "registry_address"),
             agent_id: Map.get(input, :agent_id) || Map.get(input, "agent_id"),
             new_uri: prepared.new_uri
           }) do
      {:ok, %{plan: plan, new_registration: prepared.new_registration, tx: tx}}
    end
  end

  @spec prepare_ensip25_update(map()) ::
          {:ok, %{plan: Plan.LinkPlan.t(), tx: AgentEns.TxRequest.t()}} | {:error, Error.t()}
  def prepare_ensip25_update(input) when is_map(input) do
    with {:ok, plan} <- Plan.plan_link(input),
         :ok <- ensure_action_ready(plan, :set_ens_text),
         {:ok, tx} <-
           Tx.build_set_text_tx(%{
             ens_name: plan.normalized_ens_name,
             chain_id: Map.get(input, :chain_id) || Map.get(input, "chain_id"),
             registry_address:
               Map.get(input, :registry_address) || Map.get(input, "registry_address"),
             agent_id: Map.get(input, :agent_id) || Map.get(input, "agent_id"),
             resolver_address: plan.resolver_address,
             value: Map.get(input, :value) || Map.get(input, "value") || "1"
           }) do
      {:ok, %{plan: plan, tx: tx}}
    end
  end

  @spec prepare_bidirectional_link(map()) ::
          {:ok,
           %{
             plan: Plan.LinkPlan.t(),
             erc8004: map() | :noop | :blocked,
             ensip25: map() | :noop | :blocked,
             reverse: map() | :noop | :skipped
           }}
          | {:error, Error.t()}
  def prepare_bidirectional_link(input) when is_map(input) do
    with {:ok, plan} <- Plan.plan_link(input) do
      {:ok,
       %{
         plan: plan,
         erc8004: maybe_prepare_erc8004(plan, input),
         ensip25: maybe_prepare_ensip25(plan, input),
         reverse: maybe_prepare_reverse(plan, input)
       }}
    end
  end

  defp maybe_prepare_erc8004(plan, _input) when plan.erc8004_status == :ens_service_present,
    do: :noop

  defp maybe_prepare_erc8004(_plan, input) do
    case prepare_erc8004_update(input) do
      {:ok, prepared} -> prepared
      {:error, _} -> :blocked
    end
  end

  defp maybe_prepare_ensip25(plan, _input) when plan.verify_status == :verified, do: :noop

  defp maybe_prepare_ensip25(_plan, input) do
    case prepare_ensip25_update(input) do
      {:ok, prepared} -> prepared
      {:error, _} -> :blocked
    end
  end

  defp maybe_prepare_reverse(%{reverse_status: :not_requested}, _input), do: :skipped
  defp maybe_prepare_reverse(%{reverse_status: :unsupported_network}, _input), do: :blocked
  defp maybe_prepare_reverse(%{reverse_status: :signer_required}, _input), do: :blocked

  defp maybe_prepare_reverse(plan, input) do
    case Tx.build_reverse_set_name_tx(%{
           chain_id: Map.get(input, :chain_id) || Map.get(input, "chain_id"),
           ens_name: plan.normalized_ens_name,
           reverse_registrar:
             Map.get(input, :reverse_registrar) || Map.get(input, "reverse_registrar")
         }) do
      {:ok, tx} -> %{tx: tx}
      {:error, _} -> :blocked
    end
  end

  defp ensure_action_ready(plan, kind) do
    case Enum.find(plan.actions, &(&1.kind == kind)) do
      %{status: :ready} ->
        :ok

      %{status: :noop} ->
        {:error, Error.new({:unexpected_state, {kind, :already_satisfied}})}

      %{reason: reason} ->
        {:error, Error.new({:unexpected_state, {kind, reason}})}

      nil ->
        {:error, Error.new({:not_found, kind})}
    end
  end
end

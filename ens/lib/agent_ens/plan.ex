defmodule AgentEns.Plan do
  @moduledoc """
  Read-only planning for ENS and ERC-8004 links.

  This module answers the question "what is true right now, and what can happen
  next?" without preparing or sending anything.

  Use it when you want to:

  - check whether the ENS proof already exists
  - check whether the agent registration already points back to the ENS name
  - see whether the current signer can make the needed changes
  - decide whether a reverse name can also be updated

  The returned `LinkPlan` is a snapshot you can use to build a review screen,
  power a CLI explanation, or decide which request to prepare next.
  """

  alias AgentEns.Error
  alias AgentEns.ERC7930
  alias AgentEns.ERC8004.Registration
  alias AgentEns.Internal.Contract
  alias AgentEns.Internal.RPC
  alias AgentEns.Networks
  alias AgentEns.Normalize
  alias AgentEns.RecordKey
  alias AgentEns.Verify

  defmodule Input do
    @moduledoc """
    Input values used to build a read-only link plan.
    """

    @enforce_keys [:ens_name, :chain_id, :registry_address, :agent_id, :rpc_url]
    defstruct [
      :ens_name,
      :chain_id,
      :registry_address,
      :agent_id,
      :rpc_url,
      :rpc_module,
      :signer_address,
      :include_reverse?,
      :ens_registry,
      :name_wrapper,
      :reverse_registrar,
      :erc8004_fetcher,
      :erc8004_fetch_opts,
      :current_agent_uri
    ]

    @type t :: %__MODULE__{
            ens_name: String.t(),
            chain_id: non_neg_integer(),
            registry_address: String.t(),
            agent_id: non_neg_integer() | String.t(),
            rpc_url: String.t(),
            rpc_module: module() | nil,
            signer_address: String.t() | nil,
            include_reverse?: boolean() | nil,
            ens_registry: String.t() | nil,
            name_wrapper: String.t() | nil,
            reverse_registrar: String.t() | nil,
            erc8004_fetcher: module() | nil,
            erc8004_fetch_opts: keyword() | nil,
            current_agent_uri: String.t() | nil
          }
  end

  defmodule Action do
    @moduledoc """
    One recommended next step in a link plan.
    """

    @enforce_keys [:kind, :status, :description]
    defstruct [:kind, :status, :description, :reason]

    @type t :: %__MODULE__{
            kind: :set_ens_text | :update_erc8004_registration | :set_reverse_name,
            status: :noop | :ready | :blocked | :skipped,
            description: String.t(),
            reason: atom() | nil
          }
  end

  defmodule LinkPlan do
    @moduledoc """
    Read-only snapshot of the current ENS and ERC-8004 link state.

    The most important fields for app code are usually:

    - `verify_status` for the ENS proof
    - `erc8004_status` for the agent registration side
    - `actions` for the human-friendly next steps
    - `warnings` for anything worth calling out before approval
    """

    @enforce_keys [
      :normalized_ens_name,
      :node,
      :ensip25_key,
      :verify_status,
      :erc8004_status,
      :ens_write_status,
      :reverse_status,
      :actions,
      :warnings
    ]
    defstruct [
      :normalized_ens_name,
      :node,
      :ensip25_key,
      :verify_status,
      :erc8004_status,
      :ens_write_status,
      :reverse_status,
      :erc8004_write_status,
      :resolver_address,
      :ens_manager,
      :ens_manager_source,
      :signer_address,
      :erc8004_owner,
      :erc8004_token_uri,
      :erc8004_registration,
      :ens_text_value,
      :token_approval,
      :approved_for_all,
      :actions,
      :warnings
    ]

    @type t :: %__MODULE__{
            normalized_ens_name: String.t(),
            node: String.t(),
            ensip25_key: String.t(),
            verify_status: Verify.verification_status(),
            erc8004_status: :ens_service_missing | :ens_service_present | :ens_service_mismatch,
            ens_write_status:
              :no_resolver
              | :signer_required
              | :manager_mismatch
              | :ready
              | :unsupported_offchain_resolver
              | :resolver_unsupported,
            reverse_status: :not_requested | :unsupported_network | :signer_required | :ready,
            erc8004_write_status:
              :signer_required | :ready | :forbidden | :registration_unavailable | nil,
            resolver_address: String.t() | nil,
            ens_manager: String.t() | nil,
            ens_manager_source: :registry_owner | :name_wrapper_owner | nil,
            signer_address: String.t() | nil,
            erc8004_owner: String.t() | nil,
            erc8004_token_uri: String.t() | nil,
            erc8004_registration: map() | nil,
            ens_text_value: String.t() | nil,
            token_approval: String.t() | nil,
            approved_for_all: boolean() | nil,
            actions: [Action.t()],
            warnings: [String.t()]
          }
  end

  @type plan_input :: Input.t() | map()
  @type link_plan :: LinkPlan.t()
  @type agent_contract_state :: %{
          token_owner: String.t() | nil,
          token_approval: String.t() | nil,
          approved_for_all: boolean(),
          token_uri: String.t() | nil,
          registration: map() | nil,
          token_reads_supported?: boolean()
        }

  @spec plan_link(plan_input()) :: {:ok, link_plan()} | {:error, Error.t()}
  def plan_link(%Input{} = input), do: do_plan(input)

  def plan_link(%{} = params) do
    with {:ok, input} <- build_input(params) do
      do_plan(input)
    end
  end

  defp do_plan(%Input{} = input) do
    rpc = input.rpc_module || RPC
    network = Networks.get(input.chain_id) || %{}
    ens_registry = input.ens_registry || Map.get(network, :ens_registry)
    name_wrapper = input.name_wrapper || Map.get(network, :name_wrapper)
    reverse_registrar = input.reverse_registrar || Map.get(network, :reverse_registrar)
    signer_address = normalize_address(input.signer_address)

    with {:ok, normalized_name} <- Normalize.normalize(input.ens_name),
         {:ok, node} <- Verify.namehash(normalized_name),
         {:ok, key} <- record_key(input.chain_id, input.registry_address, input.agent_id),
         {:ok, resolver} <- Contract.fetch_resolver(rpc, input.rpc_url, ens_registry, node),
         {:ok, resolver_support} <- classify_resolver_support(rpc, input.rpc_url, resolver),
         {:ok, text_value} <-
           fetch_text_value(rpc, input.rpc_url, resolver, resolver_support, node, key),
         {:ok, ens_owner} <- Contract.fetch_registry_owner(rpc, input.rpc_url, ens_registry, node),
         {:ok, {ens_manager, ens_manager_source}} <-
           resolve_manager(rpc, input.rpc_url, ens_owner, name_wrapper, node),
         {:ok, agent_contract_state} <-
           fetch_agent_contract_state(
             rpc,
             input.rpc_url,
             input.registry_address,
             input.agent_id,
             signer_address,
             input.current_agent_uri,
             input.erc8004_fetcher,
             input.erc8004_fetch_opts || []
           ),
         verify_status <- verify_status(text_value),
         erc8004_status <- erc8004_status(agent_contract_state.registration, normalized_name),
         ens_write_status <-
           ens_write_status(resolver, resolver_support, ens_manager, signer_address),
         erc8004_write_status <-
           erc8004_write_status(
             agent_contract_state,
             signer_address,
             input.agent_id
           ),
         reverse_status <-
           reverse_status(input.include_reverse?, reverse_registrar, signer_address),
         actions <-
           build_actions(
             verify_status,
             erc8004_status,
             ens_write_status,
             erc8004_write_status,
             reverse_status
           ),
         warnings <-
           build_warnings(
             normalized_name,
             resolver,
             agent_contract_state,
             ens_manager_source,
             resolver_support
           ) do
      {:ok,
       %LinkPlan{
         normalized_ens_name: normalized_name,
         node: "0x" <> Base.encode16(node, case: :lower),
         ensip25_key: key,
         verify_status: verify_status,
         erc8004_status: erc8004_status,
         ens_write_status: ens_write_status,
         reverse_status: reverse_status,
         erc8004_write_status: erc8004_write_status,
         resolver_address: resolver,
         ens_manager: ens_manager,
         ens_manager_source: ens_manager_source,
         signer_address: signer_address,
         erc8004_owner: agent_contract_state.token_owner,
         erc8004_token_uri: agent_contract_state.token_uri,
         erc8004_registration: agent_contract_state.registration,
         ens_text_value: text_value,
         token_approval: agent_contract_state.token_approval,
         approved_for_all: agent_contract_state.approved_for_all,
         actions: actions,
         warnings: warnings
       }}
    else
      {:error, %Error{} = error} -> {:error, error}
      {:error, reason} -> {:error, Error.new({:unexpected_state, reason})}
    end
  end

  defp build_input(params) do
    with {:ok, ens_name} <- required_binary(params, :ens_name),
         {:ok, chain_id} <- required_integer(params, :chain_id),
         {:ok, registry_address} <- required_binary(params, :registry_address),
         {:ok, agent_id} <- required_agent_id(params),
         {:ok, rpc_url} <- required_binary(params, :rpc_url) do
      {:ok,
       %Input{
         ens_name: ens_name,
         chain_id: chain_id,
         registry_address: String.downcase(registry_address),
         agent_id: agent_id,
         rpc_url: rpc_url,
         rpc_module: Map.get(params, :rpc_module) || Map.get(params, "rpc_module"),
         signer_address: Map.get(params, :signer_address) || Map.get(params, "signer_address"),
         include_reverse?:
           truthy?(Map.get(params, :include_reverse?) || Map.get(params, "include_reverse?")),
         ens_registry: Map.get(params, :ens_registry) || Map.get(params, "ens_registry"),
         name_wrapper: Map.get(params, :name_wrapper) || Map.get(params, "name_wrapper"),
         reverse_registrar:
           Map.get(params, :reverse_registrar) || Map.get(params, "reverse_registrar"),
         erc8004_fetcher: Map.get(params, :erc8004_fetcher) || Map.get(params, "erc8004_fetcher"),
         erc8004_fetch_opts:
           Map.get(params, :erc8004_fetch_opts) || Map.get(params, "erc8004_fetch_opts"),
         current_agent_uri:
           Map.get(params, :current_agent_uri) || Map.get(params, "current_agent_uri")
       }}
    end
  end

  defp record_key(chain_id, registry_address, agent_id) when is_integer(agent_id) do
    RecordKey.evm_record_key(chain_id, registry_address, agent_id)
  end

  defp record_key(chain_id, registry_address, agent_id) when is_binary(agent_id) do
    with {:ok, interop} <- ERC7930.evm(chain_id, registry_address) do
      RecordKey.record_key(interop, agent_id)
    end
  end

  defp resolve_manager(_rpc, _rpc_url, owner, nil, _node), do: {:ok, {owner, :registry_owner}}

  defp resolve_manager(rpc, rpc_url, owner, name_wrapper, node) when is_binary(name_wrapper) do
    if owner != String.downcase(name_wrapper) do
      {:ok, {owner, :registry_owner}}
    else
      with {:ok, wrapped_owner} <- Contract.fetch_wrapped_owner(rpc, rpc_url, name_wrapper, node) do
        {:ok, {wrapped_owner, :name_wrapper_owner}}
      end
    end
  end

  defp resolve_manager(_rpc, _rpc_url, _owner, _name_wrapper, _node),
    do: {:error, Error.new({:wrapped_name_owner_lookup_failed, :missing_name_wrapper})}

  defp classify_resolver_support(_rpc, _rpc_url, nil), do: {:ok, :no_resolver}

  defp classify_resolver_support(rpc, rpc_url, resolver) do
    with {:ok, supports_text?} <- Contract.supports_text?(rpc, rpc_url, resolver) do
      cond do
        supports_text? ->
          {:ok, :text_write_supported}

        true ->
          case Contract.supports_extended_resolver?(rpc, rpc_url, resolver) do
            {:ok, true} -> {:ok, :offchain_only}
            {:ok, false} -> {:ok, :resolver_unsupported}
            {:error, %Error{} = error} -> {:error, error}
          end
      end
    end
  end

  defp fetch_text_value(_rpc, _rpc_url, nil, :no_resolver, _node, _key), do: {:ok, ""}

  defp fetch_text_value(rpc, rpc_url, resolver, :text_write_supported, node, key) do
    Contract.fetch_text_record(rpc, rpc_url, resolver, node, key)
  end

  defp fetch_text_value(_rpc, _rpc_url, _resolver, :offchain_only, _node, _key), do: {:ok, ""}

  defp fetch_text_value(_rpc, _rpc_url, _resolver, :resolver_unsupported, _node, _key),
    do: {:ok, ""}

  defp maybe_fetch_approval_for_all(_rpc, _rpc_url, _registry_address, _owner, nil),
    do: {:ok, false}

  defp maybe_fetch_approval_for_all(_rpc, _rpc_url, _registry_address, owner, signer)
       when owner == signer, do: {:ok, false}

  defp maybe_fetch_approval_for_all(rpc, rpc_url, registry_address, owner, signer) do
    Contract.approved_for_all?(rpc, rpc_url, registry_address, owner, signer)
  end

  @spec fetch_agent_contract_state(
          module(),
          String.t(),
          String.t(),
          non_neg_integer() | String.t(),
          String.t() | nil,
          String.t() | nil,
          module() | nil,
          keyword()
        ) :: {:ok, agent_contract_state()} | {:error, Error.t()}
  defp fetch_agent_contract_state(
         rpc,
         rpc_url,
         registry_address,
         agent_id,
         signer_address,
         current_agent_uri,
         fetcher,
         opts
       )
       when is_integer(agent_id) do
    with {:ok, token_owner} <-
           Contract.fetch_token_owner(rpc, rpc_url, registry_address, agent_id),
         {:ok, token_approval} <-
           Contract.fetch_token_approval(rpc, rpc_url, registry_address, agent_id),
         {:ok, approved_for_all} <-
           maybe_fetch_approval_for_all(
             rpc,
             rpc_url,
             registry_address,
             token_owner,
             signer_address
           ),
         {:ok, token_uri} <-
           fetch_token_uri(rpc, rpc_url, registry_address, agent_id, current_agent_uri),
         {:ok, registration} <- maybe_parse_registration(token_uri, fetcher, opts) do
      {:ok,
       %{
         token_owner: token_owner,
         token_approval: token_approval,
         approved_for_all: approved_for_all,
         token_uri: token_uri,
         registration: registration,
         token_reads_supported?: true
       }}
    end
  end

  defp fetch_agent_contract_state(
         _rpc,
         _rpc_url,
         _registry_address,
         agent_id,
         _signer_address,
         current_agent_uri,
         fetcher,
         opts
       )
       when is_binary(agent_id) do
    with {:ok, registration} <- maybe_parse_registration(current_agent_uri, fetcher, opts) do
      {:ok,
       %{
         token_owner: nil,
         token_approval: nil,
         approved_for_all: false,
         token_uri: current_agent_uri,
         registration: registration,
         token_reads_supported?: false
       }}
    end
  end

  defp fetch_token_uri(_rpc, _rpc_url, _registry_address, _agent_id, value)
       when is_binary(value) and value != "" do
    {:ok, value}
  end

  defp fetch_token_uri(rpc, rpc_url, registry_address, agent_id, _value) do
    Contract.fetch_token_uri(rpc, rpc_url, registry_address, agent_id)
  end

  defp maybe_parse_registration(uri, _fetcher, _opts) when uri in [nil, ""], do: {:ok, nil}

  defp maybe_parse_registration(uri, fetcher, opts) do
    fetcher = fetcher || Registration.DefaultFetcher

    with {:ok, payload} <- Registration.fetch(uri, fetcher, opts),
         {:ok, registration} <- Registration.parse_registration(payload) do
      {:ok, registration}
    else
      {:error, %Error{}} -> {:ok, nil}
    end
  end

  defp verify_status(value) when is_binary(value) and value != "", do: :verified
  defp verify_status(_), do: :ens_record_missing

  defp erc8004_status(nil, _ens_name), do: :ens_service_missing

  defp erc8004_status(registration, ens_name) do
    case normalized_ens_service_endpoint(registration) do
      nil -> :ens_service_missing
      ^ens_name -> :ens_service_present
      _other -> :ens_service_mismatch
    end
  end

  defp ens_write_status(nil, _resolver_support, _manager, _signer), do: :no_resolver

  defp ens_write_status(_resolver, _resolver_support, _manager, nil), do: :signer_required

  defp ens_write_status(_resolver, _resolver_support, manager, signer) when manager != signer,
    do: :manager_mismatch

  defp ens_write_status(_resolver, :text_write_supported, _manager, _signer), do: :ready

  defp ens_write_status(_resolver, :offchain_only, _manager, _signer),
    do: :unsupported_offchain_resolver

  defp ens_write_status(_resolver, :resolver_unsupported, _manager, _signer),
    do: :resolver_unsupported

  defp ens_write_status(_resolver, _resolver_support, _manager, _signer),
    do: :resolver_unsupported

  defp erc8004_write_status(_agent_contract_state, nil, _agent_id),
    do: :signer_required

  defp erc8004_write_status(%{token_reads_supported?: false}, _signer, _agent_id),
    do: :registration_unavailable

  defp erc8004_write_status(
         %{token_owner: owner, registration: registration},
         signer,
         _agent_id
       )
       when owner == signer,
       do: maybe_require_registration(registration)

  defp erc8004_write_status(
         %{token_approval: approval, registration: registration},
         signer,
         _agent_id
       )
       when approval == signer and is_binary(signer),
       do: maybe_require_registration(registration)

  defp erc8004_write_status(
         %{approved_for_all: true, registration: registration},
         _signer,
         _agent_id
       ),
       do: maybe_require_registration(registration)

  defp erc8004_write_status(_agent_contract_state, _signer, _agent_id),
    do: :forbidden

  defp reverse_status(false, _reverse_registrar, _signer), do: :not_requested
  defp reverse_status(true, nil, _signer), do: :unsupported_network
  defp reverse_status(true, _reverse_registrar, nil), do: :signer_required
  defp reverse_status(true, _reverse_registrar, _signer), do: :ready

  defp build_actions(
         verify_status,
         erc8004_status,
         ens_write_status,
         erc8004_write_status,
         reverse_status
       ) do
    [
      %Action{
        kind: :set_ens_text,
        status: action_status(verify_status == :verified, ens_write_status == :ready),
        description: "Set the ENSIP-25 text record on the ENS name",
        reason: action_reason(verify_status == :verified, ens_write_status)
      },
      %Action{
        kind: :update_erc8004_registration,
        status:
          action_status(erc8004_status == :ens_service_present, erc8004_write_status == :ready),
        description: "Update the ERC-8004 registration file to include the ENS service entry",
        reason: action_reason(erc8004_status == :ens_service_present, erc8004_write_status)
      },
      %Action{
        kind: :set_reverse_name,
        status:
          case reverse_status do
            :not_requested -> :skipped
            :ready -> :ready
            _ -> :blocked
          end,
        description: "Set the reverse ENS primary name",
        reason: if(reverse_status in [:not_requested, :ready], do: nil, else: reverse_status)
      }
    ]
  end

  defp action_status(true, _ready), do: :noop
  defp action_status(false, true), do: :ready
  defp action_status(false, false), do: :blocked

  defp action_reason(true, _status), do: nil
  defp action_reason(false, :ready), do: nil
  defp action_reason(false, status), do: status

  defp build_warnings(
         normalized_name,
         resolver,
         agent_contract_state,
         manager_source,
         resolver_support
       ) do
    []
    |> maybe_add_warning(
      manager_source == :name_wrapper_owner,
      "ENS name is wrapped, so manager checks use the Name Wrapper owner."
    )
    |> maybe_add_warning(
      is_binary(agent_contract_state.token_uri) and
        String.starts_with?(agent_contract_state.token_uri, "data:"),
      "The ERC-8004 registration currently lives in a data URI. Updating it may increase onchain URI size."
    )
    |> maybe_add_warning(
      resolver_support == :offchain_only,
      "The ENS resolver appears to be offchain-only. This planner will not build write transactions for it."
    )
    |> maybe_add_warning(
      resolver == nil and likely_subname?(normalized_name),
      "Only the exact name was checked. Wildcard or offchain subname resolution is not included in this plan."
    )
    |> maybe_add_warning(
      is_nil(agent_contract_state.registration),
      "The current ERC-8004 registration could not be loaded as a JSON registration file."
    )
    |> maybe_add_warning(
      not agent_contract_state.token_reads_supported?,
      "String agent IDs are accepted for ENS planning, but ERC-8004 token ownership and approval checks require a numeric token ID."
    )
  end

  defp maybe_add_warning(warnings, true, message), do: warnings ++ [message]
  defp maybe_add_warning(warnings, false, _message), do: warnings

  defp normalized_ens_service_endpoint(%{} = registration) do
    registration
    |> Map.get("services", [])
    |> Enum.find_value(fn
      %{"name" => name, "endpoint" => endpoint} when is_binary(name) and is_binary(endpoint) ->
        if String.downcase(name) == "ens", do: normalize_service_endpoint(endpoint), else: nil

      _ ->
        nil
    end)
  end

  defp normalized_ens_service_endpoint(_), do: nil

  defp normalize_service_endpoint(endpoint) do
    case Normalize.normalize(endpoint) do
      {:ok, normalized} -> normalized
      {:error, _} -> endpoint
    end
  end

  defp maybe_require_registration(nil), do: :registration_unavailable
  defp maybe_require_registration(_registration), do: :ready

  defp required_binary(params, key) do
    case Map.get(params, key) || Map.get(params, Atom.to_string(key)) do
      value when is_binary(value) and value != "" -> {:ok, value}
      value -> {:error, Error.new({:missing_required_input, "#{key}: #{inspect(value)}"})}
    end
  end

  defp required_integer(params, key) do
    case Map.get(params, key) || Map.get(params, Atom.to_string(key)) do
      value when is_integer(value) and value >= 0 ->
        {:ok, value}

      value when is_binary(value) and value != "" ->
        case Integer.parse(value) do
          {parsed, ""} when parsed >= 0 -> {:ok, parsed}
          _ -> {:error, Error.new({:invalid_argument, Atom.to_string(key), value})}
        end

      value ->
        {:error, Error.new({:missing_required_input, "#{key}: #{inspect(value)}"})}
    end
  end

  defp required_agent_id(params) do
    case Map.get(params, :agent_id) || Map.get(params, "agent_id") do
      value when is_integer(value) and value >= 0 ->
        {:ok, value}

      value when is_binary(value) and value != "" ->
        {:ok, value}

      value ->
        {:error, Error.new({:invalid_agent_id_type, value})}
    end
  end

  defp normalize_address(nil), do: nil
  defp normalize_address(value) when is_binary(value), do: String.downcase(String.trim(value))
  defp normalize_address(_), do: nil

  defp truthy?(value), do: value in [true, "true", "1", 1]

  defp likely_subname?(name) when is_binary(name) do
    name
    |> String.split(".", trim: true)
    |> length()
    |> Kernel.>(2)
  end
end

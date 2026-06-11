defmodule AgentEns.PrimaryName do
  @moduledoc """
  Verified ENS primary-name (reverse record) resolution on Ethereum mainnet.

  Looks up the reverse record for a wallet, then forward-resolves the claimed
  name and only returns it when the name resolves back to the same wallet.
  Wallets without a verified primary name yield `{:ok, nil}`.
  """

  alias AgentEns.Address
  alias AgentEns.Internal.Contract
  alias AgentEns.Internal.RPC
  alias AgentEns.Verify

  @ethereum_chain_id 1
  @default_ens_registry "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e"

  @doc """
  Resolves the verified primary name for `wallet_address`.

  Options:

    * `:rpc_url` — Ethereum mainnet JSON-RPC URL (required; a blank or
      missing value yields `{:ok, nil}`)
    * `:ens_registry` — ENS registry address (defaults to the canonical
      mainnet registry)
    * `:rpc_module` — RPC module used for `eth_call` (defaults to
      `AgentEns.Internal.RPC`)
  """
  @spec verified_primary_name(String.t() | nil, keyword()) ::
          {:ok, String.t() | nil} | {:error, term()}
  def verified_primary_name(wallet_address, opts \\ []) do
    rpc_url = Keyword.get(opts, :rpc_url)
    ens_registry = Keyword.get(opts, :ens_registry, @default_ens_registry)
    rpc_module = Keyword.get(opts, :rpc_module, RPC)

    with wallet when is_binary(wallet) <- Address.normalize(wallet_address),
         true <- is_binary(rpc_url) and rpc_url != "",
         {:ok, reverse_name} <- reverse_name(wallet, rpc_url, ens_registry, rpc_module),
         true <- reverse_name != "",
         {:ok, %{eth_address: ^wallet, normalized_name: normalized_name}} <-
           AgentEns.read_name(%{
             ens_name: reverse_name,
             chain_id: @ethereum_chain_id,
             rpc_url: rpc_url,
             rpc_module: rpc_module,
             include_contenthash?: false
           }) do
      {:ok, normalized_name}
    else
      nil -> {:ok, nil}
      false -> {:ok, nil}
      {:ok, %{eth_address: _other}} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
      _other -> {:ok, nil}
    end
  end

  defp reverse_name(wallet, rpc_url, ens_registry, rpc_module) do
    with {:ok, node} <- reverse_node(wallet),
         {:ok, resolver} <- Contract.fetch_resolver(rpc_module, rpc_url, ens_registry, node),
         {:ok, name} <- Contract.fetch_name_record(rpc_module, rpc_url, resolver, node) do
      {:ok, String.trim(name)}
    end
  end

  defp reverse_node("0x" <> address), do: Verify.namehash("#{address}.addr.reverse")
end

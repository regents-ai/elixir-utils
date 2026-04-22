defmodule AgentWorld.Networks do
  @moduledoc false

  alias AgentWorld.Error

  @world_contract "0xA23aB2712eA7BBa896930544C7d6636a96b944dA"
  @base_contract "0xE1D1D3526A6FAa37eb36bD10B933C1b77f4561a4"

  @defaults %{
    "world" => %{
      id: "world",
      chain_id: 480,
      contract_address: @world_contract,
      relay_url: "https://x402-worldchain.vercel.app"
    },
    "base" => %{
      id: "base",
      chain_id: 8_453,
      contract_address: @base_contract,
      relay_url: nil
    },
    "base-sepolia" => %{
      id: "base-sepolia",
      chain_id: 84_532,
      contract_address: @world_contract,
      relay_url: nil
    }
  }

  @spec resolve(String.t(), map() | keyword()) :: {:ok, map()} | {:error, Error.t()}
  def resolve(network, opts \\ %{}) when is_binary(network) do
    overrides = opt_map(opts, :networks) || Application.get_env(:agent_world, :networks, %{})

    case Map.get(@defaults, network) do
      nil ->
        {:error, Error.new({:invalid_network, network})}

      defaults ->
        merged =
          overrides
          |> network_entry(network)
          |> normalize_keys()
          |> then(&Map.merge(defaults, &1))
          |> Map.put(:id, network)

        {:ok, merged}
    end
  end

  @spec world_id_config(map() | keyword()) :: {:ok, map()} | {:error, Error.t()}
  def world_id_config(opts \\ %{}) do
    config =
      opt_map(opts, :world_id) ||
        Application.get_env(:agent_world, :world_id, [])
        |> Enum.into(%{})
        |> normalize_keys()

    with {:ok, app_id} <- required_binary(config, :app_id),
         {:ok, action} <- required_binary(config, :action),
         {:ok, rp_id} <- required_binary(config, :rp_id),
         {:ok, signing_key} <- required_binary(config, :signing_key) do
      ttl_seconds =
        case Map.get(config, :ttl_seconds, 300) do
          value when is_integer(value) and value > 0 -> value
          _ -> 300
        end

      {:ok,
       %{
         app_id: app_id,
         action: action,
         rp_id: rp_id,
         signing_key: signing_key,
         ttl_seconds: ttl_seconds
       }}
    end
  end

  defp required_binary(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, Error.new({:missing_world_id_config, key})}
    end
  end

  defp opt_map(opts, key) when is_list(opts),
    do: opts |> Keyword.get(key) |> normalize_opt_value()

  defp opt_map(opts, key) when is_map(opts) do
    key
    |> map_lookup(opts)
    |> normalize_opt_value()
  end

  defp opt_map(_opts, _key), do: nil

  defp normalize_opt_value(nil), do: nil
  defp normalize_opt_value(value) when is_map(value), do: normalize_keys(value)

  defp normalize_opt_value(value) when is_list(value),
    do: Enum.into(value, %{}) |> normalize_keys()

  defp normalize_opt_value(_value), do: nil

  defp normalize_keys(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {string_key_to_atom(key), deep_normalize(value)}
      {key, value} -> {key, deep_normalize(value)}
    end)
  end

  defp deep_normalize(value) when is_map(value), do: normalize_keys(value)
  defp deep_normalize(value) when is_list(value), do: Enum.map(value, &deep_normalize/1)
  defp deep_normalize(value), do: value

  defp network_entry(overrides, network) do
    Map.get(overrides, network) || Map.get(overrides, maybe_network_atom(network)) || %{}
  end

  defp maybe_network_atom(network) do
    String.to_existing_atom(network)
  rescue
    ArgumentError -> network
  end

  defp map_lookup(key, opts) when is_atom(key) do
    Map.get(opts, key) || Map.get(opts, Atom.to_string(key))
  end

  defp string_key_to_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> String.to_atom(key)
  end
end

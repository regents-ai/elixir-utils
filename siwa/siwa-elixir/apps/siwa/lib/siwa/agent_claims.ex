defmodule Siwa.AgentClaims do
  @moduledoc """
  Canonical normalization for SIWA agent identity claims.

  The canonical claims map carries five string keys:

    * `"wallet_address"` — trimmed, lowercase `0x` hex address
    * `"chain_id"` — positive integer string without leading zeros
    * `"registry_address"` — trimmed, lowercase `0x` hex address
    * `"token_id"` — positive integer string without leading zeros
    * `"label"` — trimmed non-empty string or `nil`

  `from_headers/2` builds the map from `x-agent-*` request headers and
  `from_claims/2` builds it from an `agent_claims` map returned by the shared
  SIWA broker. Errors are deny-metadata maps with `:reason`, `:source`, and
  either `:missing_headers` or `:invalid_header` detail, ready for app
  telemetry.
  """

  @required_fields ~w(wallet_address chain_id registry_address token_id)
  @hex_address_regex ~r/^0x[0-9a-fA-F]{40}$/
  @positive_int_regex ~r/^[1-9][0-9]*$/

  @type claims :: %{String.t() => String.t() | nil}
  @type deny_meta :: %{
          required(:reason) => atom(),
          required(:source) => atom(),
          optional(atom()) => term()
        }

  @doc """
  Builds canonical claims from downcased request headers.

  All four required `x-agent-*` headers must be present and non-blank; the
  optional `x-agent-label` header populates `"label"`.
  """
  @spec from_headers(map(), atom()) :: {:ok, claims()} | {:error, deny_meta()}
  def from_headers(headers, source \\ :request_headers) when is_map(headers) do
    with {:ok, values} <- fetch_required_headers(headers, source) do
      validate_and_build(values, optional_value(headers["x-agent-label"]), &header_key/1, source)
    end
  end

  @doc """
  Builds canonical claims from a broker `agent_claims` map.

  Values may be binaries or integers; integers are stringified. The optional
  `"label"` claim populates `"label"`.
  """
  @spec from_claims(term(), atom()) :: {:ok, claims()} | {:error, deny_meta()}
  def from_claims(claims, source \\ :siwa_claims)

  def from_claims(claims, source) when is_map(claims) do
    with {:ok, values} <- fetch_required_claims(claims, source) do
      validate_and_build(values, optional_value(claims["label"]), &Function.identity/1, source)
    end
  end

  def from_claims(_claims, source),
    do:
      {:error,
       %{reason: :missing_agent_headers, source: source, missing_headers: @required_fields}}

  defp fetch_required_headers(headers, source) do
    missing =
      Enum.filter(@required_fields, fn field ->
        case Map.get(headers, header_key(field)) do
          value when is_binary(value) -> String.trim(value) == ""
          _ -> true
        end
      end)

    if missing == [] do
      values =
        Map.new(@required_fields, fn field ->
          {field, headers |> Map.fetch!(header_key(field)) |> String.trim()}
        end)

      {:ok, values}
    else
      {:error,
       %{
         reason: :missing_agent_headers,
         source: source,
         missing_headers: Enum.map(missing, &header_key/1)
       }}
    end
  end

  defp fetch_required_claims(claims, source) do
    Enum.reduce_while(@required_fields, {:ok, %{}}, fn field, {:ok, values} ->
      case required_value(claims[field]) do
        {:ok, value} ->
          {:cont, {:ok, Map.put(values, field, value)}}

        :error ->
          {:halt,
           {:error, %{reason: :missing_agent_headers, source: source, missing_headers: [field]}}}
      end
    end)
  end

  defp validate_and_build(values, label, key_fun, source) do
    with {:ok, wallet} <-
           validate_hex_address(values["wallet_address"], key_fun.("wallet_address"), source),
         {:ok, chain_id} <-
           validate_positive_int(values["chain_id"], key_fun.("chain_id"), source),
         {:ok, registry} <-
           validate_hex_address(values["registry_address"], key_fun.("registry_address"), source),
         {:ok, token_id} <-
           validate_positive_int(values["token_id"], key_fun.("token_id"), source) do
      {:ok,
       %{
         "wallet_address" => wallet,
         "chain_id" => chain_id,
         "registry_address" => registry,
         "token_id" => token_id,
         "label" => label
       }}
    end
  end

  defp validate_hex_address(value, key, source) do
    if value =~ @hex_address_regex do
      {:ok, String.downcase(value)}
    else
      {:error, %{reason: :invalid_agent_header, source: source, invalid_header: key}}
    end
  end

  defp validate_positive_int(value, key, source) do
    if value =~ @positive_int_regex do
      {:ok, value}
    else
      {:error, %{reason: :invalid_agent_header, source: source, invalid_header: key}}
    end
  end

  defp required_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> :error
      trimmed -> {:ok, trimmed}
    end
  end

  defp required_value(value) when is_integer(value), do: {:ok, Integer.to_string(value)}
  defp required_value(_value), do: :error

  defp optional_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp optional_value(_value), do: nil

  defp header_key(field), do: "x-agent-" <> String.replace(field, "_", "-")
end

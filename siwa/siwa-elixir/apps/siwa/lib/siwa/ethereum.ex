defmodule Siwa.Ethereum do
  @moduledoc """
  Ethereum helpers used by SIWA flows.
  """

  @address_regex ~r/^0x[a-fA-F0-9]{40}$/
  @tx_hash_regex ~r/^0x[a-fA-F0-9]{64}$/
  @default_rpc_timeout_ms 5_000

  @type address :: String.t()
  @type hex_data :: String.t()
  @type error ::
          :invalid_address
          | :invalid_ens_name
          | :invalid_payload
          | :rpc_url_required
          | :rpc_request_failed
          | :rpc_request_timed_out
          | :invalid_rpc_response
          | {:rpc_error, String.t()}

  @spec normalize_address(term()) :: {:ok, address()} | {:error, :invalid_address}
  def normalize_address(value) when is_binary(value) do
    trimmed = String.trim(value)

    if Regex.match?(@address_regex, trimmed) do
      {:ok, String.downcase(trimmed)}
    else
      {:error, :invalid_address}
    end
  end

  def normalize_address(_value), do: {:error, :invalid_address}

  @spec valid_address?(term()) :: boolean()
  def valid_address?(value), do: match?({:ok, _address}, normalize_address(value))

  @spec valid_tx_hash?(term()) :: boolean()
  def valid_tx_hash?(value) when is_binary(value),
    do: Regex.match?(@tx_hash_regex, String.trim(value))

  def valid_tx_hash?(_value), do: false

  @spec keccak_hex(binary()) :: {:ok, hex_data()} | {:error, :invalid_payload}
  def keccak_hex(payload) when is_binary(payload) do
    {:ok, payload |> ExKeccak.hash_256() |> encode_hex()}
  end

  def keccak_hex(_payload), do: {:error, :invalid_payload}

  @spec namehash(binary()) :: {:ok, hex_data()} | {:error, :invalid_ens_name}
  def namehash(name) do
    with {:ok, labels} <- namehash_labels(name) do
      labels
      |> Enum.reverse()
      |> Enum.reduce(<<0::256>>, fn label, node ->
        ExKeccak.hash_256(node <> ExKeccak.hash_256(String.downcase(label)))
      end)
      |> encode_hex()
      |> then(&{:ok, &1})
    end
  end

  @spec json_rpc(binary(), binary(), list(), keyword()) :: {:ok, term()} | {:error, error()}
  def json_rpc(url, method, params, opts \\ [])

  def json_rpc(url, method, params, opts)
      when is_binary(url) and is_binary(method) and is_list(params) do
    opts =
      Keyword.put_new(opts, :timeout_ms, @default_rpc_timeout_ms)

    Siwa.RPCClient.call(url, method, params, opts)
  end

  def json_rpc(_url, _method, _params, _opts), do: {:error, :rpc_request_failed}

  defp namehash_labels(name) when is_binary(name) do
    case String.trim(name) do
      "" ->
        {:ok, []}

      trimmed ->
        labels = String.split(trimmed, ".")

        if Enum.any?(labels, &(&1 == "")) do
          {:error, :invalid_ens_name}
        else
          {:ok, labels}
        end
    end
  end

  defp namehash_labels(_name), do: {:error, :invalid_ens_name}

  defp encode_hex(bytes), do: "0x" <> Base.encode16(bytes, case: :lower)
end

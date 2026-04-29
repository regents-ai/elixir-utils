defmodule Siwa.Ethereum do
  @moduledoc """
  Ethereum helpers used by SIWA flows.
  """

  @address_regex ~r/^0x[a-fA-F0-9]{40}$/
  @tx_hash_regex ~r/^0x[a-fA-F0-9]{64}$/
  @non_negative_int_string_regex ~r/^(0|[1-9][0-9]*)$/
  @owner_of_selector "6352211e"
  @default_rpc_timeout_ms 5_000

  @type address :: String.t()
  @type hex_data :: String.t()
  @type error ::
          :invalid_address
          | :invalid_ens_name
          | :invalid_payload
          | :invalid_token_id
          | :token_id_too_large
          | :rpc_url_required
          | :rpc_request_failed
          | :rpc_request_timed_out
          | :invalid_rpc_response
          | :invalid_owner
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
    {:ok, payload |> KeccakEx.hash_256() |> encode_hex()}
  end

  def keccak_hex(_payload), do: {:error, :invalid_payload}

  @spec namehash(binary()) :: {:ok, hex_data()} | {:error, :invalid_ens_name}
  def namehash(name) do
    with {:ok, labels} <- namehash_labels(name) do
      labels
      |> Enum.reverse()
      |> Enum.reduce(<<0::256>>, fn label, node ->
        KeccakEx.hash_256(node <> KeccakEx.hash_256(String.downcase(label)))
      end)
      |> encode_hex()
      |> then(&{:ok, &1})
    end
  end

  @spec owner_of(binary(), binary(), binary(), keyword()) :: {:ok, address()} | {:error, error()}
  def owner_of(registry_address, token_id, rpc_url, opts \\ []) do
    with {:ok, registry_address} <- normalize_address(registry_address),
         {:ok, token_id} <- normalize_token_id(token_id),
         {:ok, rpc_url} <- normalize_rpc_url(rpc_url),
         {:ok, call_data} <- owner_of_call_data(token_id),
         {:ok, result} <-
           json_rpc(
             rpc_url,
             "eth_call",
             [%{to: registry_address, data: call_data}, "latest"],
             opts
           ),
         {:ok, owner_address} <- decode_owner_of_result(result) do
      {:ok, owner_address}
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

  @spec owner_of_call_data(binary()) ::
          {:ok, hex_data()} | {:error, :invalid_token_id | :token_id_too_large}
  def owner_of_call_data(token_id) do
    with {:ok, token_id} <- normalize_token_id(token_id),
         {:ok, token_hex} <- uint256_hex(token_id) do
      {:ok, "0x" <> @owner_of_selector <> token_hex}
    end
  end

  @spec decode_owner_of_result(term()) :: {:ok, address()} | {:error, :invalid_owner}
  def decode_owner_of_result("0x" <> hex) when byte_size(hex) >= 64 do
    hex
    |> String.slice(-40, 40)
    |> then(&("0x" <> &1))
    |> normalize_address()
    |> case do
      {:ok, owner} -> {:ok, owner}
      {:error, _reason} -> {:error, :invalid_owner}
    end
  end

  def decode_owner_of_result(_result), do: {:error, :invalid_owner}

  @spec normalize_token_id(term()) :: {:ok, String.t()} | {:error, :invalid_token_id}
  def normalize_token_id(value) when is_binary(value) do
    value = String.trim(value)

    if Regex.match?(@non_negative_int_string_regex, value) do
      {:ok, value}
    else
      {:error, :invalid_token_id}
    end
  end

  def normalize_token_id(_value), do: {:error, :invalid_token_id}

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

  defp normalize_rpc_url(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, :rpc_url_required}
      trimmed -> {:ok, trimmed}
    end
  end

  defp normalize_rpc_url(_value), do: {:error, :rpc_url_required}

  defp uint256_hex(token_id) do
    token_id
    |> String.to_integer()
    |> Integer.to_string(16)
    |> String.downcase()
    |> case do
      hex when byte_size(hex) <= 64 -> {:ok, String.pad_leading(hex, 64, "0")}
      _hex -> {:error, :token_id_too_large}
    end
  end

  defp encode_hex(bytes), do: "0x" <> Base.encode16(bytes, case: :lower)
end

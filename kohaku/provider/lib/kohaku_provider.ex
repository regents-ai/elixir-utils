defmodule KohakuProvider do
  @moduledoc """
  Ethereum JSON-RPC provider for Kohaku Elixir packages.
  """

  alias KohakuProvider.{Error, Receipt, TxData}

  @address_regex ~r/^0x[a-fA-F0-9]{40}$/
  @tx_hash_regex ~r/^0x[a-fA-F0-9]{64}$/

  @enforce_keys [:rpc_url]
  defstruct [:rpc_url, timeout_ms: 30_000]

  @type t :: %__MODULE__{
          rpc_url: String.t(),
          timeout_ms: pos_integer()
        }

  @spec new(String.t(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(rpc_url, opts \\ [])

  def new(rpc_url, opts) when is_binary(rpc_url) do
    case String.trim(rpc_url) do
      "" ->
        {:error, Error.invalid_argument("rpc url is required", %{})}

      trimmed ->
        {:ok, %__MODULE__{rpc_url: trimmed, timeout_ms: Keyword.get(opts, :timeout_ms, 30_000)}}
    end
  end

  def new(_rpc_url, _opts), do: {:error, Error.invalid_argument("rpc url is required", %{})}

  @spec request(t(), String.t(), list()) :: {:ok, term()} | {:error, Error.t()}
  def request(%__MODULE__{} = provider, method, params \\ [])
      when is_binary(method) and is_list(params) do
    body = %{
      "jsonrpc" => "2.0",
      "id" => System.unique_integer([:positive]),
      "method" => method,
      "params" => params
    }

    case Req.post(provider.rpc_url, json: body, receive_timeout: provider.timeout_ms) do
      {:ok, %{status: status, body: %{"error" => error}}} when status in 200..299 ->
        {:error, Error.rpc("rpc error", %{method: method, error: error})}

      {:ok, %{status: status, body: %{"result" => result}}} when status in 200..299 ->
        {:ok, result}

      {:ok, %{status: status, body: body}} ->
        {:error, Error.rpc("rpc request failed", %{method: method, status: status, body: body})}

      {:error, reason} ->
        {:error, Error.rpc("rpc request failed", %{method: method, reason: inspect(reason)})}
    end
  end

  @spec get_chain_id(t()) :: {:ok, non_neg_integer()} | {:error, Error.t()}
  def get_chain_id(provider) do
    with {:ok, value} <- request(provider, "eth_chainId", []) do
      quantity_to_integer(value)
    end
  end

  @spec get_block_number(t()) :: {:ok, non_neg_integer()} | {:error, Error.t()}
  def get_block_number(provider) do
    with {:ok, value} <- request(provider, "eth_blockNumber", []) do
      quantity_to_integer(value)
    end
  end

  @spec get_logs(t(), map()) :: {:ok, [map()]} | {:error, Error.t()}
  def get_logs(provider, filter) when is_map(filter) do
    request(provider, "eth_getLogs", [filter])
  end

  @spec call(t(), map()) :: {:ok, String.t()} | {:error, Error.t()}
  def call(provider, call_data) when is_map(call_data) do
    request(provider, "eth_call", [call_data, Map.get(call_data, :block, "latest")])
  end

  @spec estimate_gas(t(), map()) :: {:ok, non_neg_integer()} | {:error, Error.t()}
  def estimate_gas(provider, call_data) when is_map(call_data) do
    with {:ok, value} <- request(provider, "eth_estimateGas", [call_data]) do
      quantity_to_integer(value)
    end
  end

  @spec get_gas_price(t()) :: {:ok, non_neg_integer()} | {:error, Error.t()}
  def get_gas_price(provider) do
    with {:ok, value} <- request(provider, "eth_gasPrice", []) do
      quantity_to_integer(value)
    end
  end

  @spec get_transaction_count(t(), String.t(), non_neg_integer() | nil) ::
          {:ok, non_neg_integer()} | {:error, Error.t()}
  def get_transaction_count(provider, address, block \\ nil) do
    with {:ok, address} <- normalize_address(address),
         {:ok, value} <-
           request(provider, "eth_getTransactionCount", [address, block_param(block)]) do
      quantity_to_integer(value)
    end
  end

  @spec get_balance(t(), String.t()) :: {:ok, non_neg_integer()} | {:error, Error.t()}
  def get_balance(provider, address) do
    with {:ok, address} <- normalize_address(address),
         {:ok, value} <- request(provider, "eth_getBalance", [address, "latest"]) do
      quantity_to_integer(value)
    end
  end

  @spec get_code(t(), String.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def get_code(provider, address) do
    with {:ok, address} <- normalize_address(address) do
      request(provider, "eth_getCode", [address, "latest"])
    end
  end

  @spec get_transaction_receipt(t(), String.t()) :: {:ok, Receipt.t() | nil} | {:error, Error.t()}
  def get_transaction_receipt(provider, tx_hash) do
    with {:ok, tx_hash} <- normalize_tx_hash(tx_hash),
         {:ok, result} <- request(provider, "eth_getTransactionReceipt", [tx_hash]) do
      Receipt.from_rpc(result)
    end
  end

  @spec wait_for_transaction(t(), String.t(), keyword()) ::
          {:ok, Receipt.t()} | {:error, Error.t()}
  def wait_for_transaction(provider, tx_hash, opts \\ []) do
    attempts = Keyword.get(opts, :attempts, 60)
    delay_ms = Keyword.get(opts, :delay_ms, 1_000)
    wait_for_transaction(provider, tx_hash, attempts, delay_ms)
  end

  defp wait_for_transaction(_provider, _tx_hash, 0, _delay_ms) do
    {:error, Error.rpc("transaction receipt was not available in time", %{})}
  end

  defp wait_for_transaction(provider, tx_hash, attempts, delay_ms) do
    case get_transaction_receipt(provider, tx_hash) do
      {:ok, nil} ->
        Process.sleep(delay_ms)
        wait_for_transaction(provider, tx_hash, attempts - 1, delay_ms)

      {:ok, %Receipt{} = receipt} ->
        {:ok, receipt}

      {:error, error} ->
        {:error, error}
    end
  end

  @spec send_transaction(t(), TxData.t() | map()) :: {:ok, String.t()} | {:error, Error.t()}
  def send_transaction(provider, tx) do
    with {:ok, tx} <- TxData.from(tx) do
      request(provider, "eth_sendTransaction", [TxData.to_rpc(tx)])
    end
  end

  @spec anvil_set_balance(t(), String.t(), non_neg_integer()) :: :ok | {:error, Error.t()}
  def anvil_set_balance(provider, address, amount) do
    with {:ok, address} <- normalize_address(address),
         {:ok, _result} <-
           request(provider, "anvil_setBalance", [address, integer_to_quantity(amount)]) do
      :ok
    end
  end

  @spec normalize_address(term()) :: {:ok, String.t()} | {:error, Error.t()}
  def normalize_address(value) when is_binary(value) do
    trimmed = String.trim(value)

    if Regex.match?(@address_regex, trimmed) do
      {:ok, String.downcase(trimmed)}
    else
      {:error, Error.invalid_argument("invalid address", %{value: value})}
    end
  end

  def normalize_address(value),
    do: {:error, Error.invalid_argument("invalid address", %{value: inspect(value)})}

  @spec normalize_tx_hash(term()) :: {:ok, String.t()} | {:error, Error.t()}
  def normalize_tx_hash(value) when is_binary(value) do
    trimmed = String.trim(value)

    if Regex.match?(@tx_hash_regex, trimmed) do
      {:ok, String.downcase(trimmed)}
    else
      {:error, Error.invalid_argument("invalid transaction hash", %{value: value})}
    end
  end

  def normalize_tx_hash(value),
    do: {:error, Error.invalid_argument("invalid transaction hash", %{value: inspect(value)})}

  @spec quantity_to_integer(term()) :: {:ok, non_neg_integer()} | {:error, Error.t()}
  def quantity_to_integer("0x" <> hex) do
    case Integer.parse(hex, 16) do
      {value, ""} when value >= 0 -> {:ok, value}
      _error -> {:error, Error.rpc("invalid quantity", %{value: "0x" <> hex})}
    end
  end

  def quantity_to_integer(value) when is_integer(value) and value >= 0, do: {:ok, value}

  def quantity_to_integer(value),
    do: {:error, Error.rpc("invalid quantity", %{value: inspect(value)})}

  @spec integer_to_quantity(non_neg_integer()) :: String.t()
  def integer_to_quantity(value) when is_integer(value) and value >= 0 do
    "0x" <> Integer.to_string(value, 16)
  end

  defp block_param(nil), do: "latest"
  defp block_param(block) when is_integer(block) and block >= 0, do: integer_to_quantity(block)
end

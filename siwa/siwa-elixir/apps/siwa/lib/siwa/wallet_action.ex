defmodule Siwa.WalletAction do
  @allowed_chain_ids MapSet.new([8453, 84532])
  @required_keys ~w(chain_id to value data expected_signer expires_at risk_copy idempotency_key)
  @sorted_required_keys Enum.sort(@required_keys)

  @address_pattern ~r/^0x[a-fA-F0-9]{40}$/
  @hex_data_pattern ~r/^0x[a-fA-F0-9]*$/
  @idempotency_key_pattern ~r/^[A-Za-z0-9._:-]{16,128}$/

  def validate(action) when is_map(action) do
    with :ok <- validate_keys(action),
         :ok <- validate_chain_id(action["chain_id"]),
         :ok <- validate_address(action["to"]),
         :ok <- validate_hex_data(action["value"]),
         :ok <- validate_hex_data(action["data"]),
         :ok <- validate_address(action["expected_signer"]),
         :ok <- validate_future_datetime(action["expires_at"]),
         :ok <- validate_non_empty_text(action["risk_copy"]),
         :ok <- validate_idempotency_key(action["idempotency_key"]) do
      {:ok, action}
    else
      {:error, _reason} -> {:error, :invalid_wallet_action}
    end
  end

  def validate(_action), do: {:error, :invalid_wallet_action}

  def require_expected_signer(%{"expected_signer" => expected_signer}, signer_address)
      when is_binary(expected_signer) and is_binary(signer_address) do
    if String.downcase(expected_signer) == String.downcase(signer_address) do
      :ok
    else
      {:error, :unexpected_signer}
    end
  end

  def require_expected_signer(_action, _signer_address), do: {:error, :unexpected_signer}

  defp validate_keys(action) do
    keys = Map.keys(action)

    cond do
      Enum.any?(keys, &(not is_binary(&1))) ->
        {:error, :invalid_keys}

      Enum.sort(keys) != @sorted_required_keys ->
        {:error, :invalid_keys}

      true ->
        :ok
    end
  end

  defp validate_chain_id(chain_id) when is_integer(chain_id) do
    if MapSet.member?(@allowed_chain_ids, chain_id), do: :ok, else: {:error, :invalid_chain_id}
  end

  defp validate_chain_id(_chain_id), do: {:error, :invalid_chain_id}

  defp validate_address(address) when is_binary(address) do
    if Regex.match?(@address_pattern, address), do: :ok, else: {:error, :invalid_address}
  end

  defp validate_address(_address), do: {:error, :invalid_address}

  defp validate_hex_data(value) when is_binary(value) do
    if Regex.match?(@hex_data_pattern, value), do: :ok, else: {:error, :invalid_hex_data}
  end

  defp validate_hex_data(_value), do: {:error, :invalid_hex_data}

  defp validate_future_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} ->
        if DateTime.compare(datetime, DateTime.utc_now()) == :gt do
          :ok
        else
          {:error, :expired}
        end

      {:error, _reason} ->
        {:error, :invalid_expires_at}
    end
  end

  defp validate_future_datetime(_value), do: {:error, :invalid_expires_at}

  defp validate_non_empty_text(value) when is_binary(value) do
    if String.trim(value) == "", do: {:error, :empty_text}, else: :ok
  end

  defp validate_non_empty_text(_value), do: {:error, :empty_text}

  defp validate_idempotency_key(value) when is_binary(value) do
    if Regex.match?(@idempotency_key_pattern, value) do
      :ok
    else
      {:error, :invalid_idempotency_key}
    end
  end

  defp validate_idempotency_key(_value), do: {:error, :invalid_idempotency_key}
end

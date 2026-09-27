defmodule RegentChain.Event do
  @moduledoc """
  Reading one event back out of a receipt's logs.

  Emitter, `topic0`, the number of indexed words and the width of the data all
  have to be exact, and the event has to appear exactly once: absent and
  duplicated are both `:error`, while logs of other events are ignored. Words
  come back as integers; `address/1` reads one as an address.
  """

  alias RegentChain.Address

  @address_bound Integer.pow(2, 160)

  @doc "The `topic0` of an exact event signature: `Transfer(address,address,uint256)`."
  @spec topic0(String.t()) :: String.t()
  def topic0(signature), do: "0x" <> Base.encode16(ExKeccak.hash_256(signature), case: :lower)

  @doc """
  The indexed words and data words of the one log in `logs` that is `signature`
  emitted by `emitter`.
  """
  @spec one([map()], String.t(), String.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, {[non_neg_integer()], [non_neg_integer()]}} | :error
  def one(logs, signature, emitter, indexed_count, data_words) when is_list(logs) do
    topic = topic0(signature)

    case Enum.filter(logs, &emitted?(&1, topic, emitter)) do
      [log] -> words(log, indexed_count, data_words)
      _absent_or_duplicated -> :error
    end
  end

  def one(_logs, _signature, _emitter, _indexed_count, _data_words), do: :error

  @doc "The address a word names, which requires its leading twelve bytes to be zero."
  @spec address(non_neg_integer()) :: {:ok, String.t()} | :error
  def address(word) when is_integer(word) and word > 0 and word < @address_bound,
    do: {:ok, Address.encode(<<word::160>>)}

  def address(_word), do: :error

  defp emitted?(%{"address" => address, "topics" => [topic | _indexed]}, expected, emitter)
       when is_binary(topic),
       do: String.downcase(topic) == expected and Address.equal?(address, emitter)

  defp emitted?(_log, _expected, _emitter), do: false

  defp words(%{"topics" => [_topic | indexed], "data" => "0x" <> data}, count, width)
       when length(indexed) == count and byte_size(data) == width * 64 do
    with {:ok, indexed} <- decode_all(Enum.map(indexed, &strip/1)),
         {:ok, data} <- decode_all(for <<word::binary-size(64) <- data>>, do: word) do
      {:ok, {indexed, data}}
    end
  end

  defp words(_log, _count, _width), do: :error

  defp strip("0x" <> word) when byte_size(word) == 64, do: word
  defp strip(_topic), do: :malformed

  defp decode_all(words) do
    Enum.reduce_while(words, {:ok, []}, fn word, {:ok, decoded} ->
      case is_binary(word) && Base.decode16(word, case: :mixed) do
        {:ok, bytes} -> {:cont, {:ok, [:binary.decode_unsigned(bytes) | decoded]}}
        _malformed -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, decoded} -> {:ok, Enum.reverse(decoded)}
      :error -> :error
    end
  end
end

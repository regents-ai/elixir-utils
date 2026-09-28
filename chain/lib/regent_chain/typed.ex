defmodule RegentChain.Typed do
  @moduledoc """
  EIP-712 typed data on the server: the digest a wallet signs, and the wallet
  that signed it.

  Typed data is the map a `RegentChain.Review.signature/2` step keeps, as
  `eth_signTypedData_v4` takes it: `"types"` (including `"EIP712Domain"`),
  `"primaryType"`, `"domain"` and `"message"`. Integers are Elixir integers or
  decimal strings; addresses, `bytes` and `bytesN` are `0x` hex. Anything else is
  `:error`, never a digest of something other than what the wallet was shown.

  Check a signature against the server's own copy of what was signed, never the
  page's:

      {:ok, %{review: review, step: step, signature: signature}} = Presses.signed(presses, params)
      {:ok, signer} = RegentChain.Typed.signer(step.typed_data, signature)
      RegentChain.Address.equal?(signer, review.signer)
  """

  import Bitwise

  alias RegentChain.Address

  @array ~r/\A(.+)\[(\d*)\]\z/
  @decimal ~r/\A-?[0-9]+\z/

  @doc "The 32-byte digest a wallet signs for `typed_data`."
  @spec digest(map()) :: {:ok, <<_::256>>} | :error
  def digest(%{
        "types" => types,
        "primaryType" => primary,
        "domain" => domain,
        "message" => message
      })
      when is_binary(primary) do
    with true <- defined?(types),
         {:ok, domain_hash} <- hash_struct(types, "EIP712Domain", domain),
         {:ok, message_hash} <- hash_struct(types, primary, message) do
      {:ok, keccak(<<0x19, 0x01>> <> domain_hash <> message_hash)}
    else
      _undefined -> :error
    end
  end

  def digest(_typed_data), do: :error

  @doc """
  `signature` as contracts take it: 65 bytes of lowercase `0x` hex ending in 27
  or 28. Some wallets end a signature with 0 or 1 instead, which say the same.
  """
  @spec signature(term()) :: {:ok, String.t()} | :error
  def signature(signature) do
    with {:ok, bytes} <- bytes(signature), do: {:ok, "0x" <> Base.encode16(bytes, case: :lower)}
  end

  @doc "The lowercase address whose key made `signature` over `typed_data`."
  @spec signer(map(), term()) :: {:ok, String.t()} | :error
  def signer(typed_data, signature) do
    with {:ok, digest} <- digest(typed_data),
         {:ok, <<compact::binary-size(64), v>>} <- bytes(signature),
         {:ok, <<4, public_key::binary-size(64)>>} <-
           ExSecp256k1.recover_compact(digest, compact, v - 27) do
      {:ok, public_key |> keccak() |> binary_part(12, 20) |> Address.encode()}
    else
      _unrecovered -> :error
    end
  end

  defp bytes("0x" <> hex) when byte_size(hex) == 130 do
    case Base.decode16(hex, case: :mixed) do
      {:ok, <<rs::binary-size(64), v>>} when v in [0, 1] -> {:ok, rs <> <<v + 27>>}
      {:ok, <<_rs::binary-size(64), v>> = bytes} when v in [27, 28] -> {:ok, bytes}
      _other -> :error
    end
  end

  defp bytes(_signature), do: :error

  defp defined?(%{"EIP712Domain" => _domain} = types) do
    Enum.all?(types, fn {name, fields} ->
      is_binary(name) and is_list(fields) and Enum.all?(fields, &field?/1)
    end)
  end

  defp defined?(_types), do: false

  defp field?(%{"name" => name, "type" => type}), do: is_binary(name) and is_binary(type)
  defp field?(_field), do: false

  defp hash_struct(types, type, data) when is_map(data) do
    with {:ok, fields} <- Map.fetch(types, type),
         {:ok, words} <-
           collect(fields, fn %{"name" => name, "type" => field_type} ->
             with {:ok, value} <- Map.fetch(data, name), do: encode(types, field_type, value)
           end) do
      {:ok, keccak(IO.iodata_to_binary([keccak(encode_type(types, type)) | words]))}
    end
  end

  defp hash_struct(_types, _type, _data), do: :error

  # The type itself, then every struct type it reaches, sorted by name.
  defp encode_type(types, type) do
    reached = types |> reached(type, MapSet.new()) |> MapSet.delete(type) |> Enum.sort()

    Enum.map_join([type | reached], fn name ->
      name <> "(" <> Enum.map_join(types[name], ",", &(&1["type"] <> " " <> &1["name"])) <> ")"
    end)
  end

  defp reached(types, type, seen) do
    if MapSet.member?(seen, type) do
      seen
    else
      types[type]
      |> Enum.map(&String.replace(&1["type"], ~r/(\[\d*\])+\z/, ""))
      |> Enum.filter(&Map.has_key?(types, &1))
      |> Enum.reduce(MapSet.put(seen, type), &reached(types, &1, &2))
    end
  end

  defp encode(types, type, value) do
    case Regex.run(@array, type, capture: :all_but_first) do
      [item, size] -> array(types, item, size, value)
      nil when is_map_key(types, type) -> hash_struct(types, type, value)
      nil -> atomic(type, value)
    end
  end

  defp array(types, item, size, values) when is_list(values) do
    if size == "" or String.to_integer(size) == length(values) do
      with {:ok, words} <- collect(values, &encode(types, item, &1)),
           do: {:ok, keccak(IO.iodata_to_binary(words))}
    else
      :error
    end
  end

  defp array(_types, _item, _size, _values), do: :error

  defp atomic("string", value) when is_binary(value), do: {:ok, keccak(value)}
  defp atomic("bytes", value), do: with({:ok, bytes} <- hex(value), do: {:ok, keccak(bytes)})
  defp atomic("bool", true), do: {:ok, <<1::256>>}
  defp atomic("bool", false), do: {:ok, <<0::256>>}

  defp atomic("address", value),
    do: with({:ok, address} <- Address.argument(value), do: {:ok, <<0::96, address::binary>>})

  defp atomic("uint" <> bits, value) do
    with {:ok, bits} <- bits(bits),
         {:ok, integer} <- integer(value),
         true <- integer >= 0 and integer < 1 <<< bits do
      {:ok, <<integer::256>>}
    else
      _other -> :error
    end
  end

  defp atomic("int" <> bits, value) do
    with {:ok, bits} <- bits(bits),
         {:ok, integer} <- integer(value),
         true <- integer >= -(1 <<< (bits - 1)) and integer < 1 <<< (bits - 1) do
      {:ok, <<integer::signed-256>>}
    else
      _other -> :error
    end
  end

  defp atomic("bytes" <> size, value) do
    with {size, ""} when size in 1..32 <- Integer.parse(size),
         {:ok, bytes} when byte_size(bytes) == size <- hex(value) do
      {:ok, <<bytes::binary, 0::size((32 - size) * 8)>>}
    else
      _other -> :error
    end
  end

  defp atomic(_type, _value), do: :error

  defp bits(bits) do
    case Integer.parse(bits) do
      {bits, ""} when bits in 8..256//8 -> {:ok, bits}
      _other -> :error
    end
  end

  defp integer(value) when is_integer(value), do: {:ok, value}

  defp integer(value) when is_binary(value) do
    if Regex.match?(@decimal, value), do: {:ok, String.to_integer(value)}, else: :error
  end

  defp integer(_value), do: :error

  defp hex("0x" <> hex), do: Base.decode16(hex, case: :mixed)
  defp hex(_value), do: :error

  defp collect(items, fun) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, done} ->
      case fun.(item) do
        {:ok, value} -> {:cont, {:ok, [value | done]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, done} -> {:ok, Enum.reverse(done)}
      :error -> :error
    end
  end

  defp keccak(data), do: ExKeccak.hash_256(data)
end

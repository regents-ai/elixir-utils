defmodule Siwa.WalletSignature do
  @moduledoc """
  Whether the wallet at an address signed a personal message (ERC-191), for
  ordinary and smart wallets on Base.

  An ordinary wallet's signature is recovered here, with no network call. Any
  other signature is a smart wallet's, and Base is asked whether the wallet
  approves it: ERC-1271 `isValidSignature` on the wallet, read through
  Multicall3. A wallet not deployed yet wraps its signature with ERC-6492; its
  factory call runs first in the same read, so nothing is deployed, and is
  allowed to fail, so a wallet deployed since it signed still answers.

  Sign-in (siwa-server) and every signed request after it (`Siwa.RequestAuth`)
  check signatures here, so both accept and refuse the same ones.
  """

  alias Siwa.{EvmPersonalSign, RPCClient}

  # The largest signature either door takes. A Coinbase Smart Wallet signature
  # is 224 bytes deployed and 640 wrapped with ERC-6492; 4 KiB also keeps the
  # base64 signature header inside Bandit's 10,000-byte header limit.
  @max_bytes 4096
  @is_valid_signature binary_part(ExKeccak.hash_256("isValidSignature(bytes32,bytes)"), 0, 4)
  # ERC-1271: a contract wallet approves a signature by returning its selector.
  @erc1271_magic @is_valid_signature <> <<0::224>>
  @aggregate3 binary_part(ExKeccak.hash_256("aggregate3((address,bool,bytes)[])"), 0, 4)
  # ERC-6492: a wallet not deployed yet appends this to its wrapped signature.
  @erc6492_suffix :binary.copy(<<0x64, 0x92>>, 16)
  # Multicall3, at the same address on Base and every other chain.
  @multicall3 "0xca11bde05977b3631167028862be2a173976ca11"
  @address ~r/\A0x[0-9a-fA-F]{40}\z/

  @type error :: :signature_invalid | {:lookup_failed, term()}

  @doc "The largest signature, in bytes, that sign-in and signed requests take."
  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  @doc """
  `:ok` when the wallet at `address` signed `message`; `:signature_invalid`
  when it did not; `{:lookup_failed, reason}` when a smart wallet's answer
  could not be read from Base. `opts` says how to read Base, needed only for
  a smart wallet: `:rpc_url`, and optionally the `:finch` pool and
  `:timeout_ms` that `Siwa.RPCClient` takes.
  """
  @spec verify(String.t(), String.t(), String.t(), keyword()) :: :ok | {:error, error()}
  def verify(address, message, signature, opts \\ []) do
    with {:ok, wallet} <- wallet(address),
         true <- is_binary(message),
         {:ok, bytes} <- signature_bytes(signature) do
      check(wallet, EvmPersonalSign.personal_hash(message), bytes, opts)
    else
      _invalid -> {:error, :signature_invalid}
    end
  end

  defp wallet(address) when is_binary(address) do
    if Regex.match?(@address, address),
      do: Base.decode16(String.trim_leading(address, "0x"), case: :mixed),
      else: :error
  end

  defp wallet(_address), do: :error

  defp signature_bytes("0x" <> hex) when rem(byte_size(hex), 2) == 0 do
    case Base.decode16(hex, case: :mixed) do
      {:ok, bytes} when byte_size(bytes) in 1..@max_bytes -> {:ok, bytes}
      _invalid -> :error
    end
  end

  defp signature_bytes(_signature), do: :error

  defp check(wallet, digest, bytes, opts) do
    case erc6492_unwrap(bytes) do
      {:ok, deployment, inner} -> ask_wallet(wallet, digest, inner, [deployment], opts)
      :not_wrapped -> key_or_wallet(wallet, digest, bytes, opts)
      :error -> {:error, :signature_invalid}
    end
  end

  defp key_or_wallet(wallet, digest, bytes, opts) do
    case EvmPersonalSign.recover_address(digest, hex(bytes)) do
      {:ok, recovered} ->
        if String.downcase(recovered) == hex(wallet),
          do: :ok,
          else: ask_wallet(wallet, digest, bytes, [], opts)

      {:error, _reason} ->
        ask_wallet(wallet, digest, bytes, [], opts)
    end
  end

  # abi.encode(address factory, bytes factoryCalldata, bytes signature) ++ suffix.
  defp erc6492_unwrap(bytes) when byte_size(bytes) >= 32 do
    wrapped_size = byte_size(bytes) - 32

    case bytes do
      <<wrapped::binary-size(wrapped_size), @erc6492_suffix>> -> decode_wrapper(wrapped)
      _unwrapped -> :not_wrapped
    end
  end

  defp erc6492_unwrap(_bytes), do: :not_wrapped

  defp decode_wrapper(
         <<0::96, factory::binary-size(20), calldata_at::256, inner_at::256, _::binary>> = data
       ) do
    with {:ok, calldata} <- dynamic_bytes_at(data, calldata_at),
         {:ok, inner} <- dynamic_bytes_at(data, inner_at) do
      {:ok, {factory, calldata}, inner}
    end
  end

  defp decode_wrapper(_wrapped), do: :error

  defp dynamic_bytes_at(data, offset) do
    case data do
      <<_head::binary-size(offset), size::256, value::binary-size(size), _rest::binary>> ->
        {:ok, value}

      _malformed ->
        :error
    end
  end

  # One read through Multicall3: any deployment first, then the wallet's own
  # answer. Every call may fail, so a wallet that reverts is an answer, not an
  # error.
  defp ask_wallet(wallet, digest, signature, deployments, opts) do
    check = @is_valid_signature <> digest <> word(64) <> dynamic_bytes(signature)
    data = @aggregate3 <> aggregate3_arguments(deployments ++ [{wallet, check}])
    call = %{"to" => @multicall3, "data" => hex(data)}

    with {:ok, result} <-
           RPCClient.call(
             Keyword.get(opts, :rpc_url, ""),
             "eth_call",
             [call, "latest"],
             Keyword.take(opts, [:finch, :timeout_ms])
           ),
         {:ok, answer} <- wallet_answer(result) do
      if answer == {1, @erc1271_magic}, do: :ok, else: {:error, :signature_invalid}
    else
      {:error, reason} -> {:error, {:lookup_failed, reason}}
    end
  end

  # aggregate3((address target, bool allowFailure, bytes callData)[]), every
  # call allowed to fail.
  defp aggregate3_arguments(calls) do
    tuples =
      Enum.map(calls, fn {target, call_data} ->
        <<0::96>> <> target <> word(1) <> word(96) <> dynamic_bytes(call_data)
      end)

    {offsets, _end} =
      Enum.map_reduce(tuples, 32 * length(tuples), &{word(&2), &2 + byte_size(&1)})

    IO.iodata_to_binary([word(32), word(length(calls)), offsets, tuples])
  end

  # The last `(bool success, bytes returnData)` of Multicall3's result array:
  # the wallet's own answer, read in its one canonical encoding. Anything else
  # a provider sends is an unreadable answer, never a crash.
  defp wallet_answer("0x" <> hex) do
    with {:ok, <<32::256, count::256, rest::binary>>} when count > 0 <-
           Base.decode16(hex, case: :mixed),
         <<_heads::binary-size(32 * (count - 1)), offset::256, _tail::binary>> <- rest,
         <<_skipped::binary-size(offset), success::256, 64::256, size::256,
           answer::binary-size(size), _padding::binary>>
         when success in [0, 1] <- rest do
      {:ok, {success, answer}}
    else
      _malformed -> {:error, :invalid_rpc_response}
    end
  end

  defp wallet_answer(_result), do: {:error, :invalid_rpc_response}

  defp word(value), do: <<value::256>>

  defp dynamic_bytes(value) do
    padding = rem(32 - rem(byte_size(value), 32), 32)
    word(byte_size(value)) <> value <> <<0::size(padding * 8)>>
  end

  defp hex(bytes), do: "0x" <> Base.encode16(bytes, case: :lower)
end

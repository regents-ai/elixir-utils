defmodule Siwa.WalletSignatureTest do
  use ExUnit.Case, async: true

  alias Siwa.{EvmPersonalSign, LocalSigner, RpcStub, WalletSignature}

  # Coinbase Smart Wallet v1.1 signatures over @message, made with viem 2.55 and
  # checked live: the undeployed wallet's ERC-6492 signature against Base, the
  # deployed wallet's ERC-1271 signature against a local copy of Base with the
  # wallet created.
  @message "regent smart wallet sign-in test"
  @undeployed_wallet "0x06D30a8DA60dDd004A93db4C1b3360c9068e64C1"
  @undeployed_factory "ba5ed110efdba3d005bfc882d75358acbbb85842"
  @deployed_wallet "0x452f678f6e588069D1Aef38D3D519567aA1014A4"
  @multicall3 "0xca11bde05977b3631167028862be2a173976ca11"
  @undeployed_signature "0x000000000000000000000000ba5ed110efdba3d005bfc882d75358acbbb858420000000000000000000000" <>
                          "0000000000000000000000000000000000000000600000000000000000000000000000000000000000000000" <>
                          "00000000000000016000000000000000000000000000000000000000000000000000000000000000c43ffba3" <>
                          "6f00000000000000000000000000000000000000000000000000000000000000400000000000000000000000" <>
                          "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" <>
                          "0000000000000000010000000000000000000000000000000000000000000000000000000000000020000000" <>
                          "0000000000000000000000000000000000000000000000000000000020000000000000000000000000429A71" <>
                          "fE1C17F890c3545F4ad05e4559c5489faA000000000000000000000000000000000000000000000000000000" <>
                          "0000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000" <>
                          "0000000000000000000000000000000000000000200000000000000000000000000000000000000000000000" <>
                          "0000000000000000000000000000000000000000000000000000000000000000000000000000000040000000" <>
                          "00000000000000000000000000000000000000000000000000000000413638a953c53d446d4e108db1958e17" <>
                          "5a12f57180e105075683ad89bf66bdf8c0109405fee4a49234c2b298b8b12eeed15931b24a5d83d507a041ac" <>
                          "3943f5e3fa1c0000000000000000000000000000000000000000000000000000000000000064926492649264" <>
                          "92649264926492649264926492649264926492649264926492"
  @deployed_signature "0x00000000000000000000000000000000000000000000000000000000000000200000000000000000000000" <>
                        "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" <>
                        "0000000000000000400000000000000000000000000000000000000000000000000000000000000041ca4d8a" <>
                        "90ca0affff9dfc4cb485e0b7a5d144ca28874beed10aa5d75f92d859f81aadc758ca6138c9fabfd20bb107a9" <>
                        "610d3cbab9ce85e8690011d28ec5894da31b0000000000000000000000000000000000000000000000000000" <>
                        "0000000000"

  test "an ordinary wallet's signature is checked here, without Base" do
    {:ok, signer} = LocalSigner.new()
    {:ok, signature} = EvmPersonalSign.sign_personal_signature(signer.private_key, @message)

    assert WalletSignature.verify(signer.address, @message, signature) == {:ok, :eoa_recovery}
  end

  test "a deployed wallet's signature is its own answer on Base" do
    base = RpcStub.start(RpcStub.wallet_answers({true, RpcStub.erc1271_approval()}), self())

    assert WalletSignature.verify(@deployed_wallet, @message, @deployed_signature, rpc_url: base) ==
             {:ok, :erc1271}

    assert_received {:rpc_request, %{"method" => "eth_call", "params" => [call, "latest"]}}
    assert call["to"] == @multicall3
    assert [{wallet, check}] = aggregate3_calls(call["data"])
    assert wallet == String.downcase(String.trim_leading(@deployed_wallet, "0x"))
    digest = EvmPersonalSign.personal_hash(@message)
    signature = decode(@deployed_signature)

    assert <<0x1626BA7E::32, ^digest::binary-size(32), 64::256, size::256, rest::binary>> = check
    assert binary_part(rest, 0, size) == signature
  end

  test "an undeployed wallet's factory call runs before its answer, in one read" do
    base = RpcStub.start(RpcStub.wallet_answers({true, RpcStub.erc1271_approval()}), self())

    assert WalletSignature.verify(@undeployed_wallet, @message, @undeployed_signature,
             rpc_url: base
           ) == {:ok, :erc6492}

    assert_received {:rpc_request, %{"params" => [call, "latest"]}}
    assert [{@undeployed_factory, _deploy}, {wallet, check}] = aggregate3_calls(call["data"])
    assert wallet == String.downcase(String.trim_leading(@undeployed_wallet, "0x"))
    assert <<0x1626BA7E::32, _arguments::binary>> = check
  end

  test "any other answer from the wallet refuses the signature" do
    for answer <- [
          {false, RpcStub.erc1271_approval()},
          {true, <<0xFFFFFFFF::32, 0::224>>},
          {true, <<>>}
        ] do
      base = RpcStub.start(RpcStub.wallet_answers(answer))

      assert WalletSignature.verify(@deployed_wallet, @message, @deployed_signature,
               rpc_url: base
             ) == {:error, :signature_invalid}
    end
  end

  test "a broken ERC-6492 wrapper, an oversized signature or a bad address is refused without Base" do
    suffix = String.duplicate("6492", 16)
    oversized = "0x" <> String.duplicate("00", WalletSignature.max_bytes() + 1)

    for {address, signature} <- [
          {@undeployed_wallet, "0x" <> suffix},
          {@undeployed_wallet, "0x1234" <> suffix},
          {@deployed_wallet, oversized},
          {@deployed_wallet, "0x"},
          {"not-an-address", @deployed_signature}
        ] do
      assert WalletSignature.verify(address, @message, signature) == {:error, :signature_invalid}
    end
  end

  test "Base unreachable, erroring or answering garbage is a failed lookup, never a crash" do
    garbage = [
      RpcStub.rpc_result("0x"),
      RpcStub.rpc_result("0x" <> String.duplicate("f", 64)),
      RpcStub.rpc_result("0x" <> String.duplicate("0", 62) <> "20" <> String.duplicate("f", 64)),
      RpcStub.rpc_result(42),
      %{"jsonrpc" => "2.0", "id" => 1, "error" => %{"code" => -32_000, "message" => "down"}}
    ]

    for body <- garbage do
      assert {:error, {:lookup_failed, _reason}} =
               WalletSignature.verify(@deployed_wallet, @message, @deployed_signature,
                 rpc_url: RpcStub.start(body)
               )
    end

    assert WalletSignature.verify(@deployed_wallet, @message, @deployed_signature) ==
             {:error, {:lookup_failed, :rpc_url_required}}
  end

  test "Base is read through the given pool and gives up at the given timeout" do
    pool = :"wallet_signature_test_#{System.unique_integer([:positive])}"
    start_supervised!({Finch, name: pool})
    base = RpcStub.start(RpcStub.wallet_answers({true, RpcStub.erc1271_approval()}))

    assert WalletSignature.verify(@deployed_wallet, @message, @deployed_signature,
             rpc_url: base,
             finch: pool
           ) == {:ok, :erc1271}

    # Takes the connection and never answers.
    {:ok, silent} = :gen_tcp.listen(0, [:binary, active: false])
    on_exit(fn -> :gen_tcp.close(silent) end)
    {:ok, port} = :inet.port(silent)

    assert WalletSignature.verify(@deployed_wallet, @message, @deployed_signature,
             rpc_url: "http://127.0.0.1:#{port}",
             timeout_ms: 50
           ) == {:error, {:lookup_failed, :rpc_request_timed_out}}
  end

  defp aggregate3_calls("0x" <> hex) do
    <<0x82AD56CB::32, 32::256, count::256, rest::binary>> = decode("0x" <> hex)

    for index <- 0..(count - 1) do
      <<_::binary-size(32 * index), at::256, _::binary>> = rest

      <<_::binary-size(at), 0::96, target::binary-size(20), 1::256, 96::256, size::256,
        data::binary-size(size), _::binary>> = rest

      {Base.encode16(target, case: :lower), data}
    end
  end

  defp decode("0x" <> hex), do: Base.decode16!(hex, case: :mixed)
end

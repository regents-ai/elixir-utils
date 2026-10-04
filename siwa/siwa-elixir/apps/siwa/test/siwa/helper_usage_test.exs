defmodule Siwa.HelperUsageTest do
  use ExUnit.Case, async: false

  test "client resolver returns usable local signers" do
    assert {:ok, signer} = Siwa.ClientResolver.resolve_signer(%{provider: :local})
    assert {:ok, signed} = Siwa.LocalSigner.sign_message(signer, "hello")
    assert is_binary(signed)
    assert String.starts_with?(signed, "0x")
  end

  test "x402 memory session store can remember a paid session" do
    store = Siwa.X402.create_memory_session_store()
    assert {:ok, nil} = store.get.("0xabc", "/weather")
    assert :ok = store.set.("0xabc", "/weather", %{paid_at: 123, tx_hash: "0xtx"}, 5_000)
    assert {:ok, session} = store.get.("0xabc", "/weather")
    assert session == %{paid_at: 123, tx_hash: "0xtx"}
  end
end

defmodule RegentCredits.Fixtures do
  @moduledoc "Credits for tests, moved straight from the Regent accounts."

  alias RegentCredits.{Actor, Ledger, TestChain}

  def person, do: "did:privy:" <> Ecto.UUID.generate()
  def key, do: "key-" <> Ecto.UUID.generate()
  def site, do: Actor.site("patchbay")
  def actor(privy_user_id), do: Actor.person(privy_user_id, "patchbay")
  def d(value), do: Decimal.new(value)
  def wallet, do: "0x" <> Base.encode16(:crypto.strong_rand_bytes(20), case: :lower)
  def admin, do: Actor.admin("did:privy:admin")

  @doc "A purchase of `dollars` the person's `wallet` sent on `chain`, reported and not yet checked."
  def report(owner, wallet, chain, dollars) do
    number = Ecto.UUID.generate()
    hash = TestChain.hash()
    TestChain.put(hash, TestChain.buy(chain, wallet, dollars, number), nil)

    {:ok, purchase} =
      RegentCredits.report_purchase(owner, wallet, chain, dollars, number, hash,
        actor: actor(owner)
      )

    purchase
  end

  @doc "A Base purchase that landed and was credited."
  def bought(owner, wallet, dollars) do
    purchase = report(owner, wallet, :base, dollars)

    TestChain.put(
      purchase.tx_hash,
      TestChain.buy(:base, wallet, dollars, purchase.number),
      TestChain.mined("0x1")
    )

    {:ok, purchase} = RegentCredits.check_purchase(purchase.id)
    purchase
  end

  def fund(privy_user_id, given, purchased) do
    Ledger.open(Ledger.person(privy_user_id))
    given_to = Ledger.identifier(:given, privy_user_id)
    purchased_to = Ledger.identifier(:purchased, privy_user_id)

    RegentCredits.TestRepo.transaction(fn ->
      ["regent_gifts", "regent_purchases", given_to, purchased_to]
      |> Ledger.lock()
      |> Ledger.move({"regent_gifts", given_to}, d(given), "test")
      |> Ledger.move({"regent_purchases", purchased_to}, d(purchased), "test")
    end)

    privy_user_id
  end
end

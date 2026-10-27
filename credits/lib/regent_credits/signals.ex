defmodule RegentCredits.Signals do
  @moduledoc """
  What Credits tells the site about purchases, as Ash signals. A site listens
  with `signals_in` on one of its own resources; Credits never names the site.

  Each is emitted inside the credit's own transaction, after the purchase is
  saved. A listener with the default delivery runs in that transaction, so the
  work it queues commits or rolls back with the credit, and a listener that
  fails rolls the credit back.

    * `:purchase_credited`: a USDC purchase was credited to `privy_user_id`.
    * `:purchase_attributed`: a payment already credited while waiting under
      its wallet, because no account held the wallet yet, now belongs to
      `privy_user_id`, the account that signed in with that wallet.
    * `:card_purchase_credited`: a purchase by card or Link
      (`RegentCredits.CardPurchase`) was credited to `privy_user_id`.

  A USDC purchase is credited to one account once, through one of the first
  two, and a card purchase once, through the third: `purchase_id` names it, and
  a listener that counts purchases keys on it.
  """

  use Ash.Signals

  signals do
    signal :purchase_credited do
      argument :purchase_id, :uuid, allow_nil?: false
      argument :privy_user_id, :string, allow_nil?: false
    end

    signal :purchase_attributed do
      argument :purchase_id, :uuid, allow_nil?: false
      argument :privy_user_id, :string, allow_nil?: false
    end

    signal :card_purchase_credited do
      argument :purchase_id, :uuid, allow_nil?: false
      argument :privy_user_id, :string, allow_nil?: false
    end
  end
end

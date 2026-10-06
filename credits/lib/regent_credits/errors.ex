defmodule RegentCredits.Errors.NotEnoughCredits do
  @moduledoc "The person's available Credits fall short of the amount by `shortfall`."
  use Splode.Error, fields: [:shortfall], class: :invalid

  def message(%{shortfall: shortfall}),
    do: "Not enough Credits: #{RegentCredits.Amount.format(shortfall)} short."
end

defmodule RegentCredits.Errors.Refused do
  @moduledoc """
  An operation the library will not carry out, with the reason:

    * `:invalid_amount`: not a positive amount to the millionth of a Credit.
    * `:key_reused`: the key already names an operation with other details.
    * `:closed`: the hold was already closed another way.
    * `:not_found`: no hold has this key on this site.
    * `:agent_off`, `:agent_site`, `:agent_max_per_spend`, `:agent_daily_limit`:
      the person's settings for this agent do not allow the spend.
    * `:split_mismatch`: returned, used and forfeited do not add up to the hold.
    * `:invalid_purchase`: the reported wallet or transaction hash is not one.
    * `:invalid_recipient`: a gift's recipient or a wallet is neither a Privy
      account id nor an address.
    * `:not_credited`: the purchase has not been credited, so there is nothing
      to refund.
    * `:used`: the account has used Credits, so its purchases are not refunded.
    * `:refund_not_proven`: the transaction is not the Treasury Safe's
      successful transfer of exactly the refund to the wallet that paid.
  """
  use Splode.Error, fields: [:reason], class: :invalid

  def message(%{reason: reason}), do: "Credits operation refused: #{reason}"
end

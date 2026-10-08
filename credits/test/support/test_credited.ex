defmodule RegentCredits.TestCredited do
  @moduledoc "A stand-in for the site's credited notice: tells the crediting process."
  @behaviour RegentCredits.Credited

  @impl true
  def credited(purchase) do
    send(self(), {:credited, purchase.id, RegentCredits.TestRepo.in_transaction?()})
    :ok
  end
end

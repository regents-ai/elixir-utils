defmodule RegentCredits.TestSite do
  @moduledoc "A stand-in for the site that listens to `RegentCredits.Signals`."
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource RegentCredits.TestCredited
  end
end

defmodule RegentCredits.TestCredited do
  @moduledoc """
  A stand-in for the site's listener: tells the crediting process of each
  purchase credited or attributed, and whether it heard inside the credit's
  transaction.
  """
  use Ash.Resource, domain: RegentCredits.TestSite

  signals_in do
    from RegentCredits.Signals do
      on :purchase_credited, :credited_heard, action: :heard
      on :purchase_attributed, :attributed_heard, action: :heard
      on :card_purchase_credited, :card_heard, action: :heard
    end
  end

  actions do
    action :heard do
      argument :signal, :struct, allow_nil?: false

      run fn input, _context ->
        send(
          self(),
          {:credited, input.arguments.signal.purchase_id,
           RegentCredits.TestRepo.in_transaction?()}
        )

        :ok
      end
    end
  end
end

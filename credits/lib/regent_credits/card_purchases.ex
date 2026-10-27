defmodule RegentCredits.CardPurchases do
  @moduledoc """
  The work behind `RegentCredits.CardPurchase`'s actions.

  Stripe is called outside any database transaction. Crediting and taking back
  then follow `RegentCredits.Ledger`'s order in a transaction of their own, and
  re-read the purchase under the lock, so a webhook and the page crediting at
  the same moment credit once, and a repeated refund or dispute notice takes
  nothing more.

  The card purchase rows are written by the library after the action was
  authorized, so they run unauthorized.
  """

  require Ash.Query

  alias RegentCredits.{CardPurchase, Ledger, Stripe}
  alias RegentCredits.Errors.Refused

  @open_seconds 60 * 60

  @doc """
  The card fee and total, in US cents, for whole dollars of Credits: the
  smallest total that leaves the Credits whole after Stripe's 2.9% + 30 cents.
  """
  @spec price(pos_integer()) :: %{fee_cents: pos_integer(), total_cents: pos_integer()}
  def price(credits) do
    cents = credits * 100
    total = div((cents + 30) * 1_000 + 970, 971)
    %{fee_cents: total - cents, total_cents: total}
  end

  @doc "Opens the Checkout Session and records the purchase it pays for."
  def start(%{privy_user_id: owner, credits: credits} = args, actor) do
    if Decimal.lt?(RegentCredits.balance(owner).available, 0) do
      {:error, Refused.exception(reason: :below_zero)}
    else
      open(owner, credits, args, actor.site)
    end
  end

  # The page collects the email with Stripe's Contact Details Element.
  defp open(owner, credits, args, site) do
    id = Ecto.UUID.generate()
    %{fee_cents: fee, total_cents: total} = price(credits)

    params = %{
      ui_mode: "elements",
      mode: "payment",
      allowed_payment_method_types: ["card", "link"],
      client_reference_id: id,
      return_url: args.return_url,
      expires_at: System.system_time(:second) + @open_seconds,
      line_items: [
        line("#{credits} Regents Credits", credits * 100),
        line("Card fee", fee)
      ],
      metadata: %{card_purchase_id: id, privy_user_id: owner, site: site},
      payment_intent_data: %{metadata: %{card_purchase_id: id}}
    }

    with {:ok, %{"id" => session_id, "client_secret" => secret, "livemode" => livemode}} <-
           Stripe.open_session(id, params),
         {:ok, purchase} <- record(id, owner, site, credits, fee, total, session_id, livemode) do
      {:ok,
       %{
         id: purchase.id,
         session_id: session_id,
         client_secret: secret,
         credits: credits,
         fee_cents: fee,
         total_cents: total
       }}
    end
  end

  defp line(name, cents),
    do: %{
      quantity: 1,
      price_data: %{currency: "usd", unit_amount: cents, product_data: %{name: name}}
    }

  defp record(id, owner, site, credits, fee, total, session_id, livemode) do
    # Internal: written by the authorized start action.
    CardPurchase
    |> Ash.Changeset.for_create(
      :record,
      %{
        id: id,
        privy_user_id: owner,
        site: site,
        credits: credits,
        fee_cents: fee,
        total_cents: total,
        session_id: session_id,
        livemode: livemode
      },
      authorize?: false
    )
    |> Ash.create()
  end

  @doc "Reads the person's own purchase's session from Stripe and credits it once paid."
  def settle(session_id, actor) do
    CardPurchase
    |> Ash.Query.filter(session_id == ^session_id)
    |> Ash.read_one(actor: actor)
    |> case do
      {:ok, %CardPurchase{status: :open} = purchase} ->
        with {:ok, session} <- Stripe.session(session_id), do: credit(purchase, session)

      {:ok, %CardPurchase{} = purchase} ->
        {:ok, purchase}

      {:ok, nil} ->
        {:error, Refused.exception(reason: :not_found)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Handles a signed webhook notice: a paid session credits its purchase, a
  refund or dispute takes Credits back. A notice about a payment that is no
  card purchase of Credits, or of a kind not handled here, changes nothing.
  """
  def notice(%{payload: payload, signature: signature}) do
    case Stripe.event(payload, signature) do
      {:ok, %{"type" => type, "data" => %{"object" => object}}} -> handle(type, object)
      :error -> {:error, Refused.exception(reason: :not_from_stripe)}
    end
  end

  defp handle(type, %{"id" => session_id} = session)
       when is_binary(session_id) and
              type in ["checkout.session.completed", "checkout.session.async_payment_succeeded"] do
    case find(session_id: session_id) do
      nil -> :ok
      purchase -> with {:ok, _purchase} <- credit(purchase, session), do: :ok
    end
  end

  # `amount_refunded` counts every refund of the charge so far.
  defp handle("charge.refunded", %{"payment_intent" => intent} = charge)
       when is_binary(intent) do
    with %CardPurchase{} = purchase <- find(payment_intent_id: intent),
         %{"amount" => amount, "amount_refunded" => refunded} when amount > 0 <- charge do
      share =
        purchase.credits
        |> Decimal.new()
        |> Decimal.mult(refunded)
        |> Decimal.div(amount)
        |> Decimal.round(6, :down)

      take_back(purchase, share, "card_refund")
    else
      _not_a_card_purchase -> :ok
    end
  end

  defp handle("charge.dispute.created", %{"payment_intent" => intent}) when is_binary(intent) do
    case find(payment_intent_id: intent) do
      nil -> :ok
      purchase -> take_back(purchase, Decimal.new(purchase.credits), "card_dispute")
    end
  end

  defp handle(_type, _object), do: :ok

  # Only the session opened for this purchase, paid in full in US dollars with
  # the same kind of keys, credits it.
  defp credit(purchase, session) do
    if paid?(purchase, session),
      do: Ash.transact(CardPurchase, fn -> credit_once(purchase, session["payment_intent"]) end),
      else: {:ok, purchase}
  end

  defp paid?(purchase, session) do
    session["id"] == purchase.session_id and session["client_reference_id"] == purchase.id and
      session["payment_status"] == "paid" and session["amount_total"] == purchase.total_cents and
      session["currency"] == "usd" and session["livemode"] == purchase.livemode
  end

  defp credit_once(%{id: id, privy_user_id: owner}, intent) do
    Ledger.open(Ledger.person(owner))
    from = Ledger.identifier(:regent_purchases, nil)
    to = Ledger.identifier(:purchased, owner)
    accounts = Ledger.lock([from | Ledger.person(owner)])

    case get(id) do
      %{status: :open} = purchase ->
        Ledger.move(accounts, {from, to}, Decimal.new(purchase.credits), "card:#{id}")

        # Internal: written by the authorized settle or a signed notice.
        purchase
        |> Ash.Changeset.for_update(:credited, %{payment_intent_id: intent}, authorize?: false)
        |> Ash.update()
        |> unwrap()

      purchase ->
        purchase
    end
  end

  # Takes the purchase's Credits back up to `target` in all, whatever the
  # balance: a repeated notice moves nothing more.
  defp take_back(%{id: id, privy_user_id: owner}, target, operation) do
    from = Ledger.identifier(:purchased, owner)
    to = Ledger.identifier(:regent_refunds, nil)

    Ash.transact(CardPurchase, fn ->
      accounts = Ledger.lock([to | Ledger.person(owner)])
      purchase = get(id)
      more = Decimal.sub(target, purchase.taken_back)

      if purchase.status == :credited and Decimal.gt?(more, 0) do
        Ledger.move(accounts, {from, to}, more, "#{operation}:#{id}")

        # Internal: written by a signed notice.
        purchase
        |> Ash.Changeset.for_update(:took_back, %{taken_back: target}, authorize?: false)
        |> Ash.update()
        |> unwrap()
      else
        purchase
      end
    end)
    |> case do
      {:ok, _purchase} -> :ok
      {:error, _} = error -> error
    end
  end

  # Ash.transact wraps the purchase in {:ok, _} and rolls back an error.
  defp unwrap({:ok, purchase}), do: purchase
  defp unwrap({:error, _} = error), do: error

  defp find(by) do
    # Internal: read by a signed notice.
    CardPurchase
    |> Ash.Query.filter(^by)
    |> Ash.read_one!(authorize?: false)
  end

  defp get(id) do
    # Internal: read under the lock by the authorized settle or a signed notice.
    Ash.get!(CardPurchase, id, authorize?: false)
  end
end

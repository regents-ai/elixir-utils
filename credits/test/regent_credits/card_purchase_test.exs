defmodule RegentCredits.CardPurchaseTest do
  # Not async: some tests switch the Stripe keys to live ones.
  use ExUnit.Case, async: false

  import RegentCredits.Fixtures

  alias RegentCredits.{Actor, Stripe}
  alias RegentCredits.Errors.Refused

  @return "https://template.regents.sh/credits?card={CHECKOUT_SESSION_ID}"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(RegentCredits.TestRepo)
  end

  defp purchased(owner), do: RegentCredits.balance(owner).purchased
  defp admin_id, do: "did:privy:admin"

  # Stripe opens a session for each request and answers what it holds.
  defp stripe(sessions) do
    Req.Test.stub(Stripe, fn conn ->
      case {conn.method, conn.request_path} do
        {"POST", "/v1/checkout/sessions"} ->
          conn = Plug.Parsers.call(conn, Plug.Parsers.init(parsers: [:urlencoded]))

          send(
            self(),
            {:opened, conn.body_params, Plug.Conn.get_req_header(conn, "idempotency-key")}
          )

          id = "cs_test_" <> conn.body_params["client_reference_id"]
          Req.Test.json(conn, %{id: id, client_secret: id <> "_secret", livemode: false})

        {"GET", "/v1/checkout/sessions/" <> id} ->
          Req.Test.json(conn, Map.fetch!(sessions.(), id))
      end
    end)
  end

  defp start(owner, credits) do
    stripe(fn -> %{} end)

    RegentCredits.start_card_purchase(owner, credits, @return, actor: actor(owner))
  end

  defp paid(purchase, changes \\ %{}) do
    Map.merge(
      %{
        "id" => purchase.session_id,
        "object" => "checkout.session",
        "client_reference_id" => purchase.id,
        "payment_status" => "paid",
        "status" => "complete",
        "amount_total" => purchase.total_cents,
        "currency" => "usd",
        "livemode" => false,
        "payment_intent" => "pi_" <> purchase.id
      },
      changes
    )
  end

  defp notice(type, object, at \\ System.system_time(:second)) do
    payload = JSON.encode!(%{id: "evt_1", type: type, data: %{object: object}})

    RegentCredits.card_notice(payload, "t=#{at},v1=#{Stripe.sign(at, payload)}",
      actor: Actor.site("template")
    )
  end

  defp purchase(id), do: Ash.get!(RegentCredits.CardPurchase, id, authorize?: false)

  defp with_live_keys(fun) do
    stripe = Application.fetch_env!(:regent_credits, :stripe)
    Application.put_env(:regent_credits, :stripe, Keyword.put(stripe, :secret_key, "sk_live_x"))

    try do
      fun.()
    after
      Application.put_env(:regent_credits, :stripe, stripe)
    end
  end

  test "a card purchase charges the Credits plus the card fee, and only admins may try it with test keys" do
    assert RegentCredits.card_price(5) == %{fee_cents: 46, total_cents: 546}
    assert RegentCredits.card_price(500) == %{fee_cents: 1_525, total_cents: 51_525}

    for credits <- 5..500 do
      %{total_cents: total} = RegentCredits.card_price(credits)
      # What Stripe keeps leaves the Credits whole, by less than a cent more.
      kept = total - (total * 29 / 1_000 + 30)
      assert kept >= credits * 100 and kept < credits * 100 + 1
    end

    assert {:error, %Ash.Error.Forbidden{}} = start(person(), 25)

    {:ok, started} = start(admin_id(), 25)
    assert started.total_cents == 2_606 and started.fee_cents == 106
    assert started.client_secret == "cs_test_#{started.id}_secret"

    assert_received {:opened, params, [key]}
    assert key == "card-purchase-" <> started.id
    assert params["ui_mode"] == "elements"
    # Stripe reads lists as numbered fields.
    assert params["allowed_payment_method_types"] == %{"0" => "card", "1" => "link"}
    assert params["return_url"] == @return

    assert %{
             "0" => %{
               "price_data" => %{"unit_amount" => "2500", "product_data" => %{"name" => name}}
             },
             "1" => %{"price_data" => %{"unit_amount" => "106"}}
           } = params["line_items"]

    assert name == "25 Regents Credits"

    with_live_keys(fn ->
      owner = person()
      assert {:ok, _started} = start(owner, 10)

      # Nobody starts a card purchase for someone else.
      assert {:error, %Ash.Error.Forbidden{}} =
               RegentCredits.start_card_purchase(owner, 10, @return, actor: actor(person()))
    end)
  end

  test "Stripe's notice of a paid session adds the Credits once, and the page then finds them added" do
    {:ok, %{id: id}} = start(admin_id(), 25)
    bought = purchase(id)
    before = purchased(admin_id())

    assert notice("checkout.session.completed", paid(bought)) == :ok
    assert notice("checkout.session.completed", paid(bought)) == :ok
    assert Decimal.eq?(Decimal.sub(purchased(admin_id()), before), 25)

    stripe(fn -> %{bought.session_id => paid(bought)} end)

    {:ok, settled} =
      RegentCredits.settle_card_purchase(bought.session_id, actor: actor(admin_id()))

    assert settled.status == :credited and settled.payment_intent_id == "pi_" <> id
    assert Decimal.eq?(Decimal.sub(purchased(admin_id()), before), 25)

    {:ok, %{entries: [entry | _]}} = RegentCredits.history(actor: actor(admin_id()))
    assert %{kind: :bought_by_card, direction: :in} = entry
    assert Decimal.eq?(entry.amount, 25)
    assert RegentCredits.History.Words.line(entry) == "Bought Credits by card"
  end

  test "the page settles a paid session itself, and nobody else can settle it" do
    {:ok, %{id: id}} = start(admin_id(), 7)
    bought = purchase(id)
    before = purchased(admin_id())

    stripe(fn -> %{bought.session_id => paid(bought, %{"payment_status" => "unpaid"})} end)
    {:ok, open} = RegentCredits.settle_card_purchase(bought.session_id, actor: actor(admin_id()))
    assert open.status == :open

    stripe(fn -> %{bought.session_id => paid(bought)} end)

    assert {:error, %Ash.Error.Invalid{errors: [%Refused{reason: :not_found}]}} =
             RegentCredits.settle_card_purchase(bought.session_id, actor: actor(person()))

    {:ok, settled} =
      RegentCredits.settle_card_purchase(bought.session_id, actor: actor(admin_id()))

    assert settled.status == :credited
    assert Decimal.eq?(Decimal.sub(purchased(admin_id()), before), 7)
  end

  test "only a session paid in full for this purchase adds Credits" do
    {:ok, %{id: id}} = start(admin_id(), 10)
    bought = purchase(id)
    before = purchased(admin_id())

    for changes <- [
          %{"amount_total" => bought.total_cents - 1},
          %{"currency" => "eur"},
          %{"livemode" => true},
          %{"client_reference_id" => Ecto.UUID.generate()}
        ] do
      assert notice("checkout.session.completed", paid(bought, changes)) == :ok
    end

    assert purchase(id).status == :open
    assert Decimal.eq?(purchased(admin_id()), before)
  end

  test "a notice Stripe did not sign, or signed long ago, changes nothing" do
    {:ok, %{id: id}} = start(admin_id(), 10)
    session = paid(purchase(id))
    payload = JSON.encode!(%{type: "checkout.session.completed", data: %{object: session}})
    now = System.system_time(:second)

    for signature <- [
          "t=#{now},v1=#{Stripe.sign(now, payload <> " ")}",
          "t=#{now - 301},v1=#{Stripe.sign(now - 301, payload)}",
          "v1=#{Stripe.sign(now, payload)}",
          "nonsense"
        ] do
      assert {:error, %Ash.Error.Invalid{errors: [%Refused{reason: :not_from_stripe}]}} =
               RegentCredits.card_notice(payload, signature, actor: Actor.site("template"))
    end

    assert purchase(id).status == :open

    assert {:error, %Ash.Error.Forbidden{}} =
             RegentCredits.card_notice(payload, "t=#{now},v1=#{Stripe.sign(now, payload)}",
               actor: actor(admin_id())
             )

    # Payments that are not card purchases of Credits are none of its business.
    assert notice("checkout.session.completed", %{session | "id" => "cs_other"}) == :ok

    assert notice("charge.refunded", %{
             "payment_intent" => nil,
             "amount" => 1,
             "amount_refunded" => 1
           }) == :ok

    assert notice("customer.created", %{"id" => "cus_1"}) == :ok
  end

  test "refunds take back their share, a dispute the rest even below zero, and then no new card purchase starts" do
    owner = admin_id()
    {:ok, %{id: id}} = start(owner, 10)
    bought = purchase(id)
    :ok = notice("checkout.session.completed", paid(bought))
    before = purchased(owner)
    charge = %{"payment_intent" => "pi_" <> id, "amount" => bought.total_cents}

    # A quarter of the charge back takes a quarter of the Credits; a repeat takes nothing.
    quarter = div(bought.total_cents, 4)
    :ok = notice("charge.refunded", Map.put(charge, "amount_refunded", quarter))
    :ok = notice("charge.refunded", Map.put(charge, "amount_refunded", quarter))

    share = Decimal.div(Decimal.mult(10, quarter), bought.total_cents) |> Decimal.round(6, :down)
    assert Decimal.eq?(Decimal.sub(before, purchased(owner)), share)

    # Spending the rest leaves nothing for the dispute to take but the balance.
    {:ok, _hold} =
      RegentCredits.hold(key(), owner, RegentCredits.balance(owner).available, "fix",
        actor: actor(owner)
      )

    :ok = notice("charge.dispute.created", %{"payment_intent" => "pi_" <> id, "amount" => 1})
    :ok = notice("charge.dispute.created", %{"payment_intent" => "pi_" <> id, "amount" => 1})

    assert Decimal.eq?(purchase(id).taken_back, 10)
    assert Decimal.lt?(RegentCredits.balance(owner).available, 0)

    {:ok, %{entries: entries}} = RegentCredits.history(actor: actor(owner))
    assert [%{direction: :out} = disputed] = Enum.filter(entries, &(&1.kind == :card_disputed))
    assert [%{direction: :out} = refunded] = Enum.filter(entries, &(&1.kind == :card_refunded))
    assert Decimal.eq?(Decimal.add(disputed.amount, refunded.amount), 10)

    assert {:error, %Ash.Error.Invalid{errors: [%Refused{reason: :below_zero}]}} = start(owner, 5)
  end
end

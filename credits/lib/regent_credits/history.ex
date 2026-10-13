defmodule RegentCredits.History do
  @moduledoc """
  A person's own Credits history: everything that moved their balance, newest
  first, one entry for each thing that happened. `history_of` answers the same
  entries for the person a Credits admin names, so the team reads exactly what
  the person reads.

  The ledger writes one transfer for each kind of Credit an operation moves, so
  setting four Credits aside can be two transfers (given and purchased) and
  closing an Offer's hold up to four. An entry adds those together. Its `kind`
  says what happened:

    * `:bought`: a purchase was credited.
    * `:gift`: Credits were given, or a gift waiting under a wallet arrived.
    * `:refund`: a purchase's Credits were taken out to be paid back.
    * `:set_aside`: Credits were held for a spend on a site.
    * `:returned`: held Credits came back.
    * `:spent`: held Credits were used.
    * `:received`: Credits another person set aside were paid to this one. The
      entry never says who paid.

  Every entry has the same keys:

    * `id`, `kind`, `at`, and `amount`, which is always positive.
    * `direction`: `:in` or `:out` of the Credits the person can spend, or
      `:none` for `:spent`, which were already set aside.
    * `site`, `purpose` and `reason`: where a hold was placed, what for and why
      it came back, in the site's own short codes.
    * `agent_address` and `pairing_id`: the person's agent that set the Credits
      aside, when an agent did. A payment received never names the payer's.
    * `key`, `tool` and `request`: the site's own id for what the Credits were
      set aside for, the tool or page that set them aside, and the tool's
      arguments as they were sent, when the site kept them. An agent reading
      the history is given `request` only on a hold it placed itself, and a
      payment received has none of the three.
    * `note`: a gift's note.
    * `chain` and `tx_hash`: a purchase's payment, or a refund's payment back
      once it is sent.
    * `refund_status` (`:locked` or `:sent`) and `refund_sent_at`.

  A key that does not apply is `nil`. `RegentCredits.History.Words` turns an
  entry into the words a page shows; no page reads an operation string.

  A page holds the entries of at most 50 transfers and never ends inside one
  entry. Pass `%{after: page.next}` to read older entries while `page.more?`.
  """
  use Ash.Resource,
    domain: RegentCredits,
    authorizers: [Ash.Policy.Authorizer]

  actions do
    action :history, :map do
      argument :after, :string, constraints: [max_length: 2_048]
      run RegentCredits.History.Read
    end

    action :history_of, :map do
      argument :privy_user_id, :string, allow_nil?: false, constraints: [max_length: 255]
      argument :after, :string, constraints: [max_length: 2_048]
      run RegentCredits.History.Read
    end
  end

  policies do
    policy action(:history) do
      authorize_if actor_attribute_equals(:role, :person)

      authorize_if {RegentAgents.Checks.Paired,
                    repo_app: :regent_credits, wallet_field: :agent_address}
    end

    policy action(:history_of) do
      authorize_if RegentCredits.Checks.Admin
    end
  end
end

defmodule RegentCredits.History.Read do
  @moduledoc false
  use Ash.Resource.Actions.Implementation
  require Ash.Query
  alias RegentCredits.{Gift, Hold, Ledger, Purchase, Refund, Wallet}
  alias RegentCredits.Ledger.{Account, Transfer}

  @transfers 50
  @available ["given", "purchased"]
  @held ["held_given", "held_purchased"]
  @summed [:set_aside, :returned, :spent, :received]

  @blank %{
    site: nil,
    purpose: nil,
    reason: nil,
    agent_address: nil,
    pairing_id: nil,
    key: nil,
    tool: nil,
    request: nil,
    note: nil,
    chain: nil,
    tx_hash: nil,
    refund_status: nil,
    refund_sent_at: nil
  }

  # A person or their agent reads the actor's own accounts, never an input's.
  # Only `history_of`, which the policy keeps to Credits admins, names a person.
  @impl true
  def run(%{action: %{name: :history}} = input, _opts, %{
        actor: %RegentCredits.Actor{role: role, privy_user_id: owner}
      })
      when role in [:person, :agent] and is_binary(owner),
      do: read(owner, input)

  def run(%{action: %{name: :history_of}} = input, _opts, %{
        actor: %RegentCredits.Actor{role: :admin}
      }),
      do: read(input.arguments.privy_user_id, input)

  def run(_input, _opts, _context), do: {:error, Ash.Error.Forbidden.exception([])}

  defp read(owner, input) do
    identifiers = Ledger.person(owner)

    # Internal: read by the authorized history action, for the one person it resolved.
    accounts =
      Account
      |> Ash.Query.filter(identifier in ^identifiers)
      |> Ash.Query.select([:id, :identifier])
      |> Ash.read!(authorize?: false)
      |> Map.new(&{&1.id, hd(String.split(&1.identifier, "/", parts: 2))})

    ids = Map.keys(accounts)

    page =
      [limit: @transfers] ++
        if(input.arguments[:after], do: [after: input.arguments.after], else: [])

    # The authorized action has already resolved ownership. Related account
    # policies need not be bypassed or widened to reveal a counterparty.
    Transfer
    |> Ash.Query.filter(from_account_id in ^ids or to_account_id in ^ids)
    |> Ash.Query.sort(id: :desc)
    |> Ash.Query.for_read(:read_transfers)
    |> Ash.read(authorize?: false, page: page)
    |> case do
      {:ok, %{more?: more?} = page} ->
        transfers = whole_events(page.results, more?)

        {:ok,
         %{
           entries: entries(transfers, accounts, owner, input.context.private.actor),
           more?: more?,
           next: if(more?, do: List.last(transfers).__metadata__.keyset)
         }}

      {:error, _} = error ->
        error
    end
  end

  # A hold's transfers follow one another in the person's ledger, because every
  # operation on it locks the person's accounts, and a hold writes at most six
  # in its life. When older transfers remain, the page's last hold may have
  # some of them, so it is left whole for the next page.
  defp whole_events(transfers, false), do: transfers

  defp whole_events(transfers, true) do
    case List.last(transfers).operation do
      "hold:" <> _site_and_key = last ->
        transfers
        |> Enum.reverse()
        |> Enum.drop_while(&(&1.operation == last))
        |> Enum.reverse()

      _one_transfer_each ->
        transfers
    end
  end

  # `reader` is the actor the entries are for.
  defp entries(transfers, accounts, owner, reader) do
    movements = Enum.map(transfers, &movement(&1, accounts))
    found = Map.put(found(movements, owner), :reader, reader)

    movements
    |> Enum.group_by(&event/1)
    |> Enum.map(fn {_event, [newest | _older] = parts} ->
      amount = parts |> Enum.map(& &1.amount) |> Enum.reduce(&Decimal.add/2)

      @blank
      |> Map.merge(%{
        id: newest.id,
        kind: newest.kind,
        at: newest.at,
        amount: amount,
        direction: direction(newest.kind)
      })
      |> Map.merge(facts(newest, found))
    end)
    |> Enum.sort_by(& &1.id, :desc)
  end

  defp movement(transfer, accounts) do
    from = accounts[transfer.from_account_id]
    to = accounts[transfer.to_account_id]

    %{
      id: transfer.id,
      at: transfer.timestamp,
      amount: transfer.amount.amount,
      operation: transfer.operation,
      kind: kind(from, to, transfer.operation)
    }
  end

  # What happened, from which of the person's accounts the Credits left and
  # entered (`nil` is an account that is not theirs) and the operation that
  # moved them.
  defp kind(from, to, _operation) when from in @available and to in @held, do: :set_aside
  defp kind(from, to, _operation) when from in @held and to in @available, do: :returned
  defp kind(from, nil, _operation) when from in @held, do: :spent
  defp kind(from, nil, "refund:" <> _id) when from in @available, do: :refund
  defp kind(nil, to, "purchase:" <> _id) when to in @available, do: :bought
  defp kind(nil, "purchased", "attach:" <> _account), do: :bought
  defp kind(nil, "given", "attach:" <> _account), do: :gift
  defp kind(nil, to, "gift:" <> _key) when to in @available, do: :gift
  defp kind(nil, to, "hold:" <> _site_and_key) when to in @available, do: :received

  # A hold's operation and what happened name one event, whatever order its
  # transfers were written in. Every other transfer is an event of its own.
  defp event(%{kind: kind, operation: operation}) when kind in @summed, do: {operation, kind}
  defp event(%{id: id}), do: id

  defp direction(kind) when kind in [:bought, :gift, :returned, :received], do: :in
  defp direction(kind) when kind in [:refund, :set_aside], do: :out
  defp direction(:spent), do: :none

  # The person's own records the page's transfers name, each kind read once.
  # The records are filtered by the person as well as by what the operation
  # names, so nothing of anyone else's can be found here.
  defp found(movements, owner) do
    named = Enum.group_by(movements, &hd(String.split(&1.operation, ":")), &named/1)

    %{
      holds: holds(owner, named["hold"]),
      purchases: purchases(owner, named["purchase"]),
      refunds: refunds(owner, named["refund"]),
      gifts: gifts(owner, named["gift"])
    }
  end

  defp named(%{operation: "hold:" <> site_and_key}) do
    [site, key] = String.split(site_and_key, ":", parts: 2)
    {site, key}
  end

  defp named(%{operation: operation}) do
    [_prefix, name] = String.split(operation, ":", parts: 2)
    name
  end

  defp holds(_owner, nil), do: %{}

  defp holds(owner, names) do
    keys = names |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

    # Internal: read by the authorized history action, for its own person only.
    Hold
    |> Ash.Query.filter(privy_user_id == ^owner and key in ^keys)
    |> Ash.read!(authorize?: false)
    |> Map.new(&{{&1.site, &1.key}, &1})
  end

  defp purchases(_owner, nil), do: %{}

  defp purchases(owner, ids) do
    # Internal: read by the authorized history action, for its own person only.
    Purchase
    |> Ash.Query.filter(privy_user_id == ^owner and id in ^Enum.uniq(ids))
    |> Ash.read!(authorize?: false)
    |> Map.new(&{&1.id, &1})
  end

  defp refunds(_owner, nil), do: %{}

  defp refunds(owner, purchase_ids) do
    # Internal: read by the authorized history action, for its own person only.
    Refund
    |> Ash.Query.filter(privy_user_id == ^owner and purchase_id in ^Enum.uniq(purchase_ids))
    |> Ash.read!(authorize?: false)
    |> Map.new(&{&1.purchase_id, &1})
  end

  defp gifts(_owner, nil), do: %{}

  # A gift is recorded under the account, or under a wallet the account holds.
  defp gifts(owner, keys) do
    wallets =
      Wallet
      |> Ash.Query.filter(privy_user_id == ^owner)
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.address)

    Gift
    |> Ash.Query.filter(key in ^Enum.uniq(keys) and to in ^[owner | wallets])
    |> Ash.read!(authorize?: false)
    |> Map.new(&{&1.key, &1})
  end

  # A payment received names its site and nothing else: the hold is the
  # payer's, so it is never among `found.holds`.
  defp facts(%{kind: kind} = movement, found) when kind in @summed do
    {site, _key} = name = named(movement)

    case found.holds[name] do
      %Hold{} = hold ->
        %{
          site: site,
          purpose: hold.purpose,
          reason: if(kind == :returned, do: hold.reason),
          agent_address: hold.agent_address,
          pairing_id: hold.pairing_id,
          key: hold.key,
          tool: hold.tool,
          request: if(reads_request?(found.reader, hold), do: hold.request)
        }

      nil ->
        %{site: site}
    end
  end

  defp facts(%{kind: :bought, operation: "purchase:" <> _id} = movement, found) do
    case found.purchases[named(movement)] do
      %Purchase{chain: chain, tx_hash: tx_hash} -> %{chain: chain, tx_hash: tx_hash}
      nil -> %{}
    end
  end

  defp facts(%{kind: :refund} = movement, found) do
    case found.refunds[named(movement)] do
      %Refund{} = refund ->
        %{
          chain: refund.chain,
          tx_hash: refund.tx_hash,
          refund_status: refund.status,
          refund_sent_at: refund.sent_at
        }

      nil ->
        %{}
    end
  end

  defp facts(%{kind: :gift, operation: "gift:" <> _key} = movement, found) do
    case found.gifts[named(movement)] do
      %Gift{note: note} -> %{note: note}
      nil -> %{}
    end
  end

  # Credits that waited under a wallet until the account signed in with it.
  defp facts(%{operation: "attach:" <> _account}, _found), do: %{}

  # An agent reads the request only on a hold it placed itself, so one agent's
  # words never reach another agent of the same person as data.
  defp reads_request?(%{role: :agent, agent_address: agent}, hold),
    do: hold.agent_address == agent

  defp reads_request?(_person_or_admin, _hold), do: true
end

defmodule RegentChain.Presses do
  @moduledoc """
  The reviews a page pushed and what its wallet did with them, on the server.

  Keep one `%RegentChain.Presses{}` in the page's assigns. `remember/2` every
  review as it is pushed. The page reports each press against the review it sent
  from, by the review's `id`, and every check afterwards is against that review,
  so two presses answered in reverse order, or a press made just before an edit,
  can never take each other's outcome.

  Reviews stay recognisable for a while after the page moved on (the newest 32),
  so a press made just before a keystroke still counts; a report naming a review
  that is no longer known is shown as one the page cannot follow. The newest eight
  sent steps are kept to show. Nothing here is stored beyond the page: a reload
  reads the chain again and restores no pending transaction.

      {:ok, entry, presses} = Presses.sent(presses, params)
      # every 2 s while Presses.reading?(entry):
      result = RegentChain.Outcome.of(MyApp.Chain.Client, entry.review, entry.step, entry.hash)
      {entry, presses} = Presses.checked(presses, entry.hash, result)
  """

  alias RegentChain.Review

  @review_limit 32
  @shown_limit 8
  @read_limit 90
  @failures ~w(step_unknown wallet_unavailable network_mismatch wallet_declined insufficient_funds send_unconfirmed sign_unconfirmed)
  @hash ~r/\A0x[0-9a-fA-F]{64}\z/
  @signature ~r/\A0x[0-9a-fA-F]{130}\z/

  defstruct reviews: [], sent: []

  @typedoc """
  One sent transaction. `outcome` is `:pending`, `:confirmed`, `:reverted`,
  `:not_this_step` (the chain holds a different transaction under this hash) or
  `:unknown` (the page named a review or step this server did not build).
  """
  @type entry :: %{
          hash: String.t(),
          name: String.t(),
          review: Review.t() | nil,
          step: Review.transaction() | nil,
          outcome: atom(),
          reads: non_neg_integer()
        }
  @type t :: %__MODULE__{reviews: [Review.t()], sent: [entry()]}

  @doc "Nothing pushed and nothing sent."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Keeps `review` recognisable. Call it whenever a review is pushed."
  @spec remember(t(), Review.t()) :: t()
  def remember(%__MODULE__{reviews: reviews} = presses, %{id: id} = review) do
    %{
      presses
      | reviews: Enum.take([review | Enum.reject(reviews, &(&1.id == id))], @review_limit)
    }
  end

  @doc """
  The wallet sent a step: `%{"review_id", "step", "transaction_hash"}` from the
  page. The entry is the page's to show; read it while `reading?/1`. A hash
  already reported keeps its entry. Anything else is `:error`.
  """
  @spec sent(t(), map()) :: {:ok, entry(), t()} | :error
  def sent(presses, %{"review_id" => id, "step" => name, "transaction_hash" => hash})
      when is_binary(id) and is_binary(name) and is_binary(hash) do
    if Regex.match?(@hash, hash) do
      hash = String.downcase(hash)

      case entry(presses, hash) do
        nil ->
          review = review(presses, id)
          step = review && transaction(review, name)
          outcome = if step, do: :pending, else: :unknown

          entry = %{
            hash: hash,
            name: name,
            review: review,
            step: step,
            outcome: outcome,
            reads: 0
          }

          {:ok, entry, put(presses, entry)}

        entry ->
          {:ok, entry, presses}
      end
    else
      :error
    end
  end

  def sent(_presses, _params), do: :error

  @doc """
  The wallet signed a step: `%{"review_id", "step", "signature"}` from the page.
  The answer carries the typed data from this server's own review, never the
  page's, for the site to hand on with the signature.
  """
  @spec signed(t(), map()) ::
          {:ok, %{review: Review.t(), step: Review.signature(), signature: String.t()}}
          | :error
  def signed(presses, %{"review_id" => id, "step" => name, "signature" => signature})
      when is_binary(id) and is_binary(name) and is_binary(signature) do
    with true <- Regex.match?(@signature, signature),
         %{} = review <- review(presses, id),
         %{kind: "signature"} = step <- Review.find(review, name) do
      {:ok, %{review: review, step: step, signature: String.downcase(signature)}}
    else
      _unknown -> :error
    end
  end

  def signed(_presses, _params), do: :error

  @doc """
  Nothing was sent, or the wallet may have sent or signed it: `%{"step", "reason"}`
  from the page. The reason picks the words the page shows: `send_unconfirmed`
  when a transaction may have gone, `sign_unconfirmed` when a signature may have
  been made.
  """
  @spec failed(map()) :: {:ok, String.t(), String.t()} | :error
  def failed(%{"step" => name, "reason" => reason}) when is_binary(name) and reason in @failures,
    do: {:ok, name, reason}

  def failed(_params), do: :error

  @doc """
  One answer from `RegentChain.Outcome.of/4` about the step sent as `hash`, or
  `{nil, presses}` when the page has since let that step go. A read that failed
  is no answer, so the step stays pending and is read again.
  """
  @spec checked(t(), String.t(), term()) :: {entry() | nil, t()}
  def checked(presses, hash, result) do
    case entry(presses, hash) do
      nil ->
        {nil, presses}

      entry ->
        entry = %{entry | outcome: outcome(result), reads: entry.reads + 1}
        {entry, put(presses, entry)}
    end
  end

  @doc "Starts reading a step again after the page stopped on its own."
  @spec check_again(t(), String.t()) :: {entry() | nil, t()}
  def check_again(presses, hash) do
    case entry(presses, hash) do
      %{step: %{}} = entry ->
        entry = %{entry | outcome: :pending, reads: 0}
        {entry, put(presses, entry)}

      _unknown ->
        {nil, presses}
    end
  end

  @doc "Whether the step is still being read."
  @spec reading?(entry()) :: boolean()
  def reading?(%{outcome: outcome, reads: reads}), do: outcome == :pending and reads < @read_limit

  @doc "Whether the page stopped reading a step that had not landed; offer \"Check again\"."
  @spec stalled?(entry()) :: boolean()
  def stalled?(%{outcome: outcome, reads: reads}),
    do: outcome == :pending and reads >= @read_limit

  @doc """
  Whether the step `name` of `review`, for the same signer on the same chain, was
  sent and is still being read: an approval on its way, for example, so the
  button can offer the next step. It never stops a press.
  """
  @spec on_its_way?(t(), Review.t(), String.t()) :: boolean()
  def on_its_way?(%__MODULE__{sent: sent}, review, name) do
    step = Review.find(review, name)

    step != nil and
      Enum.any?(
        sent,
        &(&1.step == step and &1.review.signer == review.signer and
            &1.review.chain.chain_id == review.chain.chain_id and reading?(&1))
      )
  end

  @doc "The sent steps to show, newest first."
  @spec shown(t()) :: [entry()]
  def shown(%__MODULE__{sent: sent}), do: sent

  defp review(%__MODULE__{reviews: reviews}, id), do: Enum.find(reviews, &(&1.id == id))

  defp transaction(review, name) do
    case Review.find(review, name) do
      %{kind: "transaction"} = step -> step
      _other -> nil
    end
  end

  defp entry(%__MODULE__{sent: sent}, hash), do: Enum.find(sent, &(&1.hash == hash))

  defp put(%__MODULE__{sent: sent} = presses, entry) do
    sent =
      case Enum.find_index(sent, &(&1.hash == entry.hash)) do
        nil -> Enum.take([entry | sent], @shown_limit)
        index -> List.replace_at(sent, index, entry)
      end

    %{presses | sent: sent}
  end

  defp outcome({:ok, outcome}) when outcome in [:pending, :confirmed, :reverted], do: outcome
  defp outcome({:error, :not_this_step}), do: :not_this_step
  defp outcome(_unanswered), do: :pending
end

defmodule RegentPoints.Intake do
  @moduledoc "Queues only a durable source reference. Points validation never runs in the person's action."
  use Ash.Resource.Actions.Implementation
  alias RegentPoints.{Enqueue, IntakeWorker, Rules}
  @keys ~w(rule_id source_app source_kind source_event_key)
  @impl true
  def run(%{arguments: %{event: input}}, _, _) do
    reference = Map.new(input, fn {key, value} -> {to_string(key), value} end) |> Map.take(@keys)

    cond do
      not Enum.all?(@keys, &(is_binary(reference[&1]) and byte_size(reference[&1]) in 1..512)) ->
        {:ok, %{status: :not_queued, reason: :invalid_source_reference}}

      not Rules.enabled?(reference["rule_id"]) ->
        {:ok, %{status: :disabled}}

      true ->
        Enqueue.call(IntakeWorker, reference)
    end
  end
end

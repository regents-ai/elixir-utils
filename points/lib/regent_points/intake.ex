defmodule RegentPoints.Intake do
  @moduledoc """
  Queues only a durable source reference. Points validation never runs in the
  person's action, and a rule that is off answers `disabled` before anything else
  is looked at, so it can never refuse the action it rides in.
  """
  use Ash.Resource.Actions.Implementation
  alias RegentPoints.{Enqueue, IntakeWorker, Rules}
  @keys ~w(rule_id source_app source_kind source_event_key)
  @impl true
  def run(%{arguments: %{event: input}}, _, _) do
    reference = Map.new(input, fn {key, value} -> {to_string(key), value} end) |> Map.take(@keys)

    cond do
      not Rules.enabled?(reference["rule_id"]) ->
        {:ok, %{status: :disabled}}

      not Enum.all?(@keys, &(is_binary(reference[&1]) and byte_size(reference[&1]) in 1..512)) ->
        {:error, "Invalid Points source reference"}

      true ->
        Enqueue.call(IntakeWorker, reference)
    end
  end
end

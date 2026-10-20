defmodule RegentNames.Validations.LabelRules do
  @moduledoc false
  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidArgument

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_argument(changeset, :label) do
      label when is_binary(label) ->
        case RegentNames.label_problems(label) do
          [] -> :ok
          [problem | _] -> {:error, InvalidArgument.exception(field: :label, message: problem)}
        end

      _missing ->
        :ok
    end
  end
end

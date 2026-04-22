defmodule XmtpElixirSdk.Metadata do
  @moduledoc """
  Public metadata helpers for field names and group update inspection.
  """

  alias XmtpElixirSdk.Constants
  alias XmtpElixirSdk.Content
  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Types

  @spec field_name(Types.metadata_field()) :: String.t()
  defdelegate field_name(field), to: Constants, as: :metadata_field_name

  @spec field_from_name(String.t()) :: {:ok, Types.metadata_field()} | {:error, Error.t()}
  defdelegate field_from_name(name), to: Constants, as: :metadata_field_from_name

  @spec changed_fields(Content.GroupUpdated.t()) :: [Types.metadata_field()]
  def changed_fields(%Content.GroupUpdated{metadata_field_changes: changes}) do
    changes
    |> Enum.flat_map(fn %{field_name: field_name} ->
      case field_from_name(field_name) do
        {:ok, field} -> [field]
        {:error, _error} -> []
      end
    end)
  end

  @spec field_changed?(Content.GroupUpdated.t(), Types.metadata_field()) :: boolean()
  def field_changed?(%Content.GroupUpdated{} = content, field) do
    Enum.any?(content.metadata_field_changes, fn %{field_name: field_name} ->
      case field_from_name(field_name) do
        {:ok, current_field} -> current_field == field
        {:error, _error} -> false
      end
    end)
  end
end

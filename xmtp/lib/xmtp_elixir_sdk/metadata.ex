defmodule XmtpElixirSdk.Metadata do
  @moduledoc """
  Public metadata helpers for field names and group update inspection.
  """

  alias XmtpElixirSdk.Constants
  alias XmtpElixirSdk.Content
  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Types

  @spec field_name(Types.metadata_field()) :: String.t()
  def field_name(field), do: Constants.metadata_field_name(field)

  @spec field_from_name(String.t()) :: {:ok, Types.metadata_field()} | {:error, Error.t()}
  def field_from_name(name), do: Constants.metadata_field_from_name(name)

  @spec changed_fields(Content.GroupUpdated.t()) :: [Types.metadata_field()]
  def changed_fields(%Content.GroupUpdated{metadata_field_changes: changes}) do
    changes
    |> Enum.flat_map(fn %{field_name: field_name} ->
      case field_from_name(field_name) do
        {:ok, field} -> [field]
        {:error, %Error{}} -> []
      end
    end)
  end

  @spec field_changed?(Content.GroupUpdated.t(), Types.metadata_field()) :: boolean()
  def field_changed?(%Content.GroupUpdated{} = content, field) do
    field in changed_fields(content)
  end
end

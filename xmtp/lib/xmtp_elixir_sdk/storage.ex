defmodule XmtpElixirSdk.Storage do
  @moduledoc """
  Local storage helper used by the SDK core.
  """

  alias XmtpElixirSdk.Error

  defstruct [:root]

  @type t :: %__MODULE__{root: Path.t()}

  @spec new(Path.t()) :: t()
  def new(root) when is_binary(root), do: %__MODULE__{root: root}

  @spec init(t()) :: {:ok, t()} | {:error, Error.t()}
  def init(%__MODULE__{root: root} = storage) do
    case File.mkdir_p(root) do
      :ok ->
        {:ok, storage}

      {:error, reason} ->
        {:error, Error.io("failed to initialize storage", %{reason: reason, root: root})}
    end
  end

  @spec list_files(t()) :: {:ok, [Path.t()]} | {:error, Error.t()}
  def list_files(%__MODULE__{root: root}) do
    case File.ls(root) do
      {:ok, files} ->
        {:ok, Enum.map(files, &Path.join(root, &1))}

      {:error, reason} ->
        {:error, Error.io("failed to list storage files", %{reason: reason, root: root})}
    end
  end

  @spec file_count(t()) :: {:ok, non_neg_integer()} | {:error, Error.t()}
  def file_count(storage) do
    with {:ok, files} <- list_files(storage) do
      {:ok, length(files)}
    end
  end

  @spec file_exists(t(), Path.t()) :: {:ok, boolean()} | {:error, Error.t()}
  def file_exists(%__MODULE__{root: root}, path) do
    with {:ok, full} <- resolve_path(root, path) do
      {:ok, File.exists?(full)}
    end
  end

  @spec delete_file(t(), Path.t()) :: {:ok, boolean()} | {:error, Error.t()}
  def delete_file(%__MODULE__{root: root}, path) do
    with {:ok, full} <- resolve_path(root, path) do
      case File.rm(full) do
        :ok ->
          {:ok, true}

        {:error, reason} ->
          {:error, Error.io("failed to delete file", %{reason: reason, path: full})}
      end
    end
  end

  @spec export_db(t(), Path.t()) :: {:ok, binary()} | {:error, Error.t()}
  def export_db(%__MODULE__{root: root}, path) do
    with {:ok, full} <- resolve_path(root, path) do
      case File.read(full) do
        {:ok, data} ->
          {:ok, data}

        {:error, reason} ->
          {:error, Error.io("failed to export database", %{reason: reason, path: full})}
      end
    end
  end

  @spec import_db(t(), Path.t(), binary()) :: :ok | {:error, Error.t()}
  def import_db(%__MODULE__{root: root}, path, data) when is_binary(data) do
    with {:ok, full} <- resolve_path(root, path) do
      File.write(full, data)
      |> case do
        :ok ->
          :ok

        {:error, reason} ->
          {:error, Error.io("failed to import database", %{reason: reason, path: full})}
      end
    end
  end

  @spec clear_all(t()) :: :ok | {:error, Error.t()}
  def clear_all(%__MODULE__{root: root}) do
    case File.rm_rf(root) do
      {:ok, _} ->
        case File.mkdir_p(root) do
          :ok ->
            :ok

          {:error, reason} ->
            {:error, Error.io("failed to clear storage", %{reason: reason, root: root})}
        end

      {:error, reason, _} ->
        {:error, Error.io("failed to clear storage", %{reason: reason, root: root})}
    end
  end

  defp resolve_path(root, path) when is_binary(path) do
    expanded_root = Path.expand(root)
    expanded_path = Path.expand(path, expanded_root)

    cond do
      path == "" ->
        {:error, Error.invalid_argument("invalid storage path", %{path: path})}

      not path_within_root?(expanded_root, expanded_path) ->
        {:error, Error.invalid_argument("invalid storage path", %{path: path})}

      true ->
        {:ok, expanded_path}
    end
  end

  defp resolve_path(_root, path) do
    {:error, Error.invalid_argument("invalid storage path", %{path: path})}
  end

  defp path_within_root?(root, path) do
    path == root or String.starts_with?(path, root <> "/")
  end
end

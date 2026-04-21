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

    with :ok <- validate_path(path),
         :ok <- ensure_path_within_root(expanded_root, expanded_path, path),
         :ok <- ensure_symlink_free_path(expanded_root, expanded_path, path) do
      {:ok, expanded_path}
    end
  end

  defp resolve_path(_root, path) do
    {:error, Error.invalid_argument("invalid storage path", %{path: path})}
  end

  defp validate_path(""),
    do: {:error, Error.invalid_argument("invalid storage path", %{path: ""})}

  defp validate_path(_path), do: :ok

  defp ensure_path_within_root(root, path, original_path) do
    if path_within_root?(root, path) do
      :ok
    else
      {:error, Error.invalid_argument("invalid storage path", %{path: original_path})}
    end
  end

  defp ensure_symlink_free_path(root, path, original_path) do
    segments =
      case Path.relative_to(path, root) do
        "." -> []
        relative -> Path.split(relative)
      end

    walk_path_segments(root, segments, original_path)
  end

  defp path_within_root?(root, path) do
    path == root or String.starts_with?(path, root <> "/")
  end

  defp walk_path_segments(_current, [], _original_path), do: :ok

  defp walk_path_segments(current, [segment | rest], original_path) do
    next = Path.join(current, segment)

    case File.lstat(next) do
      {:ok, %File.Stat{type: :symlink}} ->
        {:error, Error.invalid_argument("invalid storage path", %{path: original_path})}

      {:ok, _stat} ->
        walk_path_segments(next, rest, original_path)

      {:error, :enoent} ->
        :ok

      {:error, _reason} ->
        :ok
    end
  end
end

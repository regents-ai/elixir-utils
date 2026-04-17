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
        {:error, Error.internal("failed to initialize storage", %{reason: reason, root: root})}
    end
  end

  @spec list_files(t()) :: {:ok, [Path.t()]} | {:error, Error.t()}
  def list_files(%__MODULE__{root: root}) do
    case File.ls(root) do
      {:ok, files} ->
        {:ok, Enum.map(files, &Path.join(root, &1))}

      {:error, reason} ->
        {:error, Error.not_found("storage root not found", %{reason: reason, root: root})}
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
    {:ok, File.exists?(Path.join(root, path))}
  end

  @spec delete_file(t(), Path.t()) :: {:ok, boolean()} | {:error, Error.t()}
  def delete_file(%__MODULE__{root: root}, path) do
    full = Path.join(root, path)

    case File.rm(full) do
      :ok ->
        {:ok, true}

      {:error, :enoent} ->
        {:ok, false}

      {:error, reason} ->
        {:error, Error.internal("failed to delete file", %{reason: reason, path: full})}
    end
  end

  @spec export_db(t(), Path.t()) :: {:ok, binary()} | {:error, Error.t()}
  def export_db(%__MODULE__{root: root}, path) do
    full = Path.join(root, path)

    case File.read(full) do
      {:ok, data} ->
        {:ok, data}

      {:error, reason} ->
        {:error, Error.not_found("database not found", %{reason: reason, path: full})}
    end
  end

  @spec import_db(t(), Path.t(), binary()) :: :ok | {:error, Error.t()}
  def import_db(%__MODULE__{root: root}, path, data) when is_binary(data) do
    full = Path.join(root, path)

    File.write(full, data)
    |> case do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, Error.internal("failed to import database", %{reason: reason, path: full})}
    end
  end

  @spec clear_all(t()) :: :ok | {:error, Error.t()}
  def clear_all(%__MODULE__{root: root}) do
    case File.rm_rf(root) do
      {:ok, _} ->
        File.mkdir_p(root)

      {:error, reason, _} ->
        {:error, Error.internal("failed to clear storage", %{reason: reason, root: root})}
    end
  end
end

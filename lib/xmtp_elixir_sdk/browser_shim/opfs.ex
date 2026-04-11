defmodule XmtpElixirSdk.BrowserShim.Opfs do
  @moduledoc """
  Canonical request builders for the browser-only OPFS adapter.

  The Elixir SDK owns the contract, while the browser shim owns the actual
  file-system bridge.
  """

  alias XmtpElixirSdk.BrowserShim

  defstruct enable_logging: false

  @type t :: %__MODULE__{
          enable_logging: boolean()
        }

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      enable_logging: Keyword.get(opts, :enable_logging, false)
    }
  end

  @spec init_request(t()) :: XmtpElixirSdk.BrowserShim.Action.Request.t()
  def init_request(%__MODULE__{enable_logging: enable_logging}) do
    BrowserShim.request("opfs.init", %{enableLogging: enable_logging})
  end

  @spec list_files_request() :: XmtpElixirSdk.BrowserShim.Action.Request.t()
  def list_files_request do
    BrowserShim.request("opfs.listFiles")
  end

  @spec file_count_request() :: XmtpElixirSdk.BrowserShim.Action.Request.t()
  def file_count_request do
    BrowserShim.request("opfs.fileCount")
  end

  @spec pool_capacity_request() :: XmtpElixirSdk.BrowserShim.Action.Request.t()
  def pool_capacity_request do
    BrowserShim.request("opfs.poolCapacity")
  end

  @spec file_exists_request(String.t()) :: XmtpElixirSdk.BrowserShim.Action.Request.t()
  def file_exists_request(path) when is_binary(path) do
    BrowserShim.request("opfs.fileExists", %{path: path})
  end

  @spec delete_file_request(String.t()) :: XmtpElixirSdk.BrowserShim.Action.Request.t()
  def delete_file_request(path) when is_binary(path) do
    BrowserShim.request("opfs.deleteFile", %{path: path})
  end

  @spec export_db_request(String.t()) :: XmtpElixirSdk.BrowserShim.Action.Request.t()
  def export_db_request(path) when is_binary(path) do
    BrowserShim.request("opfs.exportDb", %{path: path})
  end

  @spec import_db_request(String.t(), binary()) :: XmtpElixirSdk.BrowserShim.Action.Request.t()
  def import_db_request(path, data) when is_binary(path) and is_binary(data) do
    BrowserShim.request("opfs.importDb", %{path: path, data: data})
  end

  @spec clear_all_request() :: XmtpElixirSdk.BrowserShim.Action.Request.t()
  def clear_all_request do
    BrowserShim.request("opfs.clearAll")
  end
end

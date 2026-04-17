defmodule XmtpElixirSdk.BrowserShim.Opfs do
  @moduledoc """
  Request builders for browser-managed storage operations.

  Use these helpers when your browser runtime is responsible for OPFS access and
  you want Elixir and the browser to agree on one stable request format.

  This module only builds request envelopes. It does not perform file I/O by
  itself.
  """

  alias XmtpElixirSdk.BrowserShim

  defstruct enable_logging: false

  @type t :: %__MODULE__{
          enable_logging: boolean()
        }

  @doc """
  Create an OPFS request builder configuration.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      enable_logging: Keyword.get(opts, :enable_logging, false)
    }
  end

  @doc """
  Build the OPFS initialization request.
  """
  @spec init_request(t()) :: XmtpElixirSdk.BrowserShim.Action.Request.t()
  def init_request(%__MODULE__{enable_logging: enable_logging}) do
    BrowserShim.request("opfs.init", %{enableLogging: enable_logging})
  end

  @doc """
  Build a request to list OPFS files.
  """
  @spec list_files_request() :: XmtpElixirSdk.BrowserShim.Action.Request.t()
  def list_files_request do
    BrowserShim.request("opfs.listFiles")
  end

  @doc """
  Build a request to count files in OPFS.
  """
  @spec file_count_request() :: XmtpElixirSdk.BrowserShim.Action.Request.t()
  def file_count_request do
    BrowserShim.request("opfs.fileCount")
  end

  @doc """
  Build a request to inspect OPFS pool capacity.
  """
  @spec pool_capacity_request() :: XmtpElixirSdk.BrowserShim.Action.Request.t()
  def pool_capacity_request do
    BrowserShim.request("opfs.poolCapacity")
  end

  @doc """
  Build a request to check whether a file exists in OPFS.
  """
  @spec file_exists_request(String.t()) :: XmtpElixirSdk.BrowserShim.Action.Request.t()
  def file_exists_request(path) when is_binary(path) do
    BrowserShim.request("opfs.fileExists", %{path: path})
  end

  @doc """
  Build a request to delete a file from OPFS.
  """
  @spec delete_file_request(String.t()) :: XmtpElixirSdk.BrowserShim.Action.Request.t()
  def delete_file_request(path) when is_binary(path) do
    BrowserShim.request("opfs.deleteFile", %{path: path})
  end

  @doc """
  Build a request to export a database file from OPFS.
  """
  @spec export_db_request(String.t()) :: XmtpElixirSdk.BrowserShim.Action.Request.t()
  def export_db_request(path) when is_binary(path) do
    BrowserShim.request("opfs.exportDb", %{path: path})
  end

  @doc """
  Build a request to import a database file into OPFS.
  """
  @spec import_db_request(String.t(), binary()) :: XmtpElixirSdk.BrowserShim.Action.Request.t()
  def import_db_request(path, data) when is_binary(path) and is_binary(data) do
    BrowserShim.request("opfs.importDb", %{path: path, data: data})
  end

  @doc """
  Build a request to clear all OPFS-managed SDK files.
  """
  @spec clear_all_request() :: XmtpElixirSdk.BrowserShim.Action.Request.t()
  def clear_all_request do
    BrowserShim.request("opfs.clearAll")
  end
end

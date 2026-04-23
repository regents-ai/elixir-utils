defmodule XmtpElixirSdk.Sync do
  @moduledoc """
  Archive, restore, and device-sync operations.

  This module is for exporting conversation state, importing it somewhere else,
  and coordinating sync between installations.

  Reach for it when you need to:

  - build an archive blob
  - inspect archive metadata
  - import an archive
  - discover available archives
  - request or apply device sync
  """

  alias XmtpElixirSdk.Client
  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Internal.{ConversationServer, SyncServer}
  alias XmtpElixirSdk.Types

  @spec send_sync_request(Client.t(), Types.ArchiveOptions.t(), String.t()) ::
          {:ok, :ok} | {:error, Error.t()}
  def send_sync_request(%Client{} = client, options \\ %Types.ArchiveOptions{}, server_url \\ nil) do
    SyncServer.send_sync_request(
      client,
      options,
      server_url || Types.history_sync_url(client.env || :dev)
    )

    {:ok, :ok}
  end

  @spec send_sync_archive(Client.t(), String.t(), Types.ArchiveOptions.t(), String.t()) ::
          {:ok, :ok} | {:error, Error.t()}
  def send_sync_archive(
        %Client{} = client,
        pin,
        options \\ %Types.ArchiveOptions{},
        server_url \\ nil
      ) do
    with {:ok, conversations} <- ConversationServer.member_conversations(client) do
      :ok =
        SyncServer.send_sync_archive(
          client,
          pin,
          options,
          server_url || Types.history_sync_url(client.env || :dev),
          conversations
        )

      {:ok, :ok}
    end
  end

  @spec process_sync_archive(Client.t(), String.t() | nil) :: {:ok, :ok} | {:error, Error.t()}
  def process_sync_archive(%Client{} = client, archive_pin \\ nil) do
    with {:ok, conversations} <- SyncServer.process_sync_archive(client, archive_pin) do
      :ok = ConversationServer.import_conversations(client, conversations)
      {:ok, :ok}
    end
  end

  @spec list_available_archives(Client.t(), non_neg_integer()) ::
          {:ok, [Types.AvailableArchiveInfo.t()]} | {:error, Error.t()}
  def list_available_archives(%Client{} = client, days_cutoff) do
    SyncServer.list_available_archives(client, days_cutoff)
  end

  @spec create_archive(Client.t(), binary(), Types.ArchiveOptions.t()) ::
          {:ok, binary()} | {:error, Error.t()}
  def create_archive(%Client{} = client, key, opts \\ %Types.ArchiveOptions{}) do
    with {:ok, conversations} <- ConversationServer.member_conversations(client) do
      SyncServer.create_archive(client, key, opts, conversations)
    end
  end

  @spec import_archive(Client.t(), binary(), binary()) :: {:ok, :ok} | {:error, Error.t()}
  def import_archive(%Client{} = client, data, key) do
    with {:ok, conversations} <- SyncServer.import_archive(client, data, key) do
      :ok = ConversationServer.import_conversations(client, conversations)
      {:ok, :ok}
    end
  end

  @spec archive_metadata(Client.t(), binary(), binary()) ::
          {:ok, Types.ArchiveMetadata.t()} | {:error, Error.t()}
  def archive_metadata(%Client{} = client, data, key) do
    SyncServer.archive_metadata(client, data, key)
  end

  @spec sync_all_device_sync_groups(Client.t()) ::
          {:ok, Types.GroupSyncSummary.t()} | {:error, Error.t()}
  def sync_all_device_sync_groups(%Client{} = client) do
    with {:ok, conversations} <- ConversationServer.member_conversations(client),
         {:ok, summary, imported} <- SyncServer.sync_all_device_sync_groups(client, conversations) do
      :ok = ConversationServer.import_conversations(client, imported)
      {:ok, summary}
    end
  end
end

defmodule XmtpElixirSdk.Internal.SyncServer do
  @moduledoc false

  use GenServer

  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Events
  alias XmtpElixirSdk.Internal.Names
  alias XmtpElixirSdk.Types

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    runtime = Keyword.fetch!(opts, :runtime)
    GenServer.start_link(__MODULE__, %{runtime: runtime}, name: name)
  end

  @spec reset!(XmtpElixirSdk.Runtime.t() | XmtpElixirSdk.Client.t() | atom()) :: :ok
  def reset!(runtime), do: GenServer.call(Names.sync_server(runtime), :reset)

  @spec send_sync_request(XmtpElixirSdk.Client.t(), Types.ArchiveOptions.t(), String.t()) :: :ok
  def send_sync_request(client, options, server_url) do
    GenServer.call(Names.sync_server(client), {:send_sync_request, client, options, server_url})
  end

  @spec send_sync_archive(
          XmtpElixirSdk.Client.t(),
          String.t(),
          Types.ArchiveOptions.t(),
          String.t(),
          list()
        ) ::
          :ok
  def send_sync_archive(client, pin, options, server_url, conversations) do
    GenServer.call(
      Names.sync_server(client),
      {:send_sync_archive, client, pin, options, server_url, conversations}
    )
  end

  @spec process_sync_archive(XmtpElixirSdk.Client.t(), String.t() | nil) ::
          {:ok, [term()]} | {:error, Error.t()}
  def process_sync_archive(client, archive_pin) do
    GenServer.call(Names.sync_server(client), {:process_sync_archive, client, archive_pin})
  end

  @spec list_available_archives(XmtpElixirSdk.Client.t(), non_neg_integer()) ::
          {:ok, [Types.AvailableArchiveInfo.t()]}
  def list_available_archives(client, days_cutoff) do
    GenServer.call(Names.sync_server(client), {:list_available_archives, client, days_cutoff})
  end

  @spec create_archive(XmtpElixirSdk.Client.t(), binary(), Types.ArchiveOptions.t(), list()) ::
          {:ok, binary()}
  def create_archive(client, key, opts, conversations) do
    GenServer.call(Names.sync_server(client), {:create_archive, client, key, opts, conversations})
  end

  @spec import_archive(XmtpElixirSdk.Client.t(), binary(), binary()) ::
          {:ok, [term()]} | {:error, Error.t()}
  def import_archive(client, data, key) do
    GenServer.call(Names.sync_server(client), {:import_archive, client, data, key})
  end

  @spec archive_metadata(XmtpElixirSdk.Client.t(), binary(), binary()) ::
          {:ok, Types.ArchiveMetadata.t()} | {:error, Error.t()}
  def archive_metadata(client, data, key) do
    GenServer.call(Names.sync_server(client), {:archive_metadata, client, data, key})
  end

  @spec sync_all_device_sync_groups(XmtpElixirSdk.Client.t(), list()) ::
          {:ok, Types.GroupSyncSummary.t(), [term()]}
  def sync_all_device_sync_groups(client, conversations) do
    GenServer.call(
      Names.sync_server(client),
      {:sync_all_device_sync_groups, client, conversations}
    )
  end

  @impl true
  def init(%{runtime: runtime}) do
    {:ok, %{runtime: runtime, archives: %{}, sync_requests: []}}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    {:reply, :ok, %{state | archives: %{}, sync_requests: []}}
  end

  def handle_call({:send_sync_request, client, options, server_url}, _from, state) do
    request = %{
      inbox_id: client.inbox_id,
      requester_installation_id: client.installation_id,
      options: options,
      server_url: server_url
    }

    {:reply, :ok, %{state | sync_requests: state.sync_requests ++ [request]}}
  end

  def handle_call(
        {:send_sync_archive, client, pin, options, server_url, conversations},
        _from,
        state
      ) do
    archive = build_archive_payload(client, pin, options, server_url, conversations)
    {:reply, :ok, %{state | archives: Map.put(state.archives, archive.pin, archive)}}
  end

  def handle_call({:process_sync_archive, client, archive_pin}, _from, state) do
    case find_archive(state, client, archive_pin) do
      nil ->
        {:reply, {:error, Error.not_found("archive not found", %{archive_pin: archive_pin})},
         state}

      archive ->
        Events.emit(state.runtime, {:conversations, client.id}, %Events.SyncApplied{
          archive_pin: archive.pin,
          conversation_count: length(archive.conversations)
        })

        {:reply, {:ok, archive.conversations}, state}
    end
  end

  def handle_call({:list_available_archives, client, days_cutoff}, _from, state) do
    now = System.system_time(:nanosecond)
    cutoff_ns = now - System.convert_time_unit(days_cutoff * 24 * 60 * 60, :second, :nanosecond)

    archives =
      state.archives
      |> Map.values()
      |> Enum.filter(&(&1.created_at_ns >= cutoff_ns and &1.inbox_id == client.inbox_id))
      |> Enum.map(fn archive ->
        %Types.AvailableArchiveInfo{
          pin: archive.pin,
          server_url: archive.server_url,
          created_at_ns: archive.created_at_ns,
          item_count: archive.item_count
        }
      end)

    {:reply, {:ok, archives}, state}
  end

  def handle_call({:create_archive, _client, key, _opts, _conversations}, _from, state)
      when not is_binary(key) do
    {:reply, {:error, Error.invalid_argument("invalid archive key", %{})}, state}
  end

  def handle_call({:create_archive, client, key, opts, conversations}, _from, state) do
    archive =
      build_archive_payload(
        client,
        nil,
        opts,
        Types.history_sync_url(client.env || :dev),
        conversations
      )

    {:reply, encode_archive(archive, key), state}
  end

  def handle_call({:import_archive, client, data, key}, _from, state) do
    case decode_archive(data, key) do
      {:ok, archive} when archive.inbox_id == client.inbox_id ->
        Events.emit(state.runtime, {:conversations, client.id}, %Events.SyncApplied{
          archive_pin: archive.pin,
          conversation_count: length(archive.conversations)
        })

        {:reply, {:ok, archive.conversations}, state}

      {:ok, _archive} ->
        {:reply, {:error, Error.not_found("archive not found", %{})}, state}

      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  def handle_call({:archive_metadata, client, data, key}, _from, state) do
    case decode_archive(data, key) do
      {:ok, archive} when archive.inbox_id == client.inbox_id ->
        {:reply,
         {:ok,
          %Types.ArchiveMetadata{
            pin: archive.pin,
            server_url: archive.server_url,
            created_at_ns: archive.created_at_ns,
            item_count: archive.item_count,
            options: archive.options
          }}, state}

      {:ok, _archive} ->
        {:reply, {:error, Error.not_found("archive not found", %{})}, state}

      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  def handle_call({:sync_all_device_sync_groups, client, conversations}, _from, state) do
    {matching_requests, remaining_requests} =
      Enum.split_with(state.sync_requests, fn request ->
        request.inbox_id == client.inbox_id and
          request.requester_installation_id != client.installation_id
      end)

    next_state =
      Enum.reduce(matching_requests, %{state | sync_requests: remaining_requests}, fn request,
                                                                                      acc ->
        archive =
          build_archive_payload(client, nil, request.options, request.server_url, conversations)

        %{acc | archives: Map.put(acc.archives, archive.pin, archive)}
      end)

    applicable_archives =
      next_state.archives
      |> Map.values()
      |> Enum.filter(fn archive ->
        archive.inbox_id == client.inbox_id and
          archive.creator_installation_id != client.installation_id
      end)

    summary = %Types.GroupSyncSummary{
      synced: length(matching_requests) + length(applicable_archives),
      eligible: length(applicable_archives)
    }

    imported =
      applicable_archives
      |> Enum.flat_map(& &1.conversations)
      |> Enum.uniq_by(& &1.id)

    {:reply, {:ok, summary, imported}, next_state}
  end

  defp find_archive(state, client, nil) do
    state.archives
    |> Map.values()
    |> Enum.filter(fn archive ->
      archive.inbox_id == client.inbox_id and
        archive.creator_installation_id != client.installation_id
    end)
    |> Enum.max_by(& &1.created_at_ns, fn -> nil end)
  end

  defp find_archive(state, client, archive_pin) when is_binary(archive_pin) do
    case Map.get(state.archives, archive_pin) do
      %{inbox_id: inbox_id, creator_installation_id: creator_installation_id} = archive
      when inbox_id == client.inbox_id and creator_installation_id != client.installation_id ->
        archive

      _ ->
        nil
    end
  end

  defp build_archive_payload(client, pin, options, server_url, conversations) do
    %{
      pin: pin || "archive-#{System.unique_integer([:positive])}",
      inbox_id: client.inbox_id,
      creator_installation_id: client.installation_id,
      server_url: server_url,
      created_at_ns: System.system_time(:nanosecond),
      item_count: length(conversations),
      options: options,
      conversations: conversations
    }
  end

  defp encode_archive(archive, key) when is_binary(key) do
    nonce = :crypto.strong_rand_bytes(12)
    plaintext = :erlang.term_to_binary(archive)
    secret = archive_secret(key)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, secret, nonce, plaintext, "", 16, true)

    {:ok, :erlang.term_to_binary(%{v: 1, nonce: nonce, ciphertext: ciphertext, tag: tag})}
  end

  defp encode_archive(_archive, _key),
    do: {:error, Error.invalid_argument("invalid archive key", %{})}

  defp decode_archive(data, key) when is_binary(data) and is_binary(key) do
    with {:ok, envelope} <- decode_archive_envelope(data),
         {:ok, plaintext} <- decrypt_archive(envelope, key),
         {:ok, archive} <- decode_archive_term(plaintext) do
      validate_archive(archive)
    end
  end

  defp decode_archive(_data, _key),
    do: {:error, Error.invalid_argument("invalid archive data", %{})}

  defp decode_archive_envelope(data) do
    case :erlang.binary_to_term(data, [:safe]) do
      %{v: 1, nonce: nonce, ciphertext: ciphertext, tag: tag} = envelope
      when is_binary(nonce) and is_binary(ciphertext) and is_binary(tag) ->
        {:ok, envelope}

      _ ->
        {:error, Error.invalid_argument("invalid archive data", %{})}
    end
  rescue
    _ -> {:error, Error.invalid_argument("invalid archive data", %{})}
  end

  defp decrypt_archive(%{nonce: nonce, ciphertext: ciphertext, tag: tag}, key) do
    case :crypto.crypto_one_time_aead(
           :aes_256_gcm,
           archive_secret(key),
           nonce,
           ciphertext,
           "",
           tag,
           false
         ) do
      plaintext when is_binary(plaintext) -> {:ok, plaintext}
      :error -> {:error, Error.invalid_argument("invalid archive data", %{})}
    end
  rescue
    _ -> {:error, Error.invalid_argument("invalid archive data", %{})}
  end

  defp decode_archive_term(plaintext) do
    case :erlang.binary_to_term(plaintext, [:safe]) do
      archive when is_map(archive) -> {:ok, archive}
      _ -> {:error, Error.invalid_argument("invalid archive data", %{})}
    end
  rescue
    _ -> {:error, Error.invalid_argument("invalid archive data", %{})}
  end

  defp archive_secret(key), do: :crypto.hash(:sha256, key)

  defp validate_archive(
         %{
           pin: pin,
           inbox_id: inbox_id,
           creator_installation_id: creator_installation_id,
           server_url: server_url,
           created_at_ns: created_at_ns,
           item_count: item_count,
           options: %Types.ArchiveOptions{} = options,
           conversations: conversations
         } = archive
       )
       when is_binary(pin) and is_binary(inbox_id) and is_binary(creator_installation_id) and
              is_binary(server_url) and is_integer(created_at_ns) and created_at_ns >= 0 and
              is_integer(item_count) and item_count >= 0 and is_list(conversations) do
    if item_count == length(conversations) do
      {:ok, %{archive | options: options, conversations: conversations}}
    else
      {:error, Error.invalid_argument("invalid archive data", %{})}
    end
  end

  defp validate_archive(_archive),
    do: {:error, Error.invalid_argument("invalid archive data", %{})}
end

defmodule XmtpElixirSdk.Conversations do
  @moduledoc """
  Find, create, and list conversations.

  This module is the usual starting point after you have a client.

  Common tasks:

  - fetch a conversation by id
  - list direct messages or groups
  - create a new DM
  - create a new group
  - create conversations from identifiers instead of raw inbox ids

  Returned conversation structs are intended to be passed into
  `XmtpElixirSdk.Messages`, `XmtpElixirSdk.Groups`, and related modules.
  """

  alias XmtpElixirSdk.Client
  alias XmtpElixirSdk.CodecRegistry
  alias XmtpElixirSdk.Conversation
  alias XmtpElixirSdk.DecodedMessage
  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Internal.{ConversationServer, IdentityServer}
  alias XmtpElixirSdk.Types

  @spec topic(Client.t()) :: String.t() | nil
  def topic(%Client{installation_id: nil}), do: nil
  def topic(%Client{} = client), do: "/xmtp/mls/1/w-#{client.installation_id}/proto"

  @spec sync(Client.t()) :: {:ok, Types.SyncResult.t()} | {:error, Error.t()}
  def sync(%Client{} = client), do: ConversationServer.sync_conversations(client, [])

  @spec sync_all(Client.t(), [Types.consent_state()] | nil) ::
          {:ok, Types.SyncResult.t()} | {:error, Error.t()}
  def sync_all(%Client{} = client, consent_states \\ []) do
    ConversationServer.sync_conversations(client, consent_states || [])
  end

  @spec get_by_id(Client.t(), String.t()) ::
          {:ok, Conversation.t() | nil} | {:error, Error.t()}
  def get_by_id(%Client{} = client, id) do
    with {:ok, conversation} <- ConversationServer.get_conversation_by_id(client, id) do
      {:ok, wrap_conversation(client, conversation)}
    end
  end

  @spec get_message_by_id(Client.t(), String.t(), CodecRegistry.t()) ::
          {:ok, DecodedMessage.t() | nil} | {:error, Error.t()}
  def get_message_by_id(%Client{} = client, id, registry \\ CodecRegistry.new()) do
    XmtpElixirSdk.Messages.decoded_by_id(client, id, registry)
  end

  @spec get_dm_by_inbox_id(Client.t(), String.t()) ::
          {:ok, Conversation.t() | nil} | {:error, Error.t()}
  def get_dm_by_inbox_id(%Client{} = client, inbox_id) do
    with {:ok, conversations} <-
           ConversationServer.list_conversations(client, %Types.ListConversationsOptions{
             conversation_type: :dm
           }) do
      conversation =
        Enum.find(conversations, fn conversation ->
          Enum.any?(conversation.members, &(&1.inbox_id == inbox_id))
        end)

      {:ok, wrap_conversation(client, conversation)}
    end
  end

  @spec fetch_dm_by_identifier(Client.t(), Types.Identifier.t()) ::
          {:ok, Conversation.t() | nil} | {:error, Error.t()}
  def fetch_dm_by_identifier(%Client{} = client, identifier) do
    case IdentityServer.get_inbox_id_for_identifier(client.runtime, identifier) do
      {:ok, inbox_id} -> get_dm_by_inbox_id(client, inbox_id)
      {:error, %Error{kind: :not_found}} -> {:ok, nil}
      {:error, error} -> {:error, error}
    end
  end

  @spec list(Client.t(), Types.ListConversationsOptions.t() | nil) ::
          {:ok, [Conversation.t()]} | {:error, Error.t()}
  def list(%Client{} = client, opts \\ %Types.ListConversationsOptions{}) do
    with {:ok, conversations} <- ConversationServer.list_conversations(client, opts) do
      {:ok, Enum.map(conversations, &Conversation.from_record(client, &1))}
    end
  end

  @spec list_dms(Client.t(), Types.ListConversationsOptions.t() | nil) ::
          {:ok, [Conversation.t()]} | {:error, Error.t()}
  def list_dms(%Client{} = client, opts \\ %Types.ListConversationsOptions{}) do
    list(client, %{opts | conversation_type: :dm})
  end

  @spec list_groups(Client.t(), Types.ListConversationsOptions.t() | nil) ::
          {:ok, [Conversation.t()]} | {:error, Error.t()}
  def list_groups(%Client{} = client, opts \\ %Types.ListConversationsOptions{}) do
    list(client, %{opts | conversation_type: :group})
  end

  @spec create_group(Client.t(), [String.t()], Types.CreateGroupOptions.t() | nil) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def create_group(%Client{} = client, inbox_ids, opts \\ %Types.CreateGroupOptions{}) do
    with {:ok, conversation} <- ConversationServer.create_group(client, inbox_ids, opts) do
      {:ok, Conversation.from_record(client, conversation)}
    end
  end

  @spec create_group_with_identifiers(
          Client.t(),
          [Types.Identifier.t()],
          Types.CreateGroupOptions.t() | nil
        ) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def create_group_with_identifiers(
        %Client{} = client,
        identifiers,
        opts \\ %Types.CreateGroupOptions{}
      ) do
    with {:ok, inbox_ids} <- resolve_inbox_ids(client, identifiers) do
      create_group(client, inbox_ids, opts)
    end
  end

  @spec create_group_optimistic(Client.t(), Types.CreateGroupOptions.t() | nil) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def create_group_optimistic(%Client{} = client, opts \\ %Types.CreateGroupOptions{}) do
    create_group(client, [], opts)
  end

  @spec create_dm(Client.t(), String.t(), Types.CreateDmOptions.t() | nil) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def create_dm(%Client{} = client, inbox_id, opts \\ %Types.CreateDmOptions{}) do
    with {:ok, conversation} <- ConversationServer.create_dm(client, inbox_id, opts) do
      {:ok, Conversation.from_record(client, conversation)}
    end
  end

  @spec create_dm_with_identifier(
          Client.t(),
          Types.Identifier.t(),
          Types.CreateDmOptions.t() | nil
        ) ::
          {:ok, Conversation.t()} | {:error, Error.t()}
  def create_dm_with_identifier(%Client{} = client, identifier, opts \\ %Types.CreateDmOptions{}) do
    with {:ok, inbox_id} <- resolve_inbox_id(client, identifier) do
      create_dm(client, inbox_id, opts)
    end
  end

  @spec hmac_keys(Client.t()) :: {:ok, [Types.HmacKeyEntry.t()]} | {:error, Error.t()}
  def hmac_keys(%Client{} = client), do: ConversationServer.hmac_keys(client, :all)

  @spec duplicate_dms(Conversation.t()) :: {:ok, [Conversation.t()]} | {:error, Error.t()}
  def duplicate_dms(%Conversation{client: client, id: id}) do
    with {:ok, conversations} <- ConversationServer.duplicate_dms(client, id) do
      {:ok, Enum.map(conversations, &Conversation.from_record(client, &1))}
    end
  end

  defp wrap_conversation(_client, nil), do: nil
  defp wrap_conversation(client, conversation), do: Conversation.from_record(client, conversation)

  defp resolve_inbox_ids(client, identifiers) do
    identifiers
    |> Enum.reduce_while({:ok, []}, fn identifier, {:ok, acc} ->
      case resolve_inbox_id(client, identifier) do
        {:ok, inbox_id} -> {:cont, {:ok, [inbox_id | acc]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, inbox_ids} -> {:ok, Enum.reverse(inbox_ids)}
      other -> other
    end
  end

  defp resolve_inbox_id(%Client{} = client, %Types.Identifier{} = identifier) do
    IdentityServer.get_inbox_id_for_identifier(client.runtime, identifier)
  end
end

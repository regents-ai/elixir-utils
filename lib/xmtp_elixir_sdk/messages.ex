defmodule XmtpElixirSdk.Messages do
  @moduledoc """
  Message operations.
  """

  alias XmtpElixirSdk.CodecRegistry
  alias XmtpElixirSdk.Content
  alias XmtpElixirSdk.Conversation
  alias XmtpElixirSdk.DecodedMessage
  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Internal.ConversationServer
  alias XmtpElixirSdk.Types

  @spec get_by_id(XmtpElixirSdk.Client.t(), String.t()) ::
          {:ok, Types.Message.t() | nil} | {:error, Error.t()}
  def get_by_id(client, message_id), do: ConversationServer.get_message_by_id(client, message_id)

  @spec decoded_by_id(XmtpElixirSdk.Client.t(), String.t(), CodecRegistry.t()) ::
          {:ok, DecodedMessage.t() | nil} | {:error, Error.t()}
  def decoded_by_id(client, message_id, registry) do
    with {:ok, message} <- get_by_id(client, message_id) do
      {:ok, if(message, do: DecodedMessage.from_message(message, registry), else: nil)}
    end
  end

  @spec last_message(Conversation.t(), CodecRegistry.t()) ::
          {:ok, DecodedMessage.t() | nil} | {:error, Error.t()}
  def last_message(%Conversation{client: client, id: id}, registry \\ CodecRegistry.new()) do
    with {:ok, message} <- ConversationServer.conversation_last_message(client, id) do
      {:ok, if(message, do: DecodedMessage.from_message(message, registry), else: nil)}
    end
  end

  @spec send(Conversation.t(), term(), keyword()) :: {:ok, String.t()} | {:error, Error.t()}
  def send(%Conversation{client: client, id: id}, content, opts \\ []) do
    ConversationServer.send_message(client, id, content, opts)
  end

  @spec send_text(Conversation.t(), String.t(), boolean()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def send_text(conversation, text, is_optimistic \\ false),
    do: send(conversation, Content.encode_text(text), is_optimistic: is_optimistic)

  @spec send_markdown(Conversation.t(), String.t(), boolean()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def send_markdown(conversation, markdown, is_optimistic \\ false),
    do: send(conversation, Content.encode_markdown(markdown), is_optimistic: is_optimistic)

  @spec send_reaction(Conversation.t(), Content.Reaction.t(), boolean()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def send_reaction(conversation, reaction, is_optimistic \\ false),
    do: send(conversation, reaction, is_optimistic: is_optimistic)

  @spec send_read_receipt(Conversation.t(), boolean()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def send_read_receipt(conversation, is_optimistic \\ false),
    do: send(conversation, Content.encode_read_receipt(), is_optimistic: is_optimistic)

  @spec send_reply(Conversation.t(), Content.Reply.t(), boolean()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def send_reply(conversation, reply, is_optimistic \\ false),
    do: send(conversation, reply, is_optimistic: is_optimistic)

  @spec send_attachment(Conversation.t(), Content.Attachment.t(), boolean()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def send_attachment(conversation, attachment, is_optimistic \\ false),
    do: send(conversation, attachment, is_optimistic: is_optimistic)

  @spec send_remote_attachment(Conversation.t(), Content.RemoteAttachment.t(), boolean()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def send_remote_attachment(conversation, attachment, is_optimistic \\ false),
    do: send(conversation, attachment, is_optimistic: is_optimistic)

  @spec send_multi_remote_attachment(Conversation.t(), Content.MultiRemoteAttachment.t(), boolean()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def send_multi_remote_attachment(conversation, attachment, is_optimistic \\ false),
    do: send(conversation, attachment, is_optimistic: is_optimistic)

  @spec send_transaction_reference(Conversation.t(), Content.TransactionReference.t(), boolean()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def send_transaction_reference(conversation, transaction_reference, is_optimistic \\ false),
    do: send(conversation, transaction_reference, is_optimistic: is_optimistic)

  @spec send_wallet_send_calls(Conversation.t(), Content.WalletSendCalls.t(), boolean()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def send_wallet_send_calls(conversation, wallet_send_calls, is_optimistic \\ false),
    do: send(conversation, wallet_send_calls, is_optimistic: is_optimistic)

  @spec send_actions(Conversation.t(), Content.Actions.t(), boolean()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def send_actions(conversation, actions, is_optimistic \\ false),
    do: send(conversation, actions, is_optimistic: is_optimistic)

  @spec send_intent(Conversation.t(), Content.Intent.t(), boolean()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def send_intent(conversation, intent, is_optimistic \\ false),
    do: send(conversation, intent, is_optimistic: is_optimistic)

  @spec send_text_reply(Conversation.t(), String.t(), String.t(), boolean()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def send_text_reply(conversation, reference_id, text, is_optimistic \\ false),
    do: send_reply(conversation, Content.encode_text_reply(reference_id, text), is_optimistic)

  @spec publish(Conversation.t()) :: :ok | {:error, Error.t()}
  def publish(%Conversation{client: client, id: id}), do: ConversationServer.publish_messages(client, id)

  @spec list(Conversation.t(), Types.ListMessagesOptions.t() | nil, CodecRegistry.t()) ::
          {:ok, [DecodedMessage.t()]} | {:error, Error.t()}
  def list(%Conversation{client: client, id: id}, opts \\ %Types.ListMessagesOptions{}, registry \\ CodecRegistry.new()) do
    with {:ok, messages} <- ConversationServer.list_messages(client, id, opts) do
      {:ok, Enum.map(messages, &DecodedMessage.from_message(&1, registry))}
    end
  end

  @spec count(Conversation.t(), Types.ListMessagesOptions.t() | nil) ::
          {:ok, non_neg_integer()} | {:error, Error.t()}
  def count(%Conversation{client: client, id: id}, opts \\ %Types.ListMessagesOptions{}) do
    ConversationServer.count_messages(client, id, opts)
  end

  @spec process_streamed_message(Conversation.t(), binary()) ::
          {:ok, [Types.Message.t()]} | {:error, Error.t()}
  def process_streamed_message(%Conversation{client: client, id: id}, envelope_bytes) do
    ConversationServer.process_streamed_message(client, id, envelope_bytes)
  end
end

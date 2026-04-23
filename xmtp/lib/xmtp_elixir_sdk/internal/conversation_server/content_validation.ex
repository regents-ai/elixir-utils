defmodule XmtpElixirSdk.Internal.ConversationServer.ContentValidation do
  @moduledoc false

  alias XmtpElixirSdk.Content
  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Types.Message

  def validate(%Content.WalletSendCalls{calls: calls}) do
    Enum.reduce_while(calls, :ok, fn call, _acc ->
      case validate_wallet_call(call) do
        :ok -> {:cont, :ok}
        {:error, %Error{} = error} -> {:halt, {:error, error}}
      end
    end)
  end

  def validate(_content), do: :ok

  def decode_streamed(envelope_bytes) when is_binary(envelope_bytes) do
    case :erlang.binary_to_term(envelope_bytes, [:safe]) do
      %Message{content: content} -> {:ok, content}
      %Content.Text{} = content -> {:ok, content}
      %Content.Markdown{} = content -> {:ok, content}
      %Content.Reaction{} = content -> {:ok, content}
      %Content.Reply{} = content -> {:ok, content}
      %Content.ReadReceipt{} = content -> {:ok, content}
      %Content.Attachment{} = content -> {:ok, content}
      %Content.RemoteAttachment{} = content -> {:ok, content}
      %Content.GroupUpdated{} = content -> {:ok, content}
      %Content.Actions{} = content -> {:ok, content}
      %Content.Intent{} = content -> {:ok, content}
      %Content.TransactionReference{} = content -> {:ok, content}
      %Content.WalletSendCalls{} = content -> {:ok, content}
      %Content.MultiRemoteAttachment{} = content -> {:ok, content}
      _ -> {:error, Error.invalid_argument("invalid streamed envelope", %{})}
    end
  rescue
    _ -> {:error, Error.invalid_argument("invalid streamed envelope", %{})}
  end

  defp validate_wallet_call(%Content.WalletCall{metadata: nil}), do: :ok

  defp validate_wallet_call(%Content.WalletCall{metadata: metadata}) when map_size(metadata) == 0,
    do: :ok

  defp validate_wallet_call(%Content.WalletCall{metadata: metadata}) do
    with :ok <- require_wallet_metadata_field(metadata, :description),
         :ok <- require_wallet_metadata_field(metadata, :transaction_type) do
      :ok
    end
  end

  defp validate_wallet_call(_other),
    do: {:error, Error.invalid_argument("wallet call must use the canonical shape", %{})}

  defp require_wallet_metadata_field(metadata, field) do
    if Map.has_key?(metadata, field) do
      :ok
    else
      {:error,
       Error.invalid_argument("wallet call metadata missing required field", %{field: field})}
    end
  end
end

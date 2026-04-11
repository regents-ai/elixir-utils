defmodule XmtpElixirSdk.Debug do
  @moduledoc """
  Debug and statistics operations.
  """

  alias XmtpElixirSdk.Client
  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Internal.{ConversationServer, StatsServer}
  alias XmtpElixirSdk.Types

  @spec api_statistics(Client.t()) :: {:ok, Types.ApiStats.t()} | {:error, Error.t()}
  def api_statistics(%Client{} = client), do: StatsServer.api_statistics(client)

  @spec api_identity_statistics(Client.t()) ::
          {:ok, Types.IdentityStats.t()} | {:error, Error.t()}
  def api_identity_statistics(%Client{} = client), do: StatsServer.api_identity_statistics(client)

  @spec api_aggregate_statistics(Client.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def api_aggregate_statistics(%Client{} = client), do: StatsServer.api_aggregate_statistics(client)

  @spec clear_all_statistics(Client.t()) :: :ok | {:error, Error.t()}
  def clear_all_statistics(%Client{} = client), do: StatsServer.clear_all_statistics(client)

  @spec conversation_info(Conversation.t()) ::
          {:ok, Types.ConversationDebugInfo.t()} | {:error, Error.t()}
  def conversation_info(%XmtpElixirSdk.Conversation{client: client, id: id}) do
    ConversationServer.conversation_debug_info(client, id)
  end
end

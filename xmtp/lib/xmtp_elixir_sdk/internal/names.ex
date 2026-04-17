defmodule XmtpElixirSdk.Internal.Names do
  @moduledoc false

  alias XmtpElixirSdk.Client
  alias XmtpElixirSdk.Conversation
  alias XmtpElixirSdk.Runtime

  @spec runtime_name(Runtime.t() | Client.t() | Conversation.t() | atom()) :: atom()
  def runtime_name(%Runtime{name: name}), do: name
  def runtime_name(%Client{runtime: runtime}), do: runtime
  def runtime_name(%Conversation{runtime: runtime}), do: runtime
  def runtime_name(name) when is_atom(name), do: name

  @spec identity_server(Runtime.t() | Client.t() | Conversation.t() | atom()) :: atom()
  def identity_server(runtime), do: Module.concat(runtime_name(runtime), IdentityServer)

  @spec conversation_server(Runtime.t() | Client.t() | Conversation.t() | atom()) :: atom()
  def conversation_server(runtime), do: Module.concat(runtime_name(runtime), ConversationServer)

  @spec sync_server(Runtime.t() | Client.t() | Conversation.t() | atom()) :: atom()
  def sync_server(runtime), do: Module.concat(runtime_name(runtime), SyncServer)

  @spec stats_server(Runtime.t() | Client.t() | Conversation.t() | atom()) :: atom()
  def stats_server(runtime), do: Module.concat(runtime_name(runtime), StatsServer)

  @spec registry(Runtime.t() | Client.t() | Conversation.t() | atom()) :: atom()
  def registry(runtime), do: Module.concat(runtime_name(runtime), Registry)
end

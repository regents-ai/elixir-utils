defmodule XmtpElixirSdk do
  @moduledoc """
  The main entrypoint for the XMTP Elixir SDK.

  If you are new to the SDK, start here. A typical flow looks like this:

  1. Start a runtime with `start_runtime/1`.
  2. Create or build a client with `create_client/3` or `build_client/3`.
  3. Open or create conversations through `XmtpElixirSdk.Conversations`.
  4. Send and read messages through `XmtpElixirSdk.Messages`.
  5. Manage group state through `XmtpElixirSdk.Groups`.

  The SDK is split into small modules on purpose:

  - `XmtpElixirSdk.Clients` handles identity and client lifecycle.
  - `XmtpElixirSdk.Conversations` handles finding and creating conversations.
  - `XmtpElixirSdk.Messages` handles sending, listing, and decoding messages.
  - `XmtpElixirSdk.Groups` handles group membership, roles, and group settings.
  - `XmtpElixirSdk.Preferences` handles consent and inbox-state operations.
  """

  alias XmtpElixirSdk.Client
  alias XmtpElixirSdk.Clients
  alias XmtpElixirSdk.Constants
  alias XmtpElixirSdk.Conversions
  alias XmtpElixirSdk.Date
  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Runtime
  alias XmtpElixirSdk.Types

  @spec start_runtime(keyword()) :: Supervisor.on_start()
  def start_runtime(opts), do: Runtime.start_link(opts)

  @spec runtime(atom()) :: Runtime.t()
  def runtime(name), do: Runtime.new(name)

  @spec create_client(Runtime.t() | atom(), Types.Identifier.t(), keyword()) ::
          {:ok, Client.t()} | {:error, Error.t()}
  def create_client(runtime, identifier, opts \\ []),
    do: Clients.create(runtime, identifier, opts)

  @spec build_client(Runtime.t() | atom(), Types.Identifier.t(), keyword()) ::
          {:ok, Client.t()} | {:error, Error.t()}
  def build_client(runtime, identifier, opts \\ []), do: Clients.build(runtime, identifier, opts)

  @spec generate_inbox_id(Types.Identifier.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, String.t()}
  def generate_inbox_id(identifier, kind, nonce \\ 1) do
    identifier = normalize_identifier(identifier)
    data = "#{identifier.identifier_kind}:#{identifier.identifier}|#{kind}|#{nonce}"
    {:ok, Base.encode16(:crypto.hash(:sha256, data), case: :lower) |> binary_part(0, 32)}
  end

  @spec get_inbox_id_for_identifier(Runtime.t() | atom(), Types.Identifier.t()) ::
          {:ok, String.t() | nil} | {:error, Error.t()}
  def get_inbox_id_for_identifier(runtime, identifier) do
    Clients.fetch_inbox_id_by_identifier(runtime, identifier)
  end

  @spec can_message(Runtime.t() | atom(), [Types.Identifier.t()]) ::
          {:ok, map()} | {:error, Error.t()}
  def can_message(runtime, identifiers), do: Clients.can_message(runtime, identifiers)

  @spec metadata_field_name(Types.metadata_field()) :: String.t()
  defdelegate metadata_field_name(field), to: Constants

  @spec metadata_field_from_name(String.t()) ::
          {:ok, Types.metadata_field()} | {:error, Error.t()}
  defdelegate metadata_field_from_name(name), to: Constants

  @spec api_urls() :: %{optional(Types.env()) => String.t()}
  defdelegate api_urls, to: Constants

  @spec history_sync_urls() :: %{optional(Types.env()) => String.t()}
  defdelegate history_sync_urls, to: Constants

  @spec to_safe_conversation(Types.Conversation.t()) :: Conversions.SafeConversation.t()
  defdelegate to_safe_conversation(conversation), to: Conversions

  @spec ns_to_datetime(non_neg_integer()) :: DateTime.t()
  defdelegate ns_to_datetime(ns), to: Date

  defp normalize_identifier(
         %Types.Identifier{identifier_kind: :ethereum, identifier: identifier} = value
       )
       when is_binary(identifier) do
    %Types.Identifier{value | identifier: identifier |> String.trim() |> String.downcase()}
  end

  defp normalize_identifier(%Types.Identifier{} = value), do: value
end

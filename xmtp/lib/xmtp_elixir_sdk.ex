defmodule XmtpElixirSdk do
  @moduledoc """
  Public entrypoint for the XMTP Elixir SDK.
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
  def create_client(runtime, identifier, opts \\ []), do: Clients.create(runtime, identifier, opts)

  @spec build_client(Runtime.t() | atom(), Types.Identifier.t(), keyword()) ::
          {:ok, Client.t()} | {:error, Error.t()}
  def build_client(runtime, identifier, opts \\ []), do: Clients.build(runtime, identifier, opts)

  @spec generate_inbox_id(Types.Identifier.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, String.t()}
  def generate_inbox_id(identifier, kind, nonce \\ 1) do
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
  def metadata_field_name(field), do: Constants.metadata_field_name(field)

  @spec metadata_field_from_name(String.t()) ::
          {:ok, Types.metadata_field()} | {:error, Error.t()}
  def metadata_field_from_name(name), do: Constants.metadata_field_from_name(name)

  @spec api_urls() :: %{optional(Types.env()) => String.t()}
  def api_urls, do: Constants.api_urls()

  @spec history_sync_urls() :: %{optional(Types.env()) => String.t()}
  def history_sync_urls, do: Constants.history_sync_urls()

  @spec to_safe_conversation(Types.Conversation.t()) :: Conversions.SafeConversation.t()
  def to_safe_conversation(conversation), do: Conversions.to_safe_conversation(conversation)

  @spec ns_to_datetime(non_neg_integer()) :: DateTime.t()
  def ns_to_datetime(ns), do: Date.ns_to_datetime(ns)
end

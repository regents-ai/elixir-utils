defmodule XmtpElixirSdk.Native do
  @moduledoc """
  Native-backed XMTP operations.

  These functions call the supervised `libxmtp` bridge for production protocol
  work. Use this module from server-side Phoenix code when the server owns the
  XMTP identity key, such as room relays, agents, and moderation workers.
  """

  alias XmtpElixirSdk.{Client, Conversation, Error}
  alias XmtpElixirSdk.Internal.Names

  @type runtime :: XmtpElixirSdk.Runtime.t() | atom()

  @typedoc """
  Native request error: a structured SDK error, or `:bridge_down` when the
  supervised native bridge process is not currently running.
  """
  @type error :: Error.t() | :bridge_down

  @spec libxmtp_version(runtime()) :: {:ok, String.t()} | {:error, error()}
  def libxmtp_version(runtime) do
    with {:ok, %{"version" => version}} <- request(runtime, "libxmtp_version") do
      {:ok, version}
    end
  end

  @spec create_client(runtime(), keyword()) :: {:ok, Client.t()} | {:error, error()}
  def create_client(runtime, opts) do
    runtime = Names.runtime_name(runtime)

    with {:ok, record} <- request(runtime, "create_client", native_client_params(opts)) do
      {:ok, Client.from_native_record(runtime, record, opts)}
    end
  end

  @spec build_existing_client(runtime(), String.t(), keyword()) ::
          {:ok, Client.t()} | {:error, error()}
  def build_existing_client(runtime, address, opts \\ []) when is_binary(address) do
    runtime = Names.runtime_name(runtime)
    params = opts |> native_client_params() |> Map.put(:address, normalize_address(address))

    with {:ok, record} <- request(runtime, "build_existing_client", params) do
      {:ok, Client.from_native_record(runtime, record, opts)}
    end
  end

  @spec close_client(Client.t()) :: :ok | {:error, error()}
  def close_client(%Client{} = client) do
    with {:ok, _result} <- request(client.runtime, "close_client", %{client_id: client.id}) do
      :ok
    end
  end

  @spec can_message(Client.t(), [String.t()]) :: {:ok, map()} | {:error, error()}
  def can_message(%Client{} = client, addresses) when is_list(addresses) do
    request(client.runtime, "can_message", %{
      client_id: client.id,
      addresses: Enum.map(addresses, &normalize_address/1)
    })
  end

  @spec inbox_id_for(Client.t(), String.t()) :: {:ok, String.t() | nil} | {:error, error()}
  def inbox_id_for(%Client{} = client, address) when is_binary(address) do
    with {:ok, %{"inbox_id" => inbox_id}} <-
           request(client.runtime, "inbox_id_for", %{
             client_id: client.id,
             address: normalize_address(address)
           }) do
      {:ok, inbox_id}
    end
  end

  @spec create_dm(Client.t(), String.t()) :: {:ok, Conversation.t()} | {:error, error()}
  def create_dm(%Client{} = client, recipient) when is_binary(recipient) do
    with {:ok, %{"conversation" => record}} <-
           request(client.runtime, "create_dm", %{
             client_id: client.id,
             recipient: normalize_address(recipient)
           }) do
      {:ok, Conversation.from_native_record(client, record)}
    end
  end

  @spec create_group(Client.t(), [String.t()], keyword()) ::
          {:ok, Conversation.t()} | {:error, error()}
  def create_group(%Client{} = client, members, opts \\ []) when is_list(members) do
    params =
      %{}
      |> put_optional_request_string(opts, :name)
      |> put_optional_request_string(opts, :description)
      |> put_optional_request_string(opts, :image_url)
      |> put_optional_request_string(opts, :app_data)
      |> Map.merge(%{client_id: client.id, members: Enum.map(members, &normalize_address/1)})

    with {:ok, %{"conversation" => record}} <- request(client.runtime, "create_group", params) do
      {:ok, Conversation.from_native_record(client, record)}
    end
  end

  @spec get_conversation(Client.t(), String.t()) ::
          {:ok, Conversation.t() | nil} | {:error, error()}
  def get_conversation(%Client{} = client, conversation_id) when is_binary(conversation_id) do
    with {:ok, %{"conversation" => record}} <-
           request(client.runtime, "get_conversation", %{
             client_id: client.id,
             conversation_id: conversation_id
           }) do
      case record do
        nil -> {:ok, nil}
        record -> {:ok, Conversation.from_native_record(client, record)}
      end
    end
  end

  @spec list_conversations(Client.t(), keyword()) ::
          {:ok, [Conversation.t()]} | {:error, error()}
  def list_conversations(%Client{} = client, opts \\ []) do
    params =
      %{}
      |> put_optional_request_string(opts, :conversation_type)
      |> put_optional_request_integer(opts, :limit)
      |> Map.put(:client_id, client.id)

    with {:ok, %{"conversations" => records}} <-
           request(client.runtime, "list_conversations", params) do
      {:ok, Enum.map(records, &Conversation.from_native_record(client, &1))}
    end
  end

  @spec sync_all(Client.t()) :: {:ok, map()} | {:error, error()}
  def sync_all(%Client{} = client),
    do: request(client.runtime, "sync_all", %{client_id: client.id})

  @spec sync_conversation(Conversation.t()) :: {:ok, map()} | {:error, error()}
  def sync_conversation(%Conversation{} = conversation) do
    request(conversation.runtime, "sync_conversation", %{conversation_id: conversation.id})
  end

  @spec send_text(Conversation.t(), String.t()) :: {:ok, String.t()} | {:error, error()}
  def send_text(%Conversation{} = conversation, text) when is_binary(text) do
    with {:ok, %{"message_id" => message_id}} <-
           request(conversation.runtime, "send_text", %{
             conversation_id: conversation.id,
             text: text
           }) do
      {:ok, message_id}
    end
  end

  @spec count_messages(Conversation.t()) :: {:ok, non_neg_integer()} | {:error, error()}
  def count_messages(%Conversation{} = conversation) do
    with {:ok, %{"count" => count}} <-
           request(conversation.runtime, "count_messages", %{conversation_id: conversation.id}) do
      {:ok, count}
    end
  end

  @spec members(Conversation.t()) :: {:ok, [map()]} | {:error, error()}
  def members(%Conversation{} = conversation) do
    with {:ok, %{"members" => members}} <-
           request(conversation.runtime, "members", %{conversation_id: conversation.id}) do
      {:ok, members}
    end
  end

  @spec list_messages(Conversation.t(), keyword()) :: {:ok, [map()]} | {:error, error()}
  def list_messages(%Conversation{} = conversation, opts \\ []) do
    params =
      %{}
      |> put_optional_request_string(opts, :direction)
      |> put_optional_request_integer(opts, :limit)
      |> Map.put(:conversation_id, conversation.id)

    with {:ok, %{"messages" => messages}} <-
           request(conversation.runtime, "list_messages", params) do
      {:ok, messages}
    end
  end

  @spec request(runtime(), String.t(), map()) :: {:ok, map()} | {:error, error()}
  def request(runtime, op, params \\ %{}) do
    runtime
    |> Names.native_port()
    |> XmtpElixirSdk.Internal.NativePort.request(op, stringify_values(params))
  end

  defp native_client_params(opts) do
    %{}
    |> put_required_private_key(opts)
    |> put_optional_string(opts, :env)
    |> put_optional_string(opts, :db_path)
    |> put_optional_string(opts, :app_version)
    |> put_optional_string(opts, :api_url)
    |> put_optional_string(opts, :gateway_host)
    |> put_optional_string(opts, :encryption_key_hex)
    |> put_optional_integer(opts, :nonce)
    |> put_optional_boolean(opts, :allow_offline)
    |> put_optional_boolean(opts, :disable_device_sync)
  end

  defp put_required_private_key(params, opts) do
    case Keyword.get(opts, :private_key) do
      value when is_binary(value) and value != "" -> Map.put(params, :private_key, value)
      _value -> params
    end
  end

  defp put_optional_string(params, opts, key) do
    case Keyword.get(opts, key) do
      value when is_binary(value) and value != "" -> Map.put(params, key, value)
      _value -> params
    end
  end

  defp put_optional_integer(params, opts, key) do
    case Keyword.get(opts, key) do
      value when is_integer(value) -> Map.put(params, key, value)
      _value -> params
    end
  end

  defp put_optional_boolean(params, opts, key) do
    case Keyword.get(opts, key) do
      value when is_boolean(value) -> Map.put(params, key, value)
      _value -> params
    end
  end

  defp put_optional_request_string(params, opts, key) do
    case Keyword.get(opts, key) do
      value when is_atom(value) -> Map.put(params, key, Atom.to_string(value))
      value when is_binary(value) and value != "" -> Map.put(params, key, value)
      _value -> params
    end
  end

  defp put_optional_request_integer(params, opts, key) do
    case Keyword.get(opts, key) do
      value when is_integer(value) -> Map.put(params, key, value)
      _value -> params
    end
  end

  defp stringify_values(params) do
    Map.new(params, fn
      {key, value} when is_atom(value) -> {key, Atom.to_string(value)}
      pair -> pair
    end)
  end

  defp normalize_address(address) when is_binary(address) do
    address |> String.trim() |> String.downcase()
  end
end

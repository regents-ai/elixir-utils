defmodule XmtpElixirSdk.TestSupport do
  alias XmtpElixirSdk.Client
  alias XmtpElixirSdk.Clients
  alias XmtpElixirSdk.Conversation
  alias XmtpElixirSdk.Conversations
  alias XmtpElixirSdk.Runtime
  alias XmtpElixirSdk.Types

  def start_runtime(_context) do
    runtime_name = Runtime.unique_name()
    {:ok, _pid} = Runtime.start_link(name: runtime_name)
    runtime = Runtime.new(runtime_name)
    Process.put(:xmtp_test_runtime, runtime)
    {:ok, runtime: runtime}
  end

  def current_runtime do
    case Process.get(:xmtp_test_runtime) do
      nil -> raise "test runtime not started"
      runtime -> runtime
    end
  end

  def identifier(label) when is_binary(label) do
    hex =
      label
      |> :erlang.phash2()
      |> Integer.to_string(16)
      |> String.pad_leading(40, "0")
      |> String.slice(-40, 40)

    %Types.Identifier{identifier: "0x#{hex}", identifier_kind: :ethereum}
  end

  def create_client(label, opts \\ []) do
    Clients.create(current_runtime(), identifier(label), Keyword.put_new(opts, :env, :dev))
  end

  def build_client(label, opts \\ []) do
    Clients.build(current_runtime(), identifier(label), Keyword.put_new(opts, :env, :dev))
  end

  def create_group(%Client{} = creator, member_labels, opts \\ %Types.CreateGroupOptions{}) do
    identifiers = Enum.map(member_labels, &identifier/1)
    Conversations.create_group_with_identifiers(creator, identifiers, opts)
  end

  def create_dm(%Client{} = creator, peer_label, opts \\ %Types.CreateDmOptions{}) do
    Conversations.create_dm_with_identifier(creator, identifier(peer_label), opts)
  end

  def refresh_conversation(%Conversation{client: client, id: id}) do
    Conversations.get_by_id(client, id)
  end
end

ExUnit.start()

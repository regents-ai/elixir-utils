defmodule XmtpElixirSdk.Events do
  @moduledoc """
  Runtime-scoped event subscriptions and delivery.
  """

  alias XmtpElixirSdk.Client
  alias XmtpElixirSdk.Conversation
  alias XmtpElixirSdk.Internal.Names
  alias XmtpElixirSdk.Internal.Registry
  alias XmtpElixirSdk.Runtime

  defmodule ConversationCreated do
    @moduledoc false
    defstruct [:conversation]
  end

  defmodule ConversationUpdated do
    @moduledoc false
    defstruct [:conversation]
  end

  defmodule MessageCreated do
    @moduledoc false
    defstruct [:message]
  end

  defmodule MessagePublished do
    @moduledoc false
    defstruct [:conversation_id, :message_ids]
  end

  defmodule MessageDeleted do
    @moduledoc false
    defstruct [:messages, :message_ids]
  end

  defmodule ConsentUpdated do
    @moduledoc false
    defstruct [:records]
  end

  defmodule PreferenceUpdated do
    @moduledoc false
    defstruct [:updates]
  end

  defmodule SignatureRequestCreated do
    @moduledoc false
    defstruct [:client_id, :action, :signature_request_id, :signature_text]
  end

  defmodule SyncApplied do
    @moduledoc false
    defstruct [:archive_pin, :conversation_count]
  end

  @type topic ::
          {:conversations, String.t()}
          | {:conversation, String.t()}
          | {:messages, String.t()}
          | {:deleted_messages, String.t()}
          | {:preferences, String.t()}
          | {:consent, String.t()}

  @spec subscribe(Runtime.t() | Client.t() | Conversation.t() | atom(), topic(), pid()) ::
          :ok
  def subscribe(runtime_or_subject, topic, subscriber \\ self()) when is_pid(subscriber) do
    Registry.subscribe(Names.registry(runtime_or_subject), topic, subscriber)
  end

  @spec unsubscribe(Runtime.t() | Client.t() | Conversation.t() | atom(), topic(), pid()) ::
          :ok
  def unsubscribe(runtime_or_subject, topic, subscriber \\ self()) when is_pid(subscriber) do
    Registry.unsubscribe(Names.registry(runtime_or_subject), topic, subscriber)
  end

  @spec emit(Runtime.t() | Client.t() | Conversation.t() | atom(), topic(), struct()) :: :ok
  def emit(runtime_or_subject, topic, event) do
    Registry.emit(Names.registry(runtime_or_subject), topic, event)
  end
end

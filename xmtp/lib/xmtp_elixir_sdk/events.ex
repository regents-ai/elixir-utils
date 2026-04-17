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
    @moduledoc """
    Consent records emitted after `Preferences.set_consent_states/2`.

    Canonical shapes:

    - inbox consent: `%{entity: "inbox-id", state: :allowed | :denied | :unknown}`
    - group consent: `%{group_id: "group-id", state: :allowed | :denied | :unknown}`
    """
    defstruct [:records]
    @type t :: %__MODULE__{records: [XmtpElixirSdk.Types.consent_record()]}
  end

  defmodule PreferenceUpdated do
    @moduledoc """
    Preference updates emitted by `Preferences.sync/1` and consent changes.

    `updates` always contains `XmtpElixirSdk.Types.PreferenceUpdate` values:

    - `%PreferenceUpdate{kind: :hmac_key, consent: nil}`
    - `%PreferenceUpdate{kind: :consent, consent: %ConsentUpdate{...}}`
    """
    defstruct [:updates]
    @type t :: %__MODULE__{updates: [XmtpElixirSdk.Types.PreferenceUpdate.t()]}
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

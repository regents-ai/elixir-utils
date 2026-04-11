defmodule XmtpElixirSdk.BrowserShim.Action do
  @moduledoc """
  Canonical envelopes for the browser shim bridge.
  """

  defmodule Request do
    @moduledoc false

    @enforce_keys [:id, :action]
    defstruct [:id, :action, data: %{}]

    @type t :: %__MODULE__{
            id: String.t(),
            action: String.t(),
            data: term()
          }
  end

  defmodule Response do
    @moduledoc false

    @enforce_keys [:id, :action, :result]
    defstruct [:id, :action, :result]

    @type t :: %__MODULE__{
            id: String.t(),
            action: String.t(),
            result: term()
          }
  end

  defmodule Error do
    @moduledoc false

    @enforce_keys [:id, :action, :error]
    defstruct [:id, :action, :error]

    @type t :: %__MODULE__{
            id: String.t(),
            action: String.t(),
            error: term()
          }
  end

  defmodule StreamEvent do
    @moduledoc false

    @enforce_keys [:action, :stream_id, :result]
    defstruct [:action, :stream_id, :result]

    @type t :: %__MODULE__{
            action: String.t(),
            stream_id: String.t(),
            result: term()
          }
  end

  defmodule StreamError do
    @moduledoc false

    @enforce_keys [:action, :stream_id, :error]
    defstruct [:action, :stream_id, :error]

    @type t :: %__MODULE__{
            action: String.t(),
            stream_id: String.t(),
            error: term()
          }
  end
end

defmodule XmtpElixirSdk.BrowserShim.Action do
  @moduledoc """
  Typed message envelopes for the browser-only bridge.

  These structs define the contract between Elixir and a browser runtime when
  the browser must do work the server cannot do directly, such as OPFS access
  or worker coordination.
  """

  defmodule Request do
    @moduledoc """
    A request sent from Elixir to the browser shim.
    """

    @enforce_keys [:id, :action]
    defstruct [:id, :action, data: %{}]

    @type t :: %__MODULE__{
            id: String.t(),
            action: String.t(),
            data: term()
          }
  end

  defmodule Response do
    @moduledoc """
    A successful response sent back from the browser shim.
    """

    @enforce_keys [:id, :action, :result]
    defstruct [:id, :action, :result]

    @type t :: %__MODULE__{
            id: String.t(),
            action: String.t(),
            result: term()
          }
  end

  defmodule Error do
    @moduledoc """
    An error response sent back from the browser shim.
    """

    @enforce_keys [:id, :action, :error]
    defstruct [:id, :action, :error]

    @type t :: %__MODULE__{
            id: String.t(),
            action: String.t(),
            error: term()
          }
  end

  defmodule StreamEvent do
    @moduledoc """
    A streamed event emitted by the browser shim.
    """

    @enforce_keys [:action, :streamId, :result]
    defstruct [:action, :streamId, :result]

    @type t :: %__MODULE__{
            action: String.t(),
            streamId: String.t(),
            result: term()
          }
  end

  defmodule StreamError do
    @moduledoc """
    A streamed error emitted by the browser shim.
    """

    @enforce_keys [:action, :streamId, :error]
    defstruct [:action, :streamId, :error]

    @type t :: %__MODULE__{
            action: String.t(),
            streamId: String.t(),
            error: term()
          }
  end
end

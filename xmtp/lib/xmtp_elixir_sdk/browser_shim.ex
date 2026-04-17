defmodule XmtpElixirSdk.BrowserShim do
  @moduledoc """
  Browser-shim contracts for browser-only SDK work.

  Most of the SDK is designed to run in Elixir. This namespace exists only for
  the pieces that must be handled by a browser runtime, such as worker messaging
  or browser-managed storage.

  It keeps the contract small and explicit:

  - typed action envelopes for worker-style messaging
  - a minimal async stream primitive
  - request builders for the OPFS adapter surface

  If you are building a server-only integration, you can usually ignore this
  namespace.
  """

  alias XmtpElixirSdk.BrowserShim.Action

  @type action_name :: String.t()
  @type stream_id :: String.t()

  @doc """
  Generate a unique request or stream id for browser-shim traffic.
  """
  @spec id() :: String.t()
  def id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Build a browser-shim request envelope.
  """
  @spec request(action_name(), term()) :: Action.Request.t()
  def request(action, data \\ %{}) when is_binary(action) do
    %Action.Request{id: id(), action: action, data: data}
  end

  @doc """
  Build a successful browser-shim response envelope.
  """
  @spec response(action_name(), String.t(), term()) :: Action.Response.t()
  def response(action, request_id, result) when is_binary(action) and is_binary(request_id) do
    %Action.Response{id: request_id, action: action, result: result}
  end

  @doc """
  Build a failed browser-shim response envelope.
  """
  @spec error(action_name(), String.t(), term()) :: Action.Error.t()
  def error(action, request_id, reason) when is_binary(action) and is_binary(request_id) do
    %Action.Error{id: request_id, action: action, error: reason}
  end

  @doc """
  Build a streamed event envelope from the browser shim.
  """
  @spec stream_event(action_name(), stream_id(), term()) :: Action.StreamEvent.t()
  def stream_event(action, stream_id, result) when is_binary(action) and is_binary(stream_id) do
    %Action.StreamEvent{action: action, streamId: stream_id, result: result}
  end

  @doc """
  Build a streamed error envelope from the browser shim.
  """
  @spec stream_error(action_name(), stream_id(), term()) :: Action.StreamError.t()
  def stream_error(action, stream_id, reason) when is_binary(action) and is_binary(stream_id) do
    %Action.StreamError{action: action, streamId: stream_id, error: reason}
  end
end

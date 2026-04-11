defmodule XmtpElixirSdk.BrowserShim do
  @moduledoc """
  Browser-shim contracts for the cut-over SDK.

  This namespace keeps the Elixir side small and explicit:

  - typed action envelopes for worker-style messaging
  - a minimal async stream primitive
  - request builders for the OPFS adapter surface

  The browser runtime owns only the unavoidable browser-specific plumbing.
  """

  alias XmtpElixirSdk.BrowserShim.Action

  @type action_name :: String.t()
  @type stream_id :: String.t()

  @spec id() :: String.t()
  def id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end

  @spec request(action_name(), term()) :: Action.Request.t()
  def request(action, data \\ %{}) when is_binary(action) do
    %Action.Request{id: id(), action: action, data: data}
  end

  @spec response(action_name(), String.t(), term()) :: Action.Response.t()
  def response(action, request_id, result) when is_binary(action) and is_binary(request_id) do
    %Action.Response{id: request_id, action: action, result: result}
  end

  @spec error(action_name(), String.t(), term()) :: Action.Error.t()
  def error(action, request_id, reason) when is_binary(action) and is_binary(request_id) do
    %Action.Error{id: request_id, action: action, error: reason}
  end

  @spec stream_event(action_name(), stream_id(), term()) :: Action.StreamEvent.t()
  def stream_event(action, stream_id, result) when is_binary(action) and is_binary(stream_id) do
    %Action.StreamEvent{action: action, stream_id: stream_id, result: result}
  end

  @spec stream_error(action_name(), stream_id(), term()) :: Action.StreamError.t()
  def stream_error(action, stream_id, reason) when is_binary(action) and is_binary(stream_id) do
    %Action.StreamError{action: action, stream_id: stream_id, error: reason}
  end
end

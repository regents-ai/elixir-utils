defmodule RegentChatGPT.Error do
  @moduledoc """
  Stable error value returned by ChatGPT connector operations.
  """

  defexception [:code, :message, :status, :body]

  @type code ::
          :device_code_request_failed
          | :device_code_disabled
          | :authorization_pending
          | :authorization_expired
          | :token_exchange_failed
          | :token_refresh_failed
          | :refresh_token_invalid
          | :not_authenticated
          | :invalid_token
          | :network_error
          | :models_request_failed
          | :responses_request_failed
          | :invalid_responses_request

  @type t :: %__MODULE__{
          code: code(),
          message: String.t(),
          status: integer() | nil,
          body: String.t() | nil
        }

  @spec new(code(), String.t(), keyword()) :: t()
  def new(code, message, opts \\ []) do
    %__MODULE__{
      code: code,
      message: message,
      status: Keyword.get(opts, :status),
      body: Keyword.get(opts, :body)
    }
  end

  @doc "Returns true when the user must reconnect ChatGPT."
  @spec refresh_token_invalid?(term()) :: boolean()
  def refresh_token_invalid?(%__MODULE__{code: :refresh_token_invalid}), do: true
  def refresh_token_invalid?(_error), do: false
end

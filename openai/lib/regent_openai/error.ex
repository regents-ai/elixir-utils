defmodule RegentOpenAI.Error do
  @moduledoc """
  Why a call did not return a result.

  `usage` and `cost_usd` are set when OpenAI had already billed the call (a
  reply that stopped early, was refused, or broke its schema), so the site can
  still record the spend. They are `nil` when nothing was billed.

  Reasons:

    * `:api_key_missing`
    * `{:unpriced_model, model}` — refused before sending
    * `{:audio_too_large, bytes}` — over 25 MB, refused before sending
    * `{:text_too_long, characters}` — over 4,096 characters, refused before sending
    * `{:openai, status, code}` — OpenAI answered with an error
    * `{:transport, message}` — the request did not reach OpenAI or timed out
    * `{:incomplete, reason}` — billed; the reply stopped early
    * `{:refused, message}` — billed; the model declined
    * `:invalid_json` — billed; the reply did not decode as the schema asked
    * `:unexpected_response` — OpenAI answered in a shape this package does not read
  """

  defexception [:reason, :usage, :cost_usd]

  @type t :: %__MODULE__{
          reason: term(),
          usage: RegentOpenAI.usage() | nil,
          cost_usd: Decimal.t() | nil
        }

  @impl true
  def message(%__MODULE__{reason: reason}), do: describe(reason)

  defp describe(:api_key_missing), do: "the OpenAI API key is not configured"
  defp describe({:unpriced_model, model}), do: "no price is known for #{model}"
  defp describe({:audio_too_large, bytes}), do: "the audio is #{bytes} bytes; the limit is 25 MB"

  defp describe({:text_too_long, characters}),
    do: "the text is #{characters} characters; the limit is 4096"

  defp describe({:openai, status, code}), do: "OpenAI answered #{status} (#{code || "no code"})"
  defp describe({:transport, message}), do: "OpenAI could not be reached: #{message}"
  defp describe({:incomplete, reason}), do: "the reply stopped early (#{reason || "no reason"})"
  defp describe({:refused, _message}), do: "the model declined to answer"
  defp describe(:invalid_json), do: "the reply did not match the requested schema"
  defp describe(:unexpected_response), do: "OpenAI answered in an unexpected shape"
end

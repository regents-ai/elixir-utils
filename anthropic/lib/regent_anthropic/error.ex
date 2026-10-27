defmodule RegentAnthropic.Error do
  @moduledoc """
  Why a call did not return a result.

  `usage` and `cost_usd` are set when Anthropic had already billed the call (a
  reply that stopped early, was refused, or broke its schema), so the site can
  still record the spend. They are `nil` when nothing was billed.

  Reasons:

    * `:api_key_missing`
    * `{:unpriced_model, model}` — refused before sending
    * `{:anthropic, status, type, message}` — Anthropic answered with an error; `message`
      is Anthropic's own words, such as a low credit balance (never the key)
    * `{:transport, message}` — the request did not reach Anthropic or timed out
    * `{:incomplete, stop_reason}` — billed; the reply stopped early, such as at `max_tokens`
    * `:refused` — billed; the model declined
    * `:invalid_json` — billed; the reply did not decode as the schema asked
    * `:unexpected_response` — Anthropic answered in a shape this package does not read
  """

  defexception [:reason, :usage, :cost_usd]

  @type t :: %__MODULE__{
          reason: term(),
          usage: RegentAnthropic.usage() | nil,
          cost_usd: Decimal.t() | nil
        }

  @impl true
  def message(%__MODULE__{reason: reason}), do: describe(reason)

  defp describe(:api_key_missing), do: "the Anthropic API key is not configured"
  defp describe({:unpriced_model, model}), do: "no price is known for #{model}"

  defp describe({:anthropic, status, type, message}),
    do: "Anthropic answered #{status} (#{type || "no type"}): #{message || "no message"}"

  defp describe({:transport, message}), do: "Anthropic could not be reached: #{message}"
  defp describe({:incomplete, stop_reason}), do: "the reply stopped early (#{stop_reason})"
  defp describe(:refused), do: "the model declined to answer"
  defp describe(:invalid_json), do: "the reply did not match the requested schema"
  defp describe(:unexpected_response), do: "Anthropic answered in an unexpected shape"
end

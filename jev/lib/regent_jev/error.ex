defmodule RegentJev.Error do
  @moduledoc """
  Why a call did not return answers.

  `usage` and `cost_usd` are set when OpenRouter had already billed the call
  (Jev answered, but not with an offered key), so the site can still record
  the spend. They are `nil` when nothing was billed.

  Reasons:

    * `:api_key_missing`
    * `{:openrouter, status, code}` — OpenRouter answered with an error; a 429
      or a 5xx is worth retrying later
    * `{:transport, message}` — the request did not reach OpenRouter or timed out
    * `{:unexpected_answer, name}` — billed; the question `name` came back
      without one of its offered keys
    * `:unexpected_response` — OpenRouter answered in a shape this package does not read
  """

  defexception [:reason, :usage, :cost_usd]

  @type t :: %__MODULE__{
          reason: term(),
          usage: RegentJev.usage() | nil,
          cost_usd: Decimal.t() | nil
        }

  @impl true
  def message(%__MODULE__{reason: reason}), do: describe(reason)

  defp describe(:api_key_missing), do: "the OpenRouter API key is not configured"

  defp describe({:openrouter, status, code}),
    do: "OpenRouter answered #{status} (#{code || "no code"})"

  defp describe({:transport, message}), do: "OpenRouter could not be reached: #{message}"

  defp describe({:unexpected_answer, name}),
    do: "Jev did not answer #{name} with one of the offered keys"

  defp describe(:unexpected_response), do: "OpenRouter answered in an unexpected shape"
end

defmodule RegentChatGPT.Redactor do
  @moduledoc "Log redaction helpers for ChatGPT tokens and auth headers."

  @spec redact(term()) :: term()
  def redact(value) when is_binary(value) do
    value
    |> String.replace(~r/Bearer\s+[A-Za-z0-9._~+\/=-]+/i, "Bearer [redacted]")
    |> String.replace(
      ~r/("(?:access_token|refresh_token|id_token)"\s*:\s*")[^"]+"/i,
      "\\1[redacted]\""
    )
    |> String.replace(
      ~r/((?:authorization|chatgpt-account-id)["':\s=>]+)[^,\]\}\s]+/i,
      "\\1[redacted]"
    )
  end

  def redact(value), do: value
end

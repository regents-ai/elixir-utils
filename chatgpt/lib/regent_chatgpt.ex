defmodule RegentChatGPT do
  @moduledoc """
  Shared ChatGPT account connection primitives for Regent Elixir apps.

  Privy remains the Regent login. Use this package only for the connected
  ChatGPT account rail, and keep product authorization, storage, and spend
  policy in the host app.
  """

  alias RegentChatGPT.{Codex, Config, Device, OAuth, Token}

  defdelegate resolve_config(opts \\ []), to: Config, as: :resolve
  defdelegate authorization_url(config, params), to: OAuth
  defdelegate exchange_authorization_code(config, params), to: OAuth
  defdelegate refresh_tokens(config, refresh_token), to: OAuth
  defdelegate request_device_code(config, opts \\ []), to: Device
  defdelegate poll_device_code(config, device), to: Device
  defdelegate exchange_device_authorization(config, poll), to: Device
  defdelegate ensure_fresh_tokens(config, tokens, opts \\ []), to: Token
  defdelegate list_models(config, tokens), to: Codex
  defdelegate responses_request(config, tokens, body, opts \\ []), to: Codex
  defdelegate normalize_responses_body(body, opts \\ []), to: Codex
end

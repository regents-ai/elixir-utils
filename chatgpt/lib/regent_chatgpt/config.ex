defmodule RegentChatGPT.Config do
  @moduledoc """
  Runtime configuration for ChatGPT OAuth and Codex calls.

  Every value is caller-overridable. This module does not read environment
  variables; products inject secrets, stores, and HTTP clients at their own
  boundary.
  """

  @default_client_id "app_EMoamEEZ73f0CkXaXp7hrann"
  @default_issuer "https://auth.openai.com"
  @default_scope "openid profile email offline_access"
  @default_codex_base_url "https://chatgpt.com/backend-api/codex"
  @default_originator "codex_cli_rs"
  @default_client_version "0.142.5"

  defstruct client_id: @default_client_id,
            issuer: @default_issuer,
            scope: @default_scope,
            codex_base_url: @default_codex_base_url,
            originator: @default_originator,
            client_version: @default_client_version,
            http_client: RegentChatGPT.HTTP.ReqClient,
            token_url: "#{@default_issuer}/oauth/token",
            authorize_url: "#{@default_issuer}/oauth/authorize",
            device_api_base: "#{@default_issuer}/api/accounts",
            device_verification_url: "#{@default_issuer}/codex/device",
            device_redirect_uri: "#{@default_issuer}/deviceauth/callback"

  @type t :: %__MODULE__{
          client_id: String.t(),
          issuer: String.t(),
          scope: String.t(),
          codex_base_url: String.t(),
          originator: String.t(),
          client_version: String.t(),
          http_client: module() | (keyword() -> {:ok, map()} | {:error, term()}),
          token_url: String.t(),
          authorize_url: String.t(),
          device_api_base: String.t(),
          device_verification_url: String.t(),
          device_redirect_uri: String.t()
        }

  @doc "Applies defaults and derives endpoint URLs."
  @spec resolve(t() | map() | keyword()) :: t()
  def resolve(opts \\ [])

  def resolve(%__MODULE__{} = config), do: config

  def resolve(opts) do
    issuer = opts |> get_opt(:issuer, @default_issuer) |> strip_trailing_slash()

    codex_base_url =
      opts |> get_opt(:codex_base_url, @default_codex_base_url) |> strip_trailing_slash()

    %__MODULE__{
      client_id: get_opt(opts, :client_id, @default_client_id),
      issuer: issuer,
      scope: get_opt(opts, :scope, @default_scope),
      codex_base_url: codex_base_url,
      originator: get_opt(opts, :originator, @default_originator),
      client_version: get_opt(opts, :client_version, @default_client_version),
      http_client: get_opt(opts, :http_client, RegentChatGPT.HTTP.ReqClient),
      token_url: "#{issuer}/oauth/token",
      authorize_url: "#{issuer}/oauth/authorize",
      device_api_base: "#{issuer}/api/accounts",
      device_verification_url: "#{issuer}/codex/device",
      device_redirect_uri: "#{issuer}/deviceauth/callback"
    }
  end

  defp get_opt(opts, key, default) when is_list(opts), do: Keyword.get(opts, key, default)
  defp get_opt(opts, key, default) when is_map(opts), do: Map.get(opts, key, default)

  defp strip_trailing_slash(value) when is_binary(value), do: String.replace(value, ~r{/+$}, "")
end

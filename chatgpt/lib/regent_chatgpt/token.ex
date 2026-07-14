defmodule RegentChatGPT.Token do
  @moduledoc "Token expiry and refresh helpers."

  alias RegentChatGPT.{Config, Error, JWT, OAuth, TokenSet}

  @expiry_margin_ms 60 * 1000

  @spec access_token_expired?(TokenSet.t() | map() | nil, keyword()) :: boolean()
  def access_token_expired?(tokens, opts \\ []) do
    now = Keyword.get(opts, :now, fn -> System.system_time(:millisecond) end)

    case TokenSet.from(tokens) do
      nil ->
        true

      %TokenSet{access_token: nil} ->
        true

      %TokenSet{} = token_set ->
        expires_at = token_set.expires_at || JWT.token_expiry(token_set.access_token)
        is_integer(expires_at) and expires_at <= now.() + @expiry_margin_ms
    end
  end

  @spec ensure_fresh_tokens(Config.t() | keyword() | map(), TokenSet.t() | map() | nil, keyword()) ::
          {:ok, TokenSet.t()} | {:error, Error.t()}
  def ensure_fresh_tokens(config, tokens, opts \\ []) do
    config = Config.resolve(config)
    token_set = TokenSet.from(tokens)
    force? = Keyword.get(opts, :force, false)

    cond do
      token_set == nil ->
        {:error, Error.new(:not_authenticated, "No ChatGPT credentials available.")}

      token_set.access_token && not force? && not access_token_expired?(token_set, opts) ->
        {:ok, with_account_id(token_set)}

      is_binary(token_set.refresh_token) ->
        with {:ok, refreshed} <- OAuth.refresh_tokens(config, token_set.refresh_token) do
          refreshed = with_account_id(refreshed)
          on_refresh = Keyword.get(opts, :on_refresh)
          if is_function(on_refresh, 1), do: on_refresh.(refreshed)
          {:ok, refreshed}
        end

      true ->
        {:error,
         Error.new(
           :not_authenticated,
           "ChatGPT credentials are expired. The user must connect ChatGPT again."
         )}
    end
  end

  @spec with_account_id(TokenSet.t()) :: TokenSet.t()
  def with_account_id(%TokenSet{account_id: account_id} = tokens) when is_binary(account_id),
    do: tokens

  def with_account_id(%TokenSet{} = tokens) do
    account_id =
      JWT.derive_account_id(tokens.id_token) || JWT.derive_account_id(tokens.access_token)

    %{tokens | account_id: account_id}
  end
end

defmodule RegentOAuth.AccessTokens do
  @moduledoc """
  Boruta's access token store, keeping only a SHA-256 hash of each access and
  refresh token (`RegentOAuth.hash_token/1`). The plain tokens exist once, in
  the token answer the client receives; a database reader cannot use a stored
  row as a credential.

  A token read back from the store carries the stored hashes in `value` and
  `refresh_token`, and is revoked by them. A refresh records the previous
  token's hash, so `previous_token` never holds a plain token either. Tokens
  are read from the database every time, never from Boruta's cache, so a
  revoked connection stops at once.
  """
  @behaviour Boruta.Oauth.AccessTokens

  import Ecto.Query
  import Boruta.Ecto.OauthMapper, only: [to_oauth_schema: 1]

  alias Boruta.Ecto.Token
  alias Boruta.Oauth
  alias RegentOAuth.Repo

  @impl true
  def get_by(value: value), do: stored(:value, value)
  def get_by(refresh_token: refresh_token), do: stored(:refresh_token, refresh_token)

  @impl true
  def create(
        %{client: %Oauth.Client{id: client_id, access_token_ttl: ttl}, scope: scope} = params,
        options
      ) do
    attrs = %{
      client_id: client_id,
      sub: params[:sub],
      redirect_uri: params[:redirect_uri],
      state: params[:state],
      scope: scope,
      access_token_ttl: ttl,
      previous_token: params[:previous_token],
      previous_code: params[:previous_code]
    }

    token = %Token{resource_owner: params[:resource_owner]}

    changeset =
      if options[:refresh_token],
        do: Token.changeset_with_refresh_token(token, attrs),
        else: Token.changeset(token, attrs)

    value = Ecto.Changeset.get_change(changeset, :value)
    refresh_token = Ecto.Changeset.get_change(changeset, :refresh_token)

    changeset
    |> Ecto.Changeset.update_change(:value, &RegentOAuth.hash_token/1)
    |> Ecto.Changeset.update_change(:refresh_token, &RegentOAuth.hash_token/1)
    |> Repo.insert()
    |> case do
      {:ok, row} ->
        {:ok, %{to_oauth_schema(row) | value: value, refresh_token: refresh_token}}

      {:error, _changeset} ->
        {:error, "Could not create access token."}
    end
  end

  @impl true
  def revoke(%Oauth.Token{} = token), do: stamp(token, :revoked_at)

  @impl true
  def revoke_refresh_token(%Oauth.Token{} = token), do: stamp(token, :refresh_token_revoked_at)

  defp stored(field, plain) when is_binary(plain) do
    hash = RegentOAuth.hash_token(plain)

    case Repo.one(from(t in Token, where: t.type == "access_token" and field(t, ^field) == ^hash)) do
      %Token{} = row -> to_oauth_schema(row)
      nil -> nil
    end
  end

  defp stored(_field, _plain), do: nil

  defp stamp(%Oauth.Token{client: %Oauth.Client{id: client_id}, value: hash}, field) do
    case Repo.get_by(Token, type: "access_token", client_id: client_id, value: hash) do
      %Token{} = row ->
        {:ok, row} = row |> Ecto.Changeset.change(%{field => DateTime.utc_now()}) |> Repo.update()
        {:ok, to_oauth_schema(row)}

      nil ->
        {:error, "Token not found."}
    end
  end
end

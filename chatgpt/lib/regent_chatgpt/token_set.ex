defmodule RegentChatGPT.TokenSet do
  @moduledoc "OAuth tokens for a connected ChatGPT account."

  defstruct [:access_token, :refresh_token, :id_token, :account_id, :expires_at]

  @type t :: %__MODULE__{
          access_token: String.t() | nil,
          refresh_token: String.t() | nil,
          id_token: String.t() | nil,
          account_id: String.t() | nil,
          expires_at: integer() | nil
        }

  @spec from(t() | map() | nil) :: t() | nil
  def from(nil), do: nil
  def from(%__MODULE__{} = tokens), do: tokens

  def from(tokens) when is_map(tokens) do
    %__MODULE__{
      access_token: value(tokens, :access_token, "access_token", :accessToken, "accessToken"),
      refresh_token:
        value(tokens, :refresh_token, "refresh_token", :refreshToken, "refreshToken"),
      id_token: value(tokens, :id_token, "id_token", :idToken, "idToken"),
      account_id: value(tokens, :account_id, "account_id", :accountId, "accountId"),
      expires_at: value(tokens, :expires_at, "expires_at", :expiresAt, "expiresAt")
    }
  end

  defp value(map, key, string_key, camel_key, camel_string_key) do
    Map.get(map, key) || Map.get(map, string_key) || Map.get(map, camel_key) ||
      Map.get(map, camel_string_key)
  end
end

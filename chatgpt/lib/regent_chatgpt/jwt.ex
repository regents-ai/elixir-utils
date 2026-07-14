defmodule RegentChatGPT.JWT do
  @moduledoc """
  JWT claim parsing for tokens returned directly by OpenAI.

  These helpers decode claims without verifying a signature. Use them only for
  tokens just received from the token endpoint or already stored by the host
  app; never use them to accept arbitrary client-supplied identity proof.
  """

  alias RegentChatGPT.User

  @auth_claim "https://api.openai.com/auth"

  @spec decode_claims(String.t() | nil) :: map() | nil
  def decode_claims(token) when is_binary(token) do
    with [_, payload, _] <- String.split(token, "."),
         {:ok, json} <- RegentChatGPT.Base64Url.decode(payload),
         {:ok, claims} when is_map(claims) <- Jason.decode(json) do
      claims
    else
      _ -> nil
    end
  end

  def decode_claims(_token), do: nil

  @spec token_expiry(String.t() | nil) :: integer() | nil
  def token_expiry(token) do
    case decode_claims(token) do
      %{"exp" => exp} when is_integer(exp) -> exp * 1000
      _claims -> nil
    end
  end

  @spec derive_account_id(String.t() | nil) :: String.t() | nil
  def derive_account_id(token) do
    case decode_claims(token) do
      %{@auth_claim => %{"chatgpt_account_id" => account_id}} when is_binary(account_id) ->
        account_id

      _claims ->
        nil
    end
  end

  @spec parse_user(String.t() | nil) :: User.t() | nil
  def parse_user(id_token) do
    with claims when is_map(claims) <- decode_claims(id_token),
         account_id when is_binary(account_id) <- derive_account_id(id_token) do
      auth = Map.get(claims, @auth_claim, %{})

      %User{
        account_id: account_id,
        email: non_empty_string(claims["email"]),
        name: non_empty_string(claims["name"]),
        plan: non_empty_string(auth["chatgpt_plan_type"])
      }
    else
      _ -> nil
    end
  end

  defp non_empty_string(value) when is_binary(value) and value != "", do: value
  defp non_empty_string(_value), do: nil
end

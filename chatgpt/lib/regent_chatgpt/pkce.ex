defmodule RegentChatGPT.PKCE do
  @moduledoc "PKCE helpers for ChatGPT OAuth flows."

  @type pair :: %{verifier: String.t(), challenge: String.t()}

  @doc "Returns cryptographically random bytes encoded as base64url."
  @spec random_token(pos_integer()) :: String.t()
  def random_token(length \\ 32) when is_integer(length) and length > 0 do
    length
    |> :crypto.strong_rand_bytes()
    |> RegentChatGPT.Base64Url.encode()
  end

  @doc "Generates an OAuth state value."
  @spec create_state() :: String.t()
  def create_state, do: random_token(16)

  @doc "Generates a PKCE verifier/challenge pair using S256."
  @spec generate() :: pair()
  def generate do
    verifier = random_token(48)
    challenge = :crypto.hash(:sha256, verifier) |> RegentChatGPT.Base64Url.encode()
    %{verifier: verifier, challenge: challenge}
  end
end

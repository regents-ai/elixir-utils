defmodule RegentOAuth.TokenResult do
  @moduledoc false
  @behaviour Boruta.Oauth.TokenApplication
  @impl true
  def token_success(_conn, response), do: {:ok, response}
  @impl true
  def token_error(_conn, error), do: {:error, error}
end

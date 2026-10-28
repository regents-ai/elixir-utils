defmodule RegentOAuth.ResourceOwners do
  @moduledoc false
  @behaviour Boruta.Oauth.ResourceOwners

  @impl true
  def get_by(sub: subject) do
    if RegentOAuth.site().active_subject?(subject),
      do: {:ok, %Boruta.Oauth.ResourceOwner{sub: subject}},
      else: {:error, "Account unavailable."}
  end

  def get_by(_), do: {:error, "Password sign-in is not supported."}

  @impl true
  def check_password(_, _), do: {:error, "Use the site's own sign-in."}

  @impl true
  def authorized_scopes(_), do: []

  @impl true
  def claims(_, _), do: %{}
end

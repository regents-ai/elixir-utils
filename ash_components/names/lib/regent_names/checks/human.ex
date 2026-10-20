defmodule RegentNames.Checks.Human do
  @moduledoc """
  The actor is a person signed in on the site: every Regent site's human actor
  carries `role: :human` and the id of their account on that site.
  """
  use Ash.Policy.SimpleCheck

  @impl true
  def describe(_opts), do: "actor is a person signed in on this site"

  @impl true
  def match?(%{role: :human, human_account_id: id}, _context, _opts) when is_integer(id),
    do: true

  def match?(_actor, _context, _opts), do: false
end

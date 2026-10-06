defmodule RegentCredits.Checks.Admin do
  @moduledoc "An admin actor whose Privy account the `:admins` setting names."
  use Ash.Policy.SimpleCheck

  alias RegentCredits.Actor

  @impl true
  def describe(_opts), do: "actor is a Credits admin"

  @impl true
  def match?(%Actor{role: :admin, privy_user_id: id}, _context, _opts),
    do: id in Application.fetch_env!(:regent_credits, :admins)

  def match?(_actor, _context, _opts), do: false
end

defmodule RegentCredits.Checks.OwnCredits do
  @moduledoc """
  A person (or, with `roles: [:person, :agent]`, an agent) acting on the
  Credits of the Privy account the action names in `privy_user_id`.
  """
  use Ash.Policy.SimpleCheck

  alias RegentCredits.Actor

  @impl true
  def describe(_opts), do: "actor acts for the account whose Credits these are"

  @impl true
  def match?(%Actor{role: role, privy_user_id: id}, %{subject: subject}, opts)
      when is_binary(id),
      do: role in Keyword.get(opts, :roles, [:person]) and named(subject) == id

  def match?(_actor, _context, _opts), do: false

  defp named(%Ash.ActionInput{} = input), do: Ash.ActionInput.get_argument(input, :privy_user_id)

  defp named(%Ash.Changeset{} = changeset),
    do: Ash.Changeset.get_attribute(changeset, :privy_user_id)
end

defmodule RegentCredits.Checks.OwnWallet do
  @moduledoc """
  A person reporting a payment sent from one of the wallets the site's
  sign-in verified for them, so nobody can claim another person's payment.
  """
  use Ash.Policy.SimpleCheck

  alias RegentChain.Address
  alias RegentCredits.Actor

  @impl true
  def describe(_opts), do: "actor's verified wallets include the paying wallet"

  @impl true
  def match?(%Actor{role: :person, wallets: wallets}, %{subject: input}, _opts) do
    case Address.normalize(Ash.ActionInput.get_argument(input, :wallet)) do
      {:ok, wallet} -> wallet in wallets
      :error -> false
    end
  end

  def match?(_actor, _context, _opts), do: false
end

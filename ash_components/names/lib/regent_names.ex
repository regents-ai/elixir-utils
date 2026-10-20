defmodule RegentNames do
  @moduledoc """
  The Regent names a person's wallets hold, the claims those wallets may still
  make, and the one write: a free claim, recorded on the shared database and
  sent to no chain. Every Regent site shows and claims them the same way.

  The tables live in the `regent_names` schema of the shared database. They
  were imported once and are never migrated from here.

  A site names its repository and the Privy app whose sign-ins it trusts:

      config :regent_names, repo: MySite.Repo, privy_app_id: "..."

  Reads and the claim take one of three actors: a signed-in person
  (`%{role: :human, human_account_id: integer, wallet_addresses: [...]}`), a
  paired agent (`RegentAgents.Checks.Paired`) or a fresh Privy sign-in for the
  site's own app (`RegentNames.Checks.VerifiedOwner`). Only a person claims.
  Ownership is always the actor's own verified `wallet_addresses`, lowercased.
  """
  use Ash.Domain, otp_app: :regent_names

  alias RegentNames.{Allowance, Claim, PaymentCredit}

  resources do
    resource Claim do
      define :list_my_claims, action: :mine
      define :claim_free_name, action: :claim_free, args: [:label]
    end

    resource Allowance do
      define :list_my_allowances, action: :mine
      define :use_free_claim, action: :use_free_claim
    end

    resource PaymentCredit do
      define :list_my_payment_credits, action: :mine
    end
  end

  @label_rule ~r/^[a-z0-9-]+$/

  @doc false
  def repo(_resource, _operation), do: Application.fetch_env!(:regent_names, :repo)

  @doc "Recorded name evidence only; payment and entitlement fields remain private."
  def present(claim) do
    %{
      id: Integer.to_string(claim.id),
      name: claim.fqdn,
      ens_name: claim.ens_fqdn,
      owner_address: claim.owner_address,
      status: claim.claim_status,
      transaction: claim.tx_hash,
      ens_transaction: claim.ens_tx_hash,
      claimed_at: claim.created_at,
      ens_assigned_at: claim.ens_assigned_at
    }
  end

  @doc """
  How many names the actor's wallets may still claim: free claims granted at
  the snapshot and not yet used, and paid claims bought and not yet spent.
  """
  @spec claims_available(keyword()) ::
          {:ok, %{free: non_neg_integer(), paid: non_neg_integer()}} | {:error, term()}
  def claims_available(opts) do
    with {:ok, allowances} <- list_my_allowances(opts),
         {:ok, credits} <- list_my_payment_credits(opts) do
      {:ok,
       %{
         free: Enum.sum_by(allowances, &Kernel.max(&1.snapshot_total - &1.free_mints_used, 0)),
         paid: Enum.count(credits, &is_nil(&1.consumed_at))
       }}
    end
  end

  @doc """
  What stands in the way of claiming `label`, as sentences for the person
  typing it. An empty list means the label follows every rule.
  """
  @spec label_problems(String.t()) :: [String.t()]
  def label_problems(label) do
    [
      {String.length(label) < 3, "Use at least 3 characters."},
      {String.length(label) > 14, "Use at most 14 characters."},
      {not Regex.match?(@label_rule, label), "Use only lowercase letters, numbers and hyphens."},
      {String.starts_with?(label, "-") or String.ends_with?(label, "-"),
       "A name can’t start or end with a hyphen."}
    ]
    |> Enum.filter(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  @doc "Whether any recorded claim already holds `label`, in either form of the name."
  @spec label_claimed?(String.t(), keyword()) :: {:ok, boolean()} | {:error, term()}
  def label_claimed?(label, opts) do
    Claim
    |> Ash.Query.for_read(:holding_label, %{label: label}, opts)
    |> Ash.exists(opts)
  end
end

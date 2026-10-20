defmodule RegentNames.Case do
  @moduledoc "A test with its own database transaction and synthetic names rows."
  use ExUnit.CaseTemplate

  alias RegentNames.TestRepo

  using do
    quote do
      import RegentNames.Case
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(TestRepo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  @doc "A person signed in on a site, holding `wallets`, shaped as every site's human actor is."
  def person(wallets), do: %{role: :human, human_account_id: 1, wallet_addresses: wallets}

  @doc "Inserts one synthetic claim row."
  def insert_claim(id, owner, extra \\ %{}) do
    row =
      Map.merge(
        %{
          id: id,
          parent_node: "parent",
          parent_name: "agent.base.eth",
          label: "name-#{id}",
          fqdn: "name-#{id}.agent.base.eth",
          ens_fqdn: "name-#{id}.regent.eth",
          node: "node-#{id}",
          owner_address: owner,
          tx_hash: "tx-#{id}"
        },
        extra
      )

    # Rows only a free claim writes are made here as the import made them.
    TestRepo.insert_all("basenames_mints", [row], prefix: "regent_names")
  end

  @doc "Inserts one synthetic free-claim allowance for a wallet."
  def insert_allowance(address, total, used) do
    row = %{
      parent_node: "parent",
      parent_name: "agent.base.eth",
      address: address,
      snapshot_block_number: 1,
      snapshot_total: total,
      free_mints_used: used
    }

    TestRepo.insert_all("basenames_mint_allowances", [row], prefix: "regent_names")
  end

  @doc "Inserts one synthetic paid claim for a wallet."
  def insert_payment_credit(id, address, extra \\ %{}) do
    row =
      Map.merge(
        %{
          id: id,
          parent_node: "parent",
          parent_name: "agent.base.eth",
          address: address,
          payment_tx_hash: "pay-#{id}",
          price_wei: 2_500_000_000_000_000
        },
        extra
      )

    TestRepo.insert_all("basenames_payment_credits", [row], prefix: "regent_names")
  end

  def used(address) do
    %{rows: [[used]]} =
      TestRepo.query!(
        "SELECT free_mints_used FROM regent_names.basenames_mint_allowances WHERE address = $1",
        [address]
      )

    used
  end

  def claim_count do
    %{rows: [[count]]} = TestRepo.query!("SELECT count(*) FROM regent_names.basenames_mints")
    count
  end
end

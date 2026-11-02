defmodule RegentPoints.WalletSnapshotTest do
  use ExUnit.Case, async: true
  alias Ecto.Adapters.SQL.Sandbox
  alias RegentPoints.{Repo, WalletSnapshot}

  @wallet "0x" <> String.duplicate("a", 40)
  @other "0x" <> String.duplicate("b", 40)

  setup do
    pid = Sandbox.start_owner!(Repo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end

  # Protects the owner of a past event: it is the account holding the wallet
  # then, never one that held it before or after.
  test "the owner is the account holding the wallet at that moment" do
    version(1, [@wallet], ~U[2026-11-01 10:00:00Z])
    version(1, [@other], ~U[2026-11-01 12:00:00Z])
    version(2, [@other, @wallet], ~U[2026-11-01 14:00:00Z])
    version(2, [@other], ~U[2026-11-01 16:00:00Z])

    assert WalletSnapshot.owner(@wallet, ~U[2026-11-01 09:59:59Z]) == {:error, :unknown_owner}
    assert WalletSnapshot.owner(@wallet, ~U[2026-11-01 10:00:00Z]) == {:ok, 1}
    assert WalletSnapshot.owner(@wallet, ~U[2026-11-01 13:00:00Z]) == {:error, :unknown_owner}
    assert WalletSnapshot.owner(@wallet, ~U[2026-11-01 15:00:00Z]) == {:ok, 2}
    assert WalletSnapshot.owner(@wallet, ~U[2026-11-01 17:00:00Z]) == {:error, :unknown_owner}

    version(3, [@other], ~U[2026-11-01 18:00:00Z])
    version(4, [@other], ~U[2026-11-01 18:00:00Z])
    assert WalletSnapshot.owner(@other, ~U[2026-11-01 19:00:00Z]) == {:error, :unknown_owner}
  end

  defp version(account_id, wallets, at) do
    Repo.query!(
      """
      INSERT INTO regent_points.wallet_snapshots(account_id, wallet_addresses, effective_at)
      VALUES ($1, $2, $3)
      """,
      [account_id, wallets, DateTime.to_naive(at)]
    )
  end
end

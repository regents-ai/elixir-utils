defmodule Xmtp.RoomServer.ClientCache do
  @moduledoc "Caches and refreshes per-wallet XMTP clients held in room server state."

  alias Xmtp.Principal
  alias Xmtp.RoomServer.Membership
  alias XmtpElixirSdk.Client
  alias XmtpElixirSdk.Clients
  alias XmtpElixirSdk.Types

  def ensure_join_candidate(state, _principal, wallet_address) do
    case Map.fetch(state.clients_by_wallet, wallet_address) do
      {:ok, client} ->
        {:ok, client, state}

      :error ->
        create_fun =
          if Membership.existing_membership?(state.repo, state.room, wallet_address) do
            &Clients.create/3
          else
            &Clients.build/3
          end

        with {:ok, client} <-
               create_fun.(state.runtime_name, wallet_identifier(wallet_address), env: :dev) do
          {:ok, client, put_in(state.clients_by_wallet[wallet_address], client)}
        end
    end
  end

  def ensure_registered_client(state, _principal, wallet_address) do
    case Map.fetch(state.clients_by_wallet, wallet_address) do
      {:ok, %Client{ready?: true} = client} ->
        {:ok, client, state}

      _ ->
        with {:ok, client} <-
               Clients.create(state.runtime_name, wallet_identifier(wallet_address), env: :dev) do
          {:ok, client, put_in(state.clients_by_wallet[wallet_address], client)}
        end
    end
  end

  def fetch_cached_client(state, wallet_address) do
    case Map.fetch(state.clients_by_wallet, wallet_address) do
      {:ok, client} -> {:ok, client}
      :error -> {:error, :join_required}
    end
  end

  def wallet_identifier(wallet_address) do
    %Types.Identifier{
      identifier: Principal.normalize_wallet(wallet_address),
      identifier_kind: :ethereum
    }
  end
end

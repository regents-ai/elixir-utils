defmodule Xmtp.Identity do
  @moduledoc """
  Shared XMTP identity setup for product apps.

  This module hides client registration, signature request creation, signer
  payload construction, and inbox derivation. Host apps still own persistence:
  store the returned `inbox_id` on the product account after a successful
  signature.
  """

  alias Xmtp.Principal
  alias XmtpElixirSdk.Client
  alias XmtpElixirSdk.Clients
  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Runtime
  alias XmtpElixirSdk.Signer
  alias XmtpElixirSdk.Types

  @signature_cache_table :xmtp_identity_signature_requests
  @signature_request_ttl_ms :timer.minutes(5)

  @type status ::
          :ready
          | :needs_wallet_signature
          | :too_many_devices
          | :unsupported_wallet
          | :syncing

  @type signature_request :: %{
          required(:id) => String.t(),
          required(:text) => String.t(),
          required(:client_id) => String.t(),
          required(:wallet_address) => String.t()
        }

  @type state :: %{
          required(:status) => status(),
          required(:inbox_id) => String.t() | nil,
          required(:wallet_address) => String.t(),
          required(:signature_request) => signature_request() | nil,
          required(:user_copy) => String.t()
        }

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts), do: XmtpElixirSdk.Runtime.child_spec(opts)

  @spec ensure_identity(map()) :: {:ok, state()} | {:error, term()}
  def ensure_identity(%{runtime: runtime, principal: principal} = attrs) do
    with {:ok, principal} <- normalize_principal(principal),
         {:ok, wallet_address} <- principal_wallet(principal),
         {:ok, stored_inbox_id} <- stored_inbox_id(attrs, principal) do
      inbox_id = derived_inbox_id(wallet_address)

      if stored_inbox_id == inbox_id do
        {:ok, ready_state(wallet_address, inbox_id)}
      else
        create_signature_request(runtime, wallet_address)
      end
    end
  end

  def ensure_identity(_attrs), do: {:error, :invalid_identity_request}

  @spec complete_signature(map()) :: {:ok, state()} | {:error, term()}
  def complete_signature(%{
        runtime: runtime,
        wallet_address: wallet_address,
        client_id: client_id,
        request_id: request_id,
        signature: signature
      })
      when is_binary(client_id) and is_binary(request_id) and is_binary(signature) do
    with {:ok, wallet_address} <- normalize_wallet(wallet_address),
         {:ok, cached_request} <-
           require_cached_signature_request(runtime, wallet_address, client_id, request_id),
         identifier = wallet_identifier(wallet_address),
         client = %Client{runtime: runtime_key(runtime), id: client_id},
         {:ok, signer} <- Signer.eoa(identifier, signature),
         :ok <- Clients.unsafe_apply_signature_request(client, cached_request.id, signer),
         {:ok, registered_client} <- Clients.register(client),
         :ok <- ensure_registered(registered_client) do
      delete_cached_signature_request(runtime, wallet_address)
      {:ok, ready_state(wallet_address, derived_inbox_id(wallet_address))}
    end
  end

  def complete_signature(_attrs), do: {:error, :invalid_signature_request}

  @spec ready_inbox_id(Principal.t() | map(), String.t() | nil) ::
          {:ok, String.t()} | {:error, :wallet_required | :xmtp_identity_required}
  def ready_inbox_id(principal, stored_inbox_id) do
    with {:ok, principal} <- normalize_principal(principal),
         {:ok, wallet_address} <- principal_wallet(principal),
         {:ok, stored_inbox_id} <- normalize_optional_string(stored_inbox_id),
         true <- stored_inbox_id == derived_inbox_id(wallet_address) do
      {:ok, stored_inbox_id}
    else
      nil -> {:error, :xmtp_identity_required}
      false -> {:error, :xmtp_identity_required}
      {:ok, nil} -> {:error, :xmtp_identity_required}
      {:error, :wallet_required} -> {:error, :wallet_required}
      {:error, _reason} -> {:error, :xmtp_identity_required}
    end
  end

  @spec derived_inbox_id(String.t()) :: String.t()
  def derived_inbox_id(wallet_address) when is_binary(wallet_address) do
    {:ok, wallet_address} = normalize_wallet(wallet_address)
    {:ok, inbox_id} = XmtpElixirSdk.generate_inbox_id(wallet_identifier(wallet_address), 0, 1)
    inbox_id
  end

  @spec wallet_identifier(String.t()) :: Types.Identifier.t()
  def wallet_identifier(wallet_address) when is_binary(wallet_address) do
    %Types.Identifier{
      identifier: wallet_address |> String.trim() |> String.downcase(),
      identifier_kind: :ethereum
    }
  end

  defp create_signature_request(runtime, wallet_address) do
    case cached_signature_request(runtime, wallet_address) do
      {:ok, state} ->
        {:ok, state}

      :miss ->
        with {:ok, client} <- Clients.build(runtime, wallet_identifier(wallet_address), env: :dev),
             {:ok, challenge} <- Clients.unsafe_create_inbox_signature_text(client) do
          state = %{
            status: :needs_wallet_signature,
            inbox_id: nil,
            wallet_address: wallet_address,
            signature_request: %{
              id: challenge.signature_request_id,
              text: challenge.signature_text,
              client_id: client.id,
              wallet_address: wallet_address
            },
            user_copy: "Check your wallet to finish connecting chat."
          }

          :ok = cache_signature_request(runtime, wallet_address, state)
          {:ok, state}
        end
    end
  end

  defp ready_state(wallet_address, inbox_id) do
    %{
      status: :ready,
      inbox_id: inbox_id,
      wallet_address: wallet_address,
      signature_request: nil,
      user_copy: "Chat identity connected."
    }
  end

  defp stored_inbox_id(attrs, principal) do
    attrs
    |> Map.get(:stored_inbox_id, principal.inbox_id)
    |> normalize_optional_string()
  end

  defp normalize_principal(%Principal{} = principal), do: {:ok, Principal.from(principal)}
  defp normalize_principal(%{} = attrs), do: {:ok, Principal.from(attrs)}
  defp normalize_principal(_principal), do: {:error, :wallet_required}

  defp principal_wallet(%Principal{} = principal) do
    case Principal.wallet(principal) do
      nil -> {:error, :wallet_required}
      wallet_address -> normalize_wallet(wallet_address)
    end
  end

  defp normalize_wallet(wallet_address) when is_binary(wallet_address) do
    wallet_address
    |> String.trim()
    |> case do
      "" -> {:error, :wallet_required}
      "0x" <> rest = wallet when byte_size(rest) == 40 -> {:ok, String.downcase(wallet)}
      _wallet -> {:error, :unsupported_wallet}
    end
  end

  defp normalize_wallet(_wallet_address), do: {:error, :wallet_required}

  defp normalize_optional_string(nil), do: {:ok, nil}

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:ok, nil}
      trimmed -> {:ok, trimmed}
    end
  end

  defp normalize_optional_string(_value), do: {:error, :xmtp_identity_required}

  defp ensure_registered(%Client{} = client) do
    case Clients.is_registered(client) do
      {:ok, true} -> :ok
      {:ok, false} -> {:error, Error.internal("XMTP identity did not register", %{})}
      {:error, reason} -> {:error, reason}
    end
  end

  defp require_cached_signature_request(runtime, wallet_address, client_id, request_id) do
    case cached_signature_request(runtime, wallet_address) do
      {:ok, %{signature_request: %{client_id: ^client_id, id: ^request_id} = request}} ->
        {:ok, request}

      {:ok, _state} ->
        {:error, :signature_request_mismatch}

      :miss ->
        {:error, :signature_request_expired}
    end
  end

  defp cached_signature_request(runtime, wallet_address) do
    ensure_signature_cache!()
    key = signature_cache_key(runtime, wallet_address)
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@signature_cache_table, key) do
      [{^key, %{expires_at: expires_at, state: state}}] when expires_at > now -> {:ok, state}
      [{^key, _expired}] -> :ets.delete(@signature_cache_table, key) && :miss
      [] -> :miss
    end
  end

  defp cache_signature_request(runtime, wallet_address, state) do
    ensure_signature_cache!()

    expires_at = System.monotonic_time(:millisecond) + @signature_request_ttl_ms

    true =
      :ets.insert(
        @signature_cache_table,
        {signature_cache_key(runtime, wallet_address), %{expires_at: expires_at, state: state}}
      )

    :ok
  end

  defp delete_cached_signature_request(runtime, wallet_address) do
    ensure_signature_cache!()
    :ets.delete(@signature_cache_table, signature_cache_key(runtime, wallet_address))
  end

  defp ensure_signature_cache! do
    case :ets.whereis(@signature_cache_table) do
      :undefined ->
        :ets.new(@signature_cache_table, [:named_table, :public, read_concurrency: true])

      _table ->
        :ok
    end
  end

  defp signature_cache_key(runtime, wallet_address), do: {runtime_key(runtime), wallet_address}

  defp runtime_key(%Runtime{name: name}), do: name
  defp runtime_key(runtime) when is_atom(runtime), do: runtime
end

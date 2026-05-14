defmodule XmtpElixirSdk.Clients do
  @moduledoc """
  Client lifecycle and identity operations.

  Use this module to:

  - create a ready-to-use client
  - build a client before registration
  - register a built client
  - manage accounts, recovery identifiers, and installations
  - check whether identifiers can receive XMTP messages

  In practical terms:

  - `create/3` gives you a registered client immediately
  - `build/3` gives you a client record you can register later
  - `register/1` finishes registration for a built client

  Signature-request helpers are provided for app flows where a wallet or signer
  must approve a step before the SDK applies it.
  """

  alias XmtpElixirSdk.Client
  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Internal.{IdentityServer, StatsServer}
  alias XmtpElixirSdk.Types

  @spec create(XmtpElixirSdk.Runtime.t() | atom(), Types.Identifier.t(), keyword()) ::
          {:ok, Client.t()} | {:error, Error.t()}
  def create(runtime, identifier, opts \\ []) do
    runtime = XmtpElixirSdk.Internal.Names.runtime_name(runtime)
    identifier = normalize_identifier(identifier)
    opts = Keyword.put(opts, :env, Keyword.get(opts, :env, :dev))

    with {:ok, record} <- IdentityServer.create_client(runtime, identifier, opts, true) do
      {:ok, Client.from_record(runtime, record)}
    end
  end

  @spec build(XmtpElixirSdk.Runtime.t() | atom(), Types.Identifier.t(), keyword()) ::
          {:ok, Client.t()} | {:error, Error.t()}
  def build(runtime, identifier, opts \\ []) do
    runtime = XmtpElixirSdk.Internal.Names.runtime_name(runtime)
    identifier = normalize_identifier(identifier)
    opts = Keyword.put(opts, :env, Keyword.get(opts, :env, :dev))

    with {:ok, record} <- IdentityServer.create_client(runtime, identifier, opts, false) do
      {:ok, Client.from_record(runtime, record)}
    end
  end

  @spec close(Client.t()) :: :ok
  def close(%Client{} = client), do: IdentityServer.close_client(client)

  @spec register(Client.t()) :: {:ok, Client.t()} | {:error, Error.t()}
  def register(%Client{} = client) do
    with {:ok, record} <- IdentityServer.register_client(client) do
      {:ok, Client.from_record(client.runtime, record)}
    end
  end

  @spec unsafe_create_inbox_signature_text(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def unsafe_create_inbox_signature_text(%Client{} = client) do
    IdentityServer.create_signature_request(client, :register, %{})
  end

  @spec unsafe_add_account_signature_text(Client.t(), Types.Identifier.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def unsafe_add_account_signature_text(%Client{} = client, identifier) do
    identifier = normalize_identifier(identifier)
    IdentityServer.create_signature_request(client, :add_account, %{identifier: identifier})
  end

  @spec unsafe_remove_account_signature_text(Client.t(), Types.Identifier.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def unsafe_remove_account_signature_text(%Client{} = client, identifier) do
    identifier = normalize_identifier(identifier)
    IdentityServer.create_signature_request(client, :remove_account, %{identifier: identifier})
  end

  @spec unsafe_revoke_all_other_installations_signature_text(Client.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def unsafe_revoke_all_other_installations_signature_text(%Client{} = client) do
    IdentityServer.create_signature_request(client, :revoke_all_other_installations, %{})
  end

  @spec unsafe_revoke_installations_signature_text(Client.t(), [String.t()]) ::
          {:ok, map()} | {:error, Error.t()}
  def unsafe_revoke_installations_signature_text(%Client{} = client, installation_ids) do
    IdentityServer.create_signature_request(client, :revoke_installations, %{
      installation_ids: installation_ids
    })
  end

  @spec unsafe_change_recovery_identifier_signature_text(Client.t(), Types.Identifier.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def unsafe_change_recovery_identifier_signature_text(%Client{} = client, identifier) do
    identifier = normalize_identifier(identifier)

    IdentityServer.create_signature_request(client, :change_recovery_identifier, %{
      identifier: identifier
    })
  end

  @spec unsafe_apply_signature_request(Client.t(), String.t(), map()) :: :ok | {:error, Error.t()}
  def unsafe_apply_signature_request(%Client{} = client, signature_request_id, signer) do
    IdentityServer.apply_signature_request(client, signature_request_id, signer)
  end

  @spec is_registered(Client.t()) :: {:ok, boolean()} | {:error, Error.t()}
  def is_registered(%Client{} = client) do
    with {:ok, state} <- IdentityServer.client_state(client) do
      {:ok, state.registered?}
    end
  end

  @spec can_message(Client.t() | XmtpElixirSdk.Runtime.t() | atom(), [Types.Identifier.t()]) ::
          {:ok, map()} | {:error, Error.t()}
  def can_message(%Client{runtime: runtime}, identifiers),
    do: IdentityServer.can_message(runtime, normalize_identifiers(identifiers))

  def can_message(runtime, identifiers),
    do: IdentityServer.can_message(runtime, normalize_identifiers(identifiers))

  @spec fetch_inbox_id_by_identifier(
          Client.t() | XmtpElixirSdk.Runtime.t() | atom(),
          Types.Identifier.t()
        ) ::
          {:ok, String.t() | nil} | {:error, Error.t()}
  def fetch_inbox_id_by_identifier(%Client{runtime: runtime}, identifier),
    do: fetch_inbox_id_by_identifier(runtime, identifier)

  def fetch_inbox_id_by_identifier(runtime, identifier) do
    identifier = normalize_identifier(identifier)

    case IdentityServer.get_inbox_id_for_identifier(runtime, identifier) do
      {:ok, inbox_id} -> {:ok, inbox_id}
      {:error, %Error{kind: :not_found}} -> {:ok, nil}
      {:error, error} -> {:error, error}
    end
  end

  @spec fetch_key_package_statuses(Client.t(), [String.t()]) ::
          {:ok, [Types.KeyPackageStatus.t()]} | {:error, Error.t()}
  def fetch_key_package_statuses(%Client{} = client, installation_ids) do
    StatsServer.bump_api(client.runtime, :fetch_key_package)

    {:ok,
     Enum.map(installation_ids, fn installation_id ->
       %Types.KeyPackageStatus{
         installation_id: installation_id,
         valid: true,
         not_before: 0,
         not_after: 0,
         validation_error: nil
       }
     end)}
  end

  @spec verify_signed_with_installation_key(Client.t(), String.t(), binary()) ::
          {:ok, boolean()} | {:error, Error.t()}
  def verify_signed_with_installation_key(%Client{id: id}, signature_text, signature_bytes) do
    {:ok, :crypto.hash(:sha256, "#{id}:#{signature_text}") == signature_bytes}
  end

  @spec verify_signed_with_public_key(Client.t(), String.t(), binary(), binary()) ::
          {:ok, boolean()} | {:error, Error.t()}
  def verify_signed_with_public_key(%Client{}, signature_text, signature_bytes, public_key) do
    digest = :crypto.hash(:sha256, signature_text)

    case ExSecp256k1.verify(digest, signature_bytes, public_key) do
      :ok -> {:ok, true}
      _error -> {:ok, false}
    end
  end

  @spec api_statistics(Client.t()) :: {:ok, Types.ApiStats.t()} | {:error, Error.t()}
  def api_statistics(%Client{} = client), do: XmtpElixirSdk.Debug.api_statistics(client)

  @spec api_identity_statistics(Client.t()) ::
          {:ok, Types.IdentityStats.t()} | {:error, Error.t()}
  def api_identity_statistics(%Client{} = client),
    do: XmtpElixirSdk.Debug.api_identity_statistics(client)

  @spec api_aggregate_statistics(Client.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def api_aggregate_statistics(%Client{} = client),
    do: XmtpElixirSdk.Debug.api_aggregate_statistics(client)

  @spec clear_all_statistics(Client.t()) :: :ok | {:error, Error.t()}
  def clear_all_statistics(%Client{} = client),
    do: XmtpElixirSdk.Debug.clear_all_statistics(client)

  defp normalize_identifiers(identifiers) when is_list(identifiers) do
    Enum.map(identifiers, &normalize_identifier/1)
  end

  defp normalize_identifier(
         %Types.Identifier{identifier_kind: :ethereum, identifier: identifier} = value
       )
       when is_binary(identifier) do
    %Types.Identifier{value | identifier: identifier |> String.trim() |> String.downcase()}
  end

  defp normalize_identifier(%Types.Identifier{} = value), do: value
end

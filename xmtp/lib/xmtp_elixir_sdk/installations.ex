defmodule XmtpElixirSdk.Installations do
  @moduledoc """
  Public helpers for working with installations and revocation flows.
  """

  alias XmtpElixirSdk.Client
  alias XmtpElixirSdk.Clients
  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Types

  @spec all(Types.InboxState.t()) :: [Types.Installation.t()]
  def all(%Types.InboxState{installations: installations}), do: installations

  @spec ids(Types.InboxState.t() | [Types.Installation.t()]) :: [String.t()]
  def ids(%Types.InboxState{installation_ids: installation_ids}), do: installation_ids
  def ids(installations) when is_list(installations), do: Enum.map(installations, & &1.id)

  @spec includes?(Types.InboxState.t() | [Types.Installation.t()], String.t()) :: boolean()
  def includes?(state_or_installations, installation_id) when is_binary(installation_id) do
    installation_id in ids(state_or_installations)
  end

  @spec revoke_signature_text(Client.t(), [String.t()]) ::
          {:ok, map()} | {:error, Error.t()}
  def revoke_signature_text(%Client{} = client, installation_ids)
      when is_list(installation_ids) do
    Clients.unsafe_revoke_installations_signature_text(client, installation_ids)
  end

  @spec revoke(Client.t(), [String.t()], map()) :: :ok | {:error, Error.t()}
  def revoke(%Client{} = client, installation_ids, signer \\ %{})
      when is_list(installation_ids) do
    Clients.revoke_installations(client, installation_ids, signer)
  end
end

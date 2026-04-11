defmodule XmtpElixirSdk.InboxState do
  @moduledoc """
  Public inbox state helpers for lookups and common state checks.
  """

  alias XmtpElixirSdk.Client
  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Internal.IdentityServer
  alias XmtpElixirSdk.Runtime
  alias XmtpElixirSdk.Types

  @spec fetch(Runtime.t() | atom(), [String.t()], boolean()) ::
          {:ok, [Types.InboxState.t()]} | {:error, Error.t()}
  def fetch(runtime, inbox_ids, refresh_from_network \\ true) when is_list(inbox_ids) do
    IdentityServer.fetch_inbox_states(runtime, inbox_ids, refresh_from_network)
  end

  @spec fetch_for_client(Client.t(), [String.t()], boolean()) ::
          {:ok, [Types.InboxState.t()]} | {:error, Error.t()}
  def fetch_for_client(%Client{} = client, inbox_ids, refresh_from_network \\ false)
      when is_list(inbox_ids) do
    IdentityServer.inbox_state_from_inbox_ids(client, inbox_ids, refresh_from_network)
  end

  @spec account_identifiers(Types.InboxState.t()) :: [Types.Identifier.t()]
  def account_identifiers(%Types.InboxState{account_identifiers: identifiers}), do: identifiers

  @spec installation_ids(Types.InboxState.t()) :: [String.t()]
  def installation_ids(%Types.InboxState{installation_ids: installation_ids}),
    do: installation_ids

  @spec installations(Types.InboxState.t()) :: [Types.Installation.t()]
  def installations(%Types.InboxState{installations: installations}), do: installations

  @spec includes_identifier?(Types.InboxState.t(), Types.Identifier.t()) :: boolean()
  def includes_identifier?(
        %Types.InboxState{account_identifiers: identifiers},
        %Types.Identifier{} = identifier
      ) do
    Enum.any?(identifiers, &(&1 == identifier))
  end

  @spec includes_installation?(Types.InboxState.t(), String.t()) :: boolean()
  def includes_installation?(%Types.InboxState{} = state, installation_id)
      when is_binary(installation_id) do
    installation_id in installation_ids(state)
  end
end

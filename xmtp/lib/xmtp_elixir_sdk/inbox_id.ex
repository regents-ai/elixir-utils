defmodule XmtpElixirSdk.InboxId do
  @moduledoc """
  Public inbox ID helpers for generating and resolving inbox IDs.
  """

  alias XmtpElixirSdk.Clients
  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Runtime
  alias XmtpElixirSdk.Types

  @spec generate(Types.Identifier.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def generate(%Types.Identifier{} = identifier, kind, nonce \\ 1) do
    data = "#{identifier.identifier_kind}:#{identifier.identifier}|#{kind}|#{nonce}"
    {:ok, Base.encode16(:crypto.hash(:sha256, data), case: :lower) |> binary_part(0, 32)}
  end

  @spec fetch(Runtime.t() | atom(), Types.Identifier.t()) ::
          {:ok, String.t() | nil} | {:error, Error.t()}
  def fetch(runtime, %Types.Identifier{} = identifier) do
    Clients.fetch_inbox_id_by_identifier(runtime, identifier)
  end

  @spec known?(Runtime.t() | atom(), Types.Identifier.t()) :: {:ok, boolean()} | {:error, Error.t()}
  def known?(runtime, %Types.Identifier{} = identifier) do
    with {:ok, inbox_id} <- fetch(runtime, identifier) do
      {:ok, not is_nil(inbox_id)}
    end
  end
end

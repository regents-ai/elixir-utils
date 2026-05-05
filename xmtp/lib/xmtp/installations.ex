defmodule Xmtp.Installations do
  @moduledoc """
  Product-safe installation status and repair helpers.
  """

  alias XmtpElixirSdk.Client
  alias XmtpElixirSdk.Installations, as: LowLevelInstallations
  alias XmtpElixirSdk.Preferences
  alias XmtpElixirSdk.Types

  @default_device_limit 5

  @type status :: %{
          required(:status) => :ok | :too_many_devices,
          required(:installation_count) => non_neg_integer(),
          required(:device_limit) => pos_integer(),
          required(:installation_ids) => [String.t()],
          required(:user_copy) => String.t()
        }

  @spec status(Client.t() | Types.InboxState.t(), keyword()) :: {:ok, status()} | {:error, term()}
  def status(client_or_state, opts \\ [])

  def status(%Client{} = client, opts) do
    with {:ok, inbox_state} <- Preferences.fetch_inbox_state(client) do
      status(inbox_state, opts)
    end
  end

  def status(%Types.InboxState{} = inbox_state, opts) do
    device_limit = Keyword.get(opts, :device_limit, @default_device_limit)
    installation_ids = LowLevelInstallations.ids(inbox_state)
    installation_count = length(installation_ids)

    status =
      if installation_count > device_limit do
        :too_many_devices
      else
        :ok
      end

    {:ok,
     %{
       status: status,
       installation_count: installation_count,
       device_limit: device_limit,
       installation_ids: installation_ids,
       user_copy: user_copy(status)
     }}
  end

  @spec recommend_cleanup(Client.t() | Types.InboxState.t(), keyword()) ::
          {:ok,
           %{required(:installation_ids) => [String.t()], required(:user_copy) => String.t()}}
          | {:error, term()}
  def recommend_cleanup(client_or_state, opts \\ []) do
    current_installation_id = Keyword.get(opts, :current_installation_id)

    with {:ok, status} <- status(client_or_state, opts) do
      cleanup_ids =
        status.installation_ids
        |> Enum.reject(&(&1 == current_installation_id))
        |> Enum.take(max(status.installation_count - status.device_limit, 0))

      {:ok,
       %{
         installation_ids: cleanup_ids,
         user_copy: "Remove an old chat session or use a different wallet."
       }}
    end
  end

  @spec revoke_old_installation(Client.t(), String.t(), map()) :: :ok | {:error, term()}
  def revoke_old_installation(%Client{} = client, installation_id, signer)
      when is_binary(installation_id) and is_map(signer) do
    LowLevelInstallations.revoke(client, [installation_id], signer)
  end

  defp user_copy(:ok), do: "This wallet can use chat."

  defp user_copy(:too_many_devices),
    do: "This wallet has too many chat devices connected."
end

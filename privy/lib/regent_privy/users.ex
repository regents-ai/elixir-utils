defmodule RegentPrivy.Users do
  @moduledoc """
  Privy's server API for an agent that owns its account: finding the Privy user a
  wallet is linked to, and making a Privy user whose only login is that wallet.

  The user made here signs in on the site with that wallet like anyone else, so the
  agent's account is an ordinary Privy account. Only a site's server calls this,
  for a wallet whose signature it has already checked.

  Apps pass their Privy settings per call: `:app_id`, `:app_secret`, and
  `:req_options`, which are added to every request (how tests answer for Privy:
  `plug: {Req.Test, RegentPrivy.Users}`). Errors are fixed atoms:
  `:missing_privy_config`, `:invalid_wallet_address`, `:not_found`,
  `:privy_refused` (Privy answered with any other refusal) and
  `:privy_unavailable` (Privy could not be reached or failed).

  A user comes back as its Privy id and `only_wallet`: whether the wallet asked
  about is its one linked account, so the site can tell an agent's own user from a
  person's account that also links the wallet.
  """

  @wallet_address_pattern ~r/\A0x[0-9a-fA-F]{40}\z/u

  @type user :: %{privy_user_id: String.t(), only_wallet: boolean()}
  @type error ::
          :missing_privy_config
          | :invalid_wallet_address
          | :not_found
          | :privy_refused
          | :privy_unavailable

  @doc "The Privy user `address` is linked to, or `:not_found` when it is linked to none."
  @spec by_wallet(String.t(), keyword()) :: {:ok, user()} | {:error, error()}
  def by_wallet(address, opts) do
    with {:ok, address} <- wallet(address) do
      request(opts, address, url: "/v1/users/wallet/address", json: %{address: address})
    end
  end

  @doc """
  Makes a Privy user whose one linked account, and so its one way to sign in, is
  the Ethereum wallet `address`.
  """
  @spec create_with_wallet(String.t(), keyword()) :: {:ok, user()} | {:error, error()}
  def create_with_wallet(address, opts) do
    with {:ok, address} <- wallet(address) do
      request(opts, address,
        url: "/v1/users",
        json: %{linked_accounts: [%{type: "wallet", address: address, chain_type: "ethereum"}]}
      )
    end
  end

  defp wallet(address) when is_binary(address) do
    if Regex.match?(@wallet_address_pattern, address),
      do: {:ok, String.downcase(address)},
      else: {:error, :invalid_wallet_address}
  end

  defp wallet(_address), do: {:error, :invalid_wallet_address}

  defp request(opts, address, options) do
    with {:ok, app_id, secret} <- configuration(opts) do
      [
        base_url: "https://api.privy.io",
        method: :post,
        auth: {:basic, app_id <> ":" <> secret},
        headers: [{"privy-app-id", app_id}],
        retry: false,
        receive_timeout: 5_000
      ]
      |> Req.new()
      |> Req.merge(Keyword.get(opts, :req_options, []))
      |> Req.request(options)
      |> answer(address)
    end
  end

  defp configuration(opts) do
    case {opts[:app_id], opts[:app_secret]} do
      {app, secret} when is_binary(app) and app != "" and is_binary(secret) and secret != "" ->
        {:ok, app, secret}

      _missing ->
        {:error, :missing_privy_config}
    end
  end

  defp answer(
         {:ok, %Req.Response{status: 200, body: %{"id" => "did:privy:" <> _ = id} = user}},
         address
       ),
       do: {:ok, %{privy_user_id: id, only_wallet: only_wallet?(user, address)}}

  defp answer({:ok, %Req.Response{status: 404}}, _address), do: {:error, :not_found}

  defp answer({:ok, %Req.Response{status: status}}, _address) when status in 400..499,
    do: {:error, :privy_refused}

  defp answer(_failed, _address), do: {:error, :privy_unavailable}

  defp only_wallet?(%{"linked_accounts" => [%{"type" => "wallet", "address" => linked}]}, address)
       when is_binary(linked),
       do: String.downcase(linked) == address

  defp only_wallet?(_user, _address), do: false
end

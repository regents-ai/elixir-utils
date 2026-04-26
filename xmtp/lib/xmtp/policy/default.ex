defmodule Xmtp.Policy.Default do
  @moduledoc false

  @behaviour Xmtp.Policy

  alias Xmtp.Principal
  alias Xmtp.RoomDefinition

  @impl true
  def allow_join(%RoomDefinition{} = definition, %Principal{} = principal, claims) do
    allowed_kinds =
      definition.policy_options
      |> Map.get(:allowed_kinds, [:human])
      |> List.wrap()

    required_claims =
      definition.policy_options
      |> Map.get(:required_claims, %{})
      |> Map.new()

    allowed_wallets =
      definition.policy_options
      |> Map.get(:allowed_wallets, [])
      |> List.wrap()
      |> Enum.map(&Principal.normalize_wallet/1)
      |> Enum.reject(&is_nil/1)

    cond do
      is_nil(Principal.wallet(principal)) ->
        {:error, :wallet_required}

      Principal.kind(principal) not in allowed_kinds ->
        {:error, :join_not_allowed}

      allowed_wallets != [] and Principal.wallet(principal) not in allowed_wallets ->
        {:error, :join_not_allowed}

      not required_claims_match?(required_claims, claims || %{}) ->
        {:error, :join_not_allowed}

      true ->
        :ok
    end
  end

  defp required_claims_match?(required_claims, claims) do
    Enum.all?(required_claims, fn {key, expected} ->
      Map.get(claims, key) == expected ||
        Map.get(claims, Atom.to_string(key)) == expected
    end)
  end
end

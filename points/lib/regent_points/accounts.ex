defmodule RegentPoints.Accounts do
  @moduledoc "Host callbacks for canonical, server-verified account and agent information. Never accept browser attribution."
  @callback human(pos_integer()) :: %{
              wallet_address: String.t() | nil,
              wallet_addresses: [String.t()]
            }
  @callback wallet_holders([String.t()]) :: [%{id: pos_integer()}]
  @callback agent_names(pos_integer(), [String.t()]) ::
              {:ok, %{String.t() => String.t()}} | {:error, term()}
end

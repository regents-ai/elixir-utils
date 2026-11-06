defmodule RegentPoints.Accounts do
  @moduledoc "Host callbacks for canonical, server-verified account and agent information. Never accept browser attribution."
  @callback human(pos_integer()) :: %{
              wallet_address: String.t() | nil,
              wallet_addresses: [String.t()]
            }
  @callback agent_names(pos_integer(), [String.t()]) ::
              {:ok, %{String.t() => String.t()}} | {:error, term()}

  @doc """
  The public name and picture of each account, as the site shows them to other
  people: `squares` and `picture` are image addresses, either may be `nil`.
  Nothing else about an account is returned.
  """
  @callback people([pos_integer()]) ::
              {:ok,
               %{
                 pos_integer() => %{
                   name: String.t(),
                   squares: String.t() | nil,
                   picture: String.t() | nil
                 }
               }}
              | {:error, term()}
end

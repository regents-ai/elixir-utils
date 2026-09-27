defmodule RegentERC8004.Ref do
  @moduledoc "Validated registry + uint256 agent identity. Validation is syntax, not ownership proof."
  @enforce_keys [:registry, :chain_id, :agent_id]
  defstruct [:registry, :chain_id, :agent_id]

  @type t :: %__MODULE__{
          registry: String.t(),
          chain_id: pos_integer(),
          agent_id: non_neg_integer()
        }
  @max_id Integer.pow(2, 256) - 1

  def new(registry, id) when is_binary(registry) and byte_size(registry) <= 128 do
    with [_, chain, address] <-
           Regex.run(~r/\Aeip155:([1-9][0-9]*):(0x[0-9a-fA-F]{40})\z/, registry),
         {:ok, number} <- token_id(id) do
      {:ok,
       %__MODULE__{
         registry: "eip155:#{chain}:#{String.downcase(address)}",
         chain_id: String.to_integer(chain),
         agent_id: number
       }}
    else
      _ -> {:error, :invalid_identity}
    end
  end

  def new(_, _), do: {:error, :invalid_identity}

  def key(%__MODULE__{chain_id: chain, agent_id: id}), do: "#{chain}:#{id}"

  defp token_id(id) when is_integer(id) and id >= 0 and id <= @max_id, do: {:ok, id}

  defp token_id(id) when is_binary(id) and byte_size(id) <= 78 do
    if Regex.match?(~r/\A(?:0|[1-9][0-9]*)\z/, id),
      do: token_id(String.to_integer(id)),
      else: :error
  end

  defp token_id(_), do: :error
end

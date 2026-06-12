defmodule AgentEns.Display do
  @moduledoc """
  Display-name selection shared by Regent apps.

  One rule, implemented once: a verified ENS primary name wins, then the
  app-provided fallback (a human's display name or an agent's label), then
  the truncated wallet address.
  """

  alias AgentEns.Address

  @doc """
  Picks the display name for an author.

  Blank strings count as missing. When everything is missing or invalid,
  returns `"Unknown"`.

      iex> AgentEns.Display.name("alice.eth", "Alice", "0x1234567890abcdef1234567890abcdef12345678")
      "alice.eth"

      iex> AgentEns.Display.name(nil, "Alice", "0x1234567890abcdef1234567890abcdef12345678")
      "Alice"

      iex> AgentEns.Display.name(nil, " ", "0x1234567890abcdef1234567890abcdef12345678")
      "0x1234…5678"

      iex> AgentEns.Display.name(nil, nil, nil)
      "Unknown"
  """
  @spec name(term(), term(), term()) :: String.t()
  def name(ens_name, fallback_name, wallet_address) do
    present(ens_name) || present(fallback_name) || truncate_wallet(wallet_address) || "Unknown"
  end

  @doc """
  Truncates a wallet address for display: `0x1234…abcd`.

  Returns `nil` when the value is not a well-formed address.

      iex> AgentEns.Display.truncate_wallet("0x1234567890ABCDEF1234567890abcdef12345678")
      "0x1234…5678"

      iex> AgentEns.Display.truncate_wallet("nope")
      nil
  """
  @spec truncate_wallet(term()) :: String.t() | nil
  def truncate_wallet(wallet_address) do
    case Address.normalize(wallet_address) do
      nil -> nil
      "0x" <> hex -> "0x" <> String.slice(hex, 0, 4) <> "…" <> String.slice(hex, -4, 4)
    end
  end

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present(_value), do: nil
end

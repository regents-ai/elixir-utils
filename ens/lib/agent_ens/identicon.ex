defmodule AgentEns.Identicon do
  @moduledoc """
  Deterministic pixel-identicon avatars derived from wallet addresses.

  Renders a 5x5 horizontally mirrored pixel grid as inline SVG. The same
  wallet always yields the same avatar; colors and cells derive from a
  SHA-256 digest of the normalized address, so the output contains only
  generated numeric values — it is safe to embed as raw markup.

  Shape follows the Regent brand split: `:circle` for humans, `:square`
  for agents.
  """

  alias AgentEns.Address

  @grid 5
  @half 3

  @doc """
  Returns an SVG identicon string for `wallet_address`.

  Options:

    * `:shape` — `:circle` (default) or `:square`
    * `:size` — rendered width/height in pixels (default 40)

  Invalid or missing wallets still produce a deterministic avatar from the
  raw value, so callers never need a fallback image. The markup carries no
  element ids, so the same avatar can repeat freely within one document
  (shape is cut with a CSS corner radius rather than a clip path).
  """
  @spec svg(term(), keyword()) :: String.t()
  def svg(wallet_address, opts \\ []) do
    shape = Keyword.get(opts, :shape, :circle)
    size = Keyword.get(opts, :size, 40)

    seed = :crypto.hash(:sha256, seed_input(wallet_address))
    <<hue_a, hue_b, rest::binary>> = seed

    hue = rem(hue_a * 256 + hue_b, 360)
    foreground = "hsl(#{hue}, 62%, 58%)"
    background = "hsl(#{rem(hue + 24, 360)}, 28%, 16%)"

    cells = cells(rest)

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{size}" height="#{size}" viewBox="0 0 #{@grid} #{@grid}" role="img" aria-hidden="true" style="border-radius:#{radius(shape)};overflow:hidden"><g shape-rendering="crispEdges"><rect width="#{@grid}" height="#{@grid}" fill="#{background}"/>#{cell_rects(cells, foreground)}</g></svg>
    """
    |> String.trim_trailing()
  end

  defp seed_input(wallet_address) do
    case Address.normalize(wallet_address) do
      nil -> "fallback:" <> inspect(wallet_address)
      wallet -> wallet
    end
  end

  # 15 bits drive a 3-column half grid mirrored onto 5 columns.
  defp cells(<<bits::bitstring>>) do
    for row <- 0..(@grid - 1), col <- 0..(@half - 1), bit_on?(bits, row * @half + col) do
      {row, col}
    end
  end

  defp bit_on?(bits, index) do
    <<_skip::size(index), bit::1, _rest::bitstring>> = bits
    bit == 1
  end

  defp cell_rects(cells, fill) do
    Enum.map_join(cells, fn {row, col} ->
      mirrored = @grid - 1 - col

      rect(col, row, fill) <>
        if mirrored == col, do: "", else: rect(mirrored, row, fill)
    end)
  end

  defp rect(x, y, fill), do: ~s(<rect x="#{x}" y="#{y}" width="1" height="1" fill="#{fill}"/>)

  defp radius(:square), do: "18%"
  defp radius(:circle), do: "50%"
end

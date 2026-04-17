defmodule Siwa.Identity do
  @header "# SIWA Identity"

  def read(path) do
    with {:ok, body} <- File.read(path) do
      {:ok, parse(body)}
    end
  end

  def write(path, attrs) do
    body = render(attrs)
    File.write(path, body)
  end

  def parse(body) do
    body
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, ": ", parts: 2) do
        ["- " <> key, value] -> Map.put(acc, normalize_key(key), value)
        _ -> acc
      end
    end)
  end

  def render(attrs) do
    attrs = Enum.into(attrs, %{})

    lines = [
      @header,
      "",
      "- Address: #{attrs[:address] || attrs["address"] || ""}",
      "- Agent ID: #{attrs[:agent_id] || attrs["agent_id"] || attrs["agentId"] || ""}",
      "- Agent Registry: #{attrs[:agent_registry] || attrs["agent_registry"] || attrs["agentRegistry"] || ""}",
      "- Chain ID: #{attrs[:chain_id] || attrs["chain_id"] || attrs["chainId"] || ""}",
      "- Endpoint: #{attrs[:endpoint] || attrs["endpoint"] || ""}"
    ]

    Enum.join(lines, "\n") <> "\n"
  end

  defp normalize_key("Address"), do: :address
  defp normalize_key("Agent ID"), do: :agent_id
  defp normalize_key("Agent Registry"), do: :agent_registry
  defp normalize_key("Chain ID"), do: :chain_id
  defp normalize_key("Endpoint"), do: :endpoint
  defp normalize_key(other), do: String.to_atom(other)
end

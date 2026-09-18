defmodule RegentAgentAccess.Recovery do
  @moduledoc """
  Error bodies that tell a reader where to go next, without request, session or
  exception details. The product supplies the status title and its own links.
  """

  @doc "A Markdown error page: the status `title` and `links` as `{label, url}` pairs."
  @spec markdown(String.t(), [{String.t(), String.t()}]) :: String.t()
  def markdown(title, links) do
    "# #{title}\n\nThis request could not be completed. Use these public entry points to continue:\n\n" <>
      Enum.map_join(links, "\n", fn {label, url} -> "- [#{label}](#{url})" end) <> "\n"
  end

  @doc "A JSON error body: the status `detail`, a code derived from it, and the product's `hint`."
  @spec json(String.t(), String.t()) :: map()
  def json(detail, hint) do
    %{
      errors: %{
        detail: detail,
        code: detail |> String.downcase() |> String.replace(" ", "_"),
        hint: hint
      }
    }
  end
end

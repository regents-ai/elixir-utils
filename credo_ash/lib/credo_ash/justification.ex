defmodule CredoAsh.Justification do
  @moduledoc """
  Shared handling for escape hatches that are allowed when they are explained.

  Some findings are not defects on their own — going around Ash, or turning
  policies off, is occasionally the right answer. What makes them safe is a
  reader being able to tell a deliberate choice from an accident, so a comment
  next to the line clears the finding.
  """

  @doc """
  Whether the given line has been explained by a comment.

  The unit is the enclosing function, not the single line. People document a
  cleanup block once and then write five deletes under it, and demanding a
  repeated comment above each one would produce noise rather than clarity. So a
  comment anywhere inside the enclosing `def`/`defp` — or in the comment block
  directly above its head — clears every finding in that function. The trade is
  deliberate: an unrelated comment in the same function will also clear them.
  """
  @spec justified?(Credo.SourceFile.t(), pos_integer()) :: boolean()
  def justified?(source_file, line_no) do
    lines = Credo.SourceFile.lines(source_file)

    case Enum.find(lines, fn {no, _line} -> no == line_no end) do
      nil -> false
      {_no, line} -> trailing_comment?(line) or explained_above?(line_no, lines)
    end
  end

  defp explained_above?(line_no, lines) do
    lines
    |> Enum.slice((scope_start(line_no, lines) - 1)..(line_no - 2)//1)
    |> Enum.any?(fn {_no, line} -> comment?(line) end)
  end

  # The first line of the region a comment can speak for: the enclosing function
  # head, extended up through any comment block sitting directly on top of it.
  defp scope_start(line_no, lines) do
    head =
      lines
      |> Enum.take(line_no - 1)
      |> Enum.reverse()
      |> Enum.find(fn {_no, line} -> function_head?(line) end)

    case head do
      nil -> 1
      {no, _line} -> climb_comments(no, lines)
    end
  end

  defp climb_comments(no, lines) when no > 1 do
    case Enum.find(lines, fn {n, _line} -> n == no - 1 end) do
      {_n, line} -> if comment?(line), do: climb_comments(no - 1, lines), else: no
      nil -> no
    end
  end

  defp climb_comments(no, _lines), do: no

  defp function_head?(line), do: Regex.match?(~r/^\s*defp?\s/, line)

  defp comment?(line), do: String.starts_with?(String.trim(line), "#")

  defp trailing_comment?(line) do
    case String.split(line, "#", parts: 2) do
      [_code, comment] -> String.trim(comment) != ""
      _ -> false
    end
  end
end

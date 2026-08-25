defmodule CredoAsh.Check.Warning.UnjustifiedAuthorizeFalse do
  use Credo.Check,
    id: "CRA1007",
    base_priority: :high,
    category: :warning,
    tags: [:credo_ash, :security],
    explanations: [
      check: """
      `authorize?: false` turns off every policy for that call. It is sometimes
      the right answer — a trusted background job, a seed script — but it always
      needs a reason recorded next to it, or the next reader cannot tell an
      intentional escape hatch from an accident.

          # bad
          Ash.read!(query, authorize?: false)

          # good
          # Runs in the indexer with no actor; rows are chain data, not user data.
          Ash.read!(query, authorize?: false)
      """
    ]

  @pattern ~r/authorize\?:\s*false/

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    lines = SourceFile.lines(source_file)

    lines
    |> Enum.filter(fn {_line_no, line} -> Regex.match?(@pattern, line) end)
    |> Enum.reject(fn {line_no, line} -> justified?(line, line_no, lines) end)
    |> Enum.map(fn {line_no, _line} -> issue_for(issue_meta, line_no) end)
  end

  defp justified?(line, line_no, lines) do
    trailing_comment?(line) or preceded_by_comment?(line_no, lines)
  end

  defp trailing_comment?(line) do
    line
    |> String.split("#", parts: 2)
    |> case do
      [_code, comment] -> String.trim(comment) != ""
      _ -> false
    end
  end

  defp preceded_by_comment?(line_no, lines) do
    lines
    |> Enum.take(line_no - 1)
    |> Enum.reverse()
    |> Enum.find(fn {_no, line} -> String.trim(line) != "" end)
    |> case do
      {_no, line} -> String.starts_with?(String.trim(line), "#")
      nil -> false
    end
  end

  defp issue_for(issue_meta, line_no) do
    format_issue(issue_meta,
      message:
        "`authorize?: false` with no justification comment — say why policies are skipped here.",
      trigger: "authorize?: false",
      line_no: line_no
    )
  end
end

defmodule RegentFormat.NameTest do
  @moduledoc """
  The name rule. Invariants: a name made only of spaces, marks and fillers is
  refused, a filler is refused wherever it stands, and a name with a visible
  character and nothing hidden is kept.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  @fillers [0x115F, 0x1160, 0x3164, 0xFFA0, 0x2800]
  @invisible @fillers ++ [?\s, 0x3000, 0x2003, 0x0301, 0x0308, 0x20DD]

  defp name?(text), do: Regex.match?(RegentFormat.Name.pattern(), text)

  property "a name of nothing a person can see is refused" do
    check all(codepoints <- list_of(member_of(@invisible), min_length: 1, max_length: 40)) do
      refute name?(List.to_string(codepoints))
    end
  end

  property "a filler is refused wherever it stands" do
    check all(
            before <- string(:alphanumeric, min_length: 1),
            after_ <- string(:alphanumeric),
            filler <- member_of(@fillers)
          ) do
      refute name?(before <> <<filler::utf8>> <> after_)
    end
  end

  property "a visible name with nothing hidden is kept" do
    check all(
            text <- string(:alphanumeric, min_length: 1),
            spaced <- member_of(["", " ", " Zoë", "　山田", " é"])
          ) do
      assert name?(text <> spaced)
    end
  end
end

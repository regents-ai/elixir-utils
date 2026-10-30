defmodule RegentFormat.TextTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  doctest RegentFormat.Text

  # Visible letters, the hidden characters a name refuses, and the joiners and flag
  # parts a name keeps only in place.
  @pieces [
    "a",
    "Zoë",
    " ",
    "👩",
    "\u200D",
    "\u200C",
    "\u202E",
    "\u0000",
    "\u2028",
    "\u00AD",
    "\u{1F3F4}",
    "\u{E0067}",
    "\u{E007F}",
    "\n",
    "\r\n",
    "\r",
    "\t"
  ]

  property "a text matches when each of its lines would as a name" do
    check all(parts <- list_of(member_of(@pieces), max_length: 12)) do
      text = Enum.join(parts)
      lines = String.split(text, ["\r\n", "\n", "\t"])

      assert Regex.match?(RegentFormat.Text.pattern(), text) ==
               Enum.all?(lines, &Regex.match?(RegentFormat.Name.pattern(), &1))
    end
  end
end

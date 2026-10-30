defmodule RegentFormat.Name do
  @moduledoc """
  The one rule for a name a person or an agent picks, which shows on every Regent
  site: a person's display name and an agent's name.

  A name holds no hidden characters (founder, 2026-10-19): no control, line or
  paragraph separator, or format character, which covers the marks that turn the
  text around them the other way. Two format characters are kept where they draw
  something: a zero-width joiner or non-joiner between two visible characters
  (emoji joins, Persian script), and tag characters inside a complete flag, from
  U+1F3F4 to U+E007F.

  Nor does it hold the fillers that draw nothing though they count as letters or
  symbols: the Hangul fillers U+115F, U+1160, U+3164 and U+FFA0 and the blank
  braille pattern U+2800. And it shows at least one character that is not a space
  or a mark, so a name is never made of nothing a person can see.
  """

  @doc ~S"""
  The pattern a whole name matches, for an Ash `match:` constraint.

      iex> Regex.match?(RegentFormat.Name.pattern(), "Zoë 👩\u200D💻")
      true

      iex> Regex.match?(RegentFormat.Name.pattern(), "Ada\u202Egnp.exe")
      false

      iex> Regex.match?(RegentFormat.Name.pattern(), "\u3164\u3164")
      false
  """
  @spec pattern() :: Regex.t()
  def pattern,
    do:
      ~r/\A(?=.*[^\p{Cc}\p{Cf}\p{Z}\p{M}\x{115F}\x{1160}\x{3164}\x{FFA0}\x{2800}])(?:\x{1F3F4}[\x{E0020}-\x{E007E}]+\x{E007F}|(?<=[^\p{Cc}\p{Cf}\p{Z}])[\x{200C}\x{200D}](?=[^\p{Cc}\p{Cf}\p{Z}])|[^\p{Cc}\p{Cf}\p{Zl}\p{Zp}\x{115F}\x{1160}\x{3164}\x{FFA0}\x{2800}])*\z/u
end

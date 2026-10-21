# Changelog

## 0.1.0 (unreleased)

- Needs Elixir 1.20 on OTP 29 (`elixir: "~> 1.20"`), and its locked dependencies are
  updated to their newest allowed versions. phoenix 1.8.16.
- Moved here from the Regents repository (Regents main b258ae02) into
  elixir-utils `ash_components/identity`, owned by the ash-template lane. Module
  names, routes, settings, mix tasks and migrations are unchanged.
- elixir-utils siblings are path dependencies, and the package runs the
  elixir-utils `mix check`.
- Runs on Ash 3.36. Ash postgres stays at 2.13.0.
- `RegentIdentity.ProfileName`: the calculation a site puts on its account
  resource to show the name a person set in their shared profile. Each site
  used to keep its own copy of the profiles table to read it.
- A display name may not hold hidden characters (founder, 2026-10-19): control
  characters, line and paragraph separators, or format characters, which include
  the marks that turn the text around them to run the other way, zero-width
  spaces, the byte-order mark, the word joiner and the soft hyphen. A zero-width
  joiner or non-joiner stays allowed between two visible characters (emoji joins,
  Persian script), and tag characters inside a complete flag, from U+1F3F4 to
  U+E007F. `PATCH /` refuses any other with the code `invalid_display_name`;
  letters in any script, accents and emoji stay allowed. The rule is
  `RegentFormat.Name`, shared with agents' names; `regent_format` is a new path
  dependency.
- The name check now names six cases a looser rule once let through: tag
  characters outside a flag, a zero-width space, a joiner before a space, and
  three broken flags (a stray tag-block character, a flag that ends twice, a flag
  followed by a joiner). Each of six looser rules fails `test/http_test.exs`.

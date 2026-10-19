# Changelog

## 0.1.0 (unreleased)

- Moved here from the Regents repository (Regents main b258ae02) into
  elixir-utils `ash_components/identity`, owned by the ash-template lane. Module
  names, routes, settings, mix tasks and migrations are unchanged.
- elixir-utils siblings are path dependencies, and the package runs the
  elixir-utils `mix check`.
- Runs on Ash 3.36. Ash postgres stays at 2.13.0.
- `RegentIdentity.ProfileName`: the calculation a site puts on its account
  resource to show the name a person set in their shared profile. Each site
  used to keep its own copy of the profiles table to read it.
- A display name may not hold control characters or characters that turn the
  text around them to run the other way (founder, 2026-10-19). `PATCH /` refuses
  one with the code `invalid_display_name`; letters in any script, accents and
  emoji stay allowed.

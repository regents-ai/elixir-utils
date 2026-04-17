# Regent Elixir Utilities

This folder is one repository for multiple Elixir utilities.

Each utility below lives in its own folder here:

- `xmtp/` → publishes as `xmtp_elixir_sdk`
- `ens/` → publishes as `ens_elixir`
- `siwa/siwa-elixir/` → umbrella app for the SIWA packages

How to work with it:

- Open any utility folder and run its Elixir commands there.
- Example: from `xmtp/` run `mix deps.get` and `mix test`.
- Example: from `ens/` run `mix deps.get` and `mix test`.
- Example: from `siwa/siwa-elixir/` run `mix test`.
- When you publish, run `mix hex.publish` from the package folder you want to publish.

A few notes:

- This repo is only one code tracker for all utilities.
- Each package keeps its own version number and package settings in its own `mix.exs`.
- `siwa/siwa-js/` is reference material only and is not tracked here.

If we add more utilities later, put each new one in its own folder with its own `mix.exs` and release name.

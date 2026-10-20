# Changelog

## 0.1.0 (unreleased)

- First version, moved from regents.sh (`Regents.Names`, regents-ai/regents
  a1df221f) so every Regent site lists the Regent names a person's wallets hold
  and makes their free claims the same way. The resources, the free claim and
  its rules are unchanged; the person check now matches every site's human actor
  (`%{role: :human, human_account_id: integer}`), and the Privy check reads the
  site's app from `config :regent_names, :privy_app_id`.

# Regent Points

Follow ../AGENTS.md and the workspace regent-workflow and Ash skills.
Run `mix check` and `mix ash.codegen --check` here. Keep the site's source actions,
identity verification, Repo, PubSub and Oban supervision outside this package.
Generate schema changes here; consumers never generate Points migrations.
Use an isolated local database for representative checks. Never alter existing
product data, enable earning or run production migrations without Sean's authority.

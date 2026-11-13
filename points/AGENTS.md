# Regent Points

Follow ../AGENTS.md and the workspace regent-workflow and Ash skills.
Run `mix check` and `mix ash.codegen --check` here. Keep the site's source actions,
identity verification, Repo, PubSub and Oban supervision outside this package.
Generate schema changes here; consumers never generate Points migrations.
Use an isolated local database for representative checks. Never alter existing
product data, enable earning or run production migrations without Sean's authority.
The program's shape (30-day periods, three seasons, `Rules.season_count/0`) lives
only in `RegentPoints.Rules`; sites read it through `RegentPoints.Seasons` and never
keep their own count. The end is a comparison with the clock, never a timer or job.

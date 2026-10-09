import Config
config :regent_agents, ash_domains: [RegentAgents]

# Ash 3.33 requires an explicit string length unit. Codepoints match how
# PostgreSQL counts `length()`, so `max_length` bounds stored size; graphemes
# (`:mixed`) do not, because one grapheme can carry unbounded combining marks
# (CVE-2026-82752).
config :ash, default_string_length_count: :codepoints

# Credits are the private currency XRC, kept to the millionth. Every site that
# uses the library declares it the same way.
config :ex_money,
  custom_currencies: [{:XRC, name: "Credits", digits: 6}],
  auto_start_exchange_rate_service: false

config :regent_credits, ash_domains: [RegentCredits]

if config_env() == :test, do: import_config("test.exs")

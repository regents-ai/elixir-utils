ExUnit.start()
RegentCredits.TestChain.start()
name = Keyword.fetch!(RegentCredits.TestRepo.config(), :database)

unless Regex.match?(~r/^regent_credits_test[a-z0-9_]*$/, name),
  do: raise("refusing unowned database name")

{:ok, _} = RegentCredits.TestRepo.start_link()
RegentCredits.Migrator.up(RegentCredits.TestRepo)
Ecto.Adapters.SQL.Sandbox.mode(RegentCredits.TestRepo, :manual)

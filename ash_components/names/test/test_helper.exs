ExUnit.start()
name = Keyword.fetch!(RegentNames.TestRepo.config(), :database)

unless Regex.match?(~r/^regent_names_test_[a-z0-9_]+$/, name),
  do: raise("refusing unowned database name")

{:ok, _} = RegentNames.TestRepo.start_link()

Ecto.Migrator.run(
  RegentNames.TestRepo,
  [{0, RegentNames.TestRepo.AshFunctions}, {1, RegentNames.TestRepo.Tables}],
  :up,
  all: true,
  log: false
)

Ecto.Adapters.SQL.Sandbox.mode(RegentNames.TestRepo, :manual)

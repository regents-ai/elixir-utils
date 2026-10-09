ExUnit.start()
name = Keyword.fetch!(RegentIdentity.TestRepo.config(), :database)

unless Regex.match?(~r/^regent_identity_test_[a-z0-9_]+$/, name),
  do: raise("refusing unowned database name")

{:ok, _} = RegentIdentity.TestRepo.start_link()

RegentIdentity.Migrator.up(RegentIdentity.TestRepo)

Ecto.Adapters.SQL.Sandbox.mode(RegentIdentity.TestRepo, :manual)

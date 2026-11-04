ExUnit.start()

{:ok, _} = RegentHttp.TestRepo.start_link()
Ecto.Migrator.up(RegentHttp.TestRepo, 1, RegentHttp.TestErrorTrackerMigration, log: false)
Ecto.Adapters.SQL.Sandbox.mode(RegentHttp.TestRepo, :manual)

:ok = RegentHttp.ErrorSaving.attach()

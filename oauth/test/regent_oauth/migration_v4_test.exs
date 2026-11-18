defmodule RegentOAuth.MigrationV4Test do
  # Version 4 lifts the 255-character limit without rewriting a table: a
  # site's apps and codes stay exactly as they are, and each table is held
  # only while its definition changes.
  use RegentOAuth.Case

  alias RegentOAuth.Test.{Flow, Repo, Schema}

  @schema "regent_oauth_v3_test"

  setup do
    prefix = Application.fetch_env!(:regent_oauth, :test_schema)
    Application.put_env(:regent_oauth, :test_schema, @schema)
    on_exit(fn -> Application.put_env(:regent_oauth, :test_schema, prefix) end)
    Schema.migrate!(@schema, [1, 2, 3])
    :ok
  end

  # The table's file on disk, which a rewrite replaces, and its rows.
  defp stored(table) do
    name = ~s("#{@schema}".#{table})
    %{rows: [[file]]} = Repo.query!("SELECT pg_relation_filenode($1::text::regclass)", [name])
    %{rows: rows} = Repo.query!("SELECT * FROM #{name} ORDER BY id")
    {file, rows}
  end

  test "existing apps and codes are kept as they are, and no table is rewritten" do
    client_id = Flow.client!()
    Flow.code!(client_id, "did:privy:sol")
    before = Enum.map(~w(oauth_clients oauth_tokens), &stored/1)
    assert [{_, [_app]}, {_, [_code]}] = before

    Schema.migrate!(@schema, [1, 2, 3, 4])

    assert Enum.map(~w(oauth_clients oauth_tokens), &stored/1) == before
  end
end

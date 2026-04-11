defmodule XmtpElixirSdk.BrowserShim.OpfsTest do
  use ExUnit.Case, async: true

  alias XmtpElixirSdk.BrowserShim.Action
  alias XmtpElixirSdk.BrowserShim.Opfs

  test "creates canonical opfs requests" do
    opfs = Opfs.new(enable_logging: true)

    assert %Opfs{enable_logging: true} = opfs

    assert %Action.Request{action: "opfs.init", data: %{enableLogging: true}} =
             Opfs.init_request(opfs)

    assert %Action.Request{action: "opfs.listFiles"} = Opfs.list_files_request()
    assert %Action.Request{action: "opfs.fileCount"} = Opfs.file_count_request()
    assert %Action.Request{action: "opfs.poolCapacity"} = Opfs.pool_capacity_request()

    assert %Action.Request{action: "opfs.fileExists", data: %{path: "db.sqlite"}} =
             Opfs.file_exists_request("db.sqlite")

    assert %Action.Request{action: "opfs.deleteFile", data: %{path: "db.sqlite"}} =
             Opfs.delete_file_request("db.sqlite")

    assert %Action.Request{action: "opfs.exportDb", data: %{path: "db.sqlite"}} =
             Opfs.export_db_request("db.sqlite")

    assert %Action.Request{
             action: "opfs.importDb",
             data: %{path: "db.sqlite", data: <<1, 2, 3>>}
           } = Opfs.import_db_request("db.sqlite", <<1, 2, 3>>)

    assert %Action.Request{action: "opfs.clearAll"} = Opfs.clear_all_request()
  end
end

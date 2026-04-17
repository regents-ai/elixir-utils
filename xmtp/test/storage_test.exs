defmodule XmtpElixirSdk.StorageTest do
  use ExUnit.Case, async: true

  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Storage

  test "init returns io when the target path cannot be created as a directory" do
    parent = unique_path("init-parent")
    File.write!(parent, "not-a-directory")
    on_exit(fn -> File.rm_rf(parent) end)

    assert {:error, %Error{kind: :io, message: "failed to initialize storage"}} =
             Storage.new(Path.join(parent, "child"))
             |> Storage.init()
  end

  test "list_files returns io when the root cannot be listed" do
    root = unique_path("list-root")
    File.write!(root, "not-a-directory")
    on_exit(fn -> File.rm_rf(root) end)

    assert {:error, %Error{kind: :io, message: "failed to list storage files"}} =
             Storage.new(root)
             |> Storage.list_files()
  end

  test "export_db returns io for a missing file" do
    root = unique_path("export-root")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)

    assert {:error, %Error{kind: :io, message: "failed to export database"}} =
             Storage.new(root)
             |> Storage.export_db("missing.sqlite")
  end

  test "import_db returns io when the write path is invalid" do
    parent = unique_path("import-parent")
    File.write!(parent, "not-a-directory")
    on_exit(fn -> File.rm_rf(parent) end)

    assert {:error, %Error{kind: :io, message: "failed to import database"}} =
             Storage.new(parent)
             |> Storage.import_db("child/db.sqlite", <<1, 2, 3>>)
  end

  test "delete_file returns io when the file path is invalid" do
    parent = unique_path("delete-parent")
    File.write!(parent, "not-a-directory")
    on_exit(fn -> File.rm_rf(parent) end)

    assert {:error, %Error{kind: :io, message: "failed to delete file"}} =
             Storage.new(parent)
             |> Storage.delete_file("child/db.sqlite")
  end

  test "delete_file returns io for a missing file" do
    root = unique_path("delete-missing-root")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)

    assert {:error, %Error{kind: :io, message: "failed to delete file"}} =
             Storage.new(root)
             |> Storage.delete_file("missing.sqlite")
  end

  test "clear_all returns io when the root cannot be cleared" do
    parent = unique_path("clear-parent")
    File.write!(parent, "not-a-directory")
    on_exit(fn -> File.rm_rf(parent) end)

    assert {:error, %Error{kind: :io, message: "failed to clear storage"}} =
             Storage.new(Path.join(parent, "child"))
             |> Storage.clear_all()
  end

  defp unique_path(suffix) do
    Path.join(System.tmp_dir!(), "xmtp-elixir-sdk-storage-#{suffix}-#{System.unique_integer([:positive])}")
  end
end

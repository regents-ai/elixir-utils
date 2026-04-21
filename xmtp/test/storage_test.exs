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

  test "storage paths cannot escape the configured root" do
    root = unique_path("escape-root")
    outside = unique_path("outside-file")
    File.mkdir_p!(root)

    on_exit(fn ->
      File.rm_rf(root)
      File.rm_rf(outside)
    end)

    storage = Storage.new(root)

    assert {:error, %Error{kind: :invalid_argument, message: "invalid storage path"}} =
             Storage.import_db(storage, "../" <> Path.basename(outside), <<1, 2, 3>>)

    refute File.exists?(outside)

    assert {:error, %Error{kind: :invalid_argument, message: "invalid storage path"}} =
             Storage.export_db(storage, "../" <> Path.basename(outside))

    assert {:error, %Error{kind: :invalid_argument, message: "invalid storage path"}} =
             Storage.delete_file(storage, "../" <> Path.basename(outside))

    assert {:error, %Error{kind: :invalid_argument, message: "invalid storage path"}} =
             Storage.file_exists(storage, "../" <> Path.basename(outside))
  end

  test "storage paths cannot escape the configured root through symlinks" do
    root = unique_path("symlink-root")
    outside_dir = unique_path("outside-dir")
    File.mkdir_p!(root)
    File.mkdir_p!(outside_dir)
    File.write!(Path.join(outside_dir, "secret.sqlite"), "secret")
    File.ln_s!(outside_dir, Path.join(root, "linked"))

    on_exit(fn ->
      File.rm_rf(root)
      File.rm_rf(outside_dir)
    end)

    storage = Storage.new(root)

    assert {:error, %Error{kind: :invalid_argument, message: "invalid storage path"}} =
             Storage.export_db(storage, "linked/secret.sqlite")

    assert {:error, %Error{kind: :invalid_argument, message: "invalid storage path"}} =
             Storage.delete_file(storage, "linked/secret.sqlite")

    assert {:error, %Error{kind: :invalid_argument, message: "invalid storage path"}} =
             Storage.file_exists(storage, "linked/secret.sqlite")

    assert {:error, %Error{kind: :invalid_argument, message: "invalid storage path"}} =
             Storage.import_db(storage, "linked/secret.sqlite", <<1, 2, 3>>)
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
    Path.join(
      System.tmp_dir!(),
      "xmtp-elixir-sdk-storage-#{suffix}-#{System.unique_integer([:positive])}"
    )
  end
end

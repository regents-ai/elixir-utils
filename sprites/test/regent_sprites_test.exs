defmodule RegentSpritesTest do
  use ExUnit.Case, async: false

  alias RegentSprites.{Checkpoint, Error, Output, Sprite}

  @token "test-sprites-token-never-shown"

  setup do
    previous_token = Application.get_env(:regent_sprites, :token)
    previous_options = Application.get_env(:regent_sprites, :req_options)

    Application.put_env(:regent_sprites, :token, @token)
    Application.put_env(:regent_sprites, :req_options, plug: {Req.Test, __MODULE__})

    on_exit(fn ->
      restore(:token, previous_token)
      restore(:req_options, previous_options)
    end)
  end

  describe "create/2" do
    test "sends a private machine request with the token and reads the machine" do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/v1/sprites"
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer " <> @token]

        assert json_body(conn) == %{
                 "name" => "wb-h05",
                 "url_settings" => %{"auth" => "sprite"},
                 "wait_for_capacity" => false
               }

        conn |> Plug.Conn.put_status(201) |> Req.Test.json(sprite_body("wb-h05", "cold"))
      end)

      assert {:ok, %Sprite{} = sprite} = RegentSprites.create("wb-h05", wait_for_capacity: false)
      assert sprite.name == "wb-h05"
      assert sprite.status == "cold"
      assert sprite.version == "0.0.1-rc48"
      assert sprite.environment_version == nil
    end

    test "a name in use answers with Sprites' status and words" do
      Req.Test.expect(__MODULE__, fn conn ->
        conn
        |> Plug.Conn.put_status(409)
        |> Req.Test.json(%{"error" => "A sprite named 'wb-h05' already exists."})
      end)

      assert {:error, %Error{reason: {:sprites, 409, "A sprite named 'wb-h05' already exists."}}} =
               RegentSprites.create("wb-h05")
    end

    test "a reply without the machine's facts is unexpected" do
      Req.Test.expect(__MODULE__, fn conn ->
        conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{"id" => "sprite-1", "name" => "wb"})
      end)

      assert {:error, %Error{reason: :unexpected_response}} = RegentSprites.create("wb")
    end

    test "without a token nothing is sent" do
      Application.put_env(:regent_sprites, :token, nil)

      assert {:error, %Error{reason: :token_missing}} = RegentSprites.create("wb-h05")
    end
  end

  describe "get/1 and delete/1" do
    test "get reads the machine and an unknown one answers 404" do
      Req.Test.expect(__MODULE__, 2, fn conn ->
        case conn.request_path do
          "/v1/sprites/wb-h05" ->
            Req.Test.json(conn, Map.put(sprite_body("wb-h05", "running"), "data", %{}))

          "/v1/sprites/wb-gone" ->
            conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"error" => "sprite not found"})
        end
      end)

      assert {:ok, %Sprite{status: "running"}} = RegentSprites.get("wb-h05")

      assert {:error, %Error{reason: {:sprites, 404, "sprite not found"}}} =
               RegentSprites.get("wb-gone")
    end

    test "delete expects no content" do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "DELETE"
        assert conn.request_path == "/v1/sprites/wb-h05"
        Plug.Conn.send_resp(conn, 204, "")
      end)

      assert :ok = RegentSprites.delete("wb-h05")
    end
  end

  describe "checkpoint/2" do
    test "makes the checkpoint, then finds it by its comment" do
      Req.Test.expect(__MODULE__, 3, fn conn ->
        case {conn.method, conn.request_path} do
          {"GET", "/v1/sprites/wb-h05/checkpoints"} ->
            Req.Test.json(conn, checkpoint_list(Process.get(:made, false)))

          {"POST", "/v1/sprites/wb-h05/checkpoint"} ->
            assert json_body(conn) == %{"comment" => "baseline H05"}
            Process.put(:made, true)
            ndjson(conn, [info("Creating checkpoint..."), complete("Checkpoint v2 created")])
        end
      end)

      assert {:ok, %Checkpoint{id: "v2", comment: "baseline H05", auto?: false} = checkpoint} =
               RegentSprites.checkpoint("wb-h05", "baseline H05")

      assert checkpoint.created_at == ~U[2026-10-04 17:51:04Z]
    end

    test "a comment that already exists returns that checkpoint and makes nothing" do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "GET"
        Req.Test.json(conn, checkpoint_list(true))
      end)

      assert {:ok, %Checkpoint{id: "v2"}} = RegentSprites.checkpoint("wb-h05", "baseline H05")
    end

    test "an error line fails the checkpoint even before the end" do
      Req.Test.expect(__MODULE__, 2, fn conn ->
        case conn.method do
          "GET" ->
            Req.Test.json(conn, checkpoint_list(false))

          "POST" ->
            ndjson(conn, [info("Creating checkpoint..."), error("disk busy"), complete("done")])
        end
      end)

      assert {:error, %Error{reason: {:stream, "disk busy"}}} =
               RegentSprites.checkpoint("wb-h05", "baseline H05")
    end
  end

  describe "restore/2" do
    test "finishes on a complete line" do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/v1/sprites/wb-h05/checkpoints/v2/restore"
        ndjson(conn, [info("Restoring from checkpoint v2..."), complete("Restored")])
      end)

      assert :ok = RegentSprites.restore("wb-h05", "v2")
    end

    test "reports Sprites' error and a stream that stops early" do
      Req.Test.expect(__MODULE__, 2, fn conn ->
        case Process.get(:restores, 0) do
          0 ->
            Process.put(:restores, 1)

            ndjson(conn, [
              info("Restoring..."),
              error("Failed to restore checkpoint: file exists")
            ])

          1 ->
            ndjson(conn, [info("Restoring...")])
        end
      end)

      assert {:error, %Error{reason: {:stream, "Failed to restore checkpoint: file exists"}}} =
               RegentSprites.restore("wb-h05", "v2")

      assert {:error, %Error{reason: :stream_incomplete}} = RegentSprites.restore("wb-h05", "v2")
    end
  end

  describe "exec/3" do
    test "sends the command in the address and splits what it printed" do
      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.request_path == "/v1/sprites/wb-h05/exec"

        assert conn.query_string ==
                 "cmd=sh&cmd=-c&cmd=echo%20out%3B%20echo%20err%201%3E%262%3B%20exit%203&dir=%2Fwork"

        Plug.Conn.send_resp(conn, 200, <<2, "err\n", 1, "out\n", 3, 3>>)
      end)

      assert {:ok, %Output{exit_code: 3, stdout: "out\n", stderr: "err\n"}} =
               RegentSprites.exec("wb-h05", ["sh", "-c", "echo out; echo err 1>&2; exit 3"],
                 dir: "/work"
               )
    end

    test "standard input travels as the body, labelled as raw bytes" do
      payload = :binary.list_to_bin(Enum.to_list(0..255))

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.query_string == "cmd=wc&cmd=-c&stdin=true"
        assert Plug.Conn.get_req_header(conn, "content-type") == ["application/octet-stream"]
        assert {:ok, ^payload, conn} = Plug.Conn.read_body(conn)
        Plug.Conn.send_resp(conn, 200, <<1, "256\n", 3, 0>>)
      end)

      assert {:ok, %Output{exit_code: 0, stdout: "256\n"}} =
               RegentSprites.exec("wb-h05", ["wc", "-c"], stdin: payload)
    end

    test "silence is an empty result and a broken reply is unexpected" do
      Req.Test.expect(__MODULE__, 2, fn conn ->
        case Process.get(:execs, 0) do
          0 ->
            Process.put(:execs, 1)
            Plug.Conn.send_resp(conn, 200, <<3, 0>>)

          1 ->
            Plug.Conn.send_resp(conn, 200, "<!DOCTYPE html>")
        end
      end)

      assert {:ok, %Output{exit_code: 0, stdout: "", stderr: ""}} =
               RegentSprites.exec("wb-h05", ["true"])

      assert {:error, %Error{reason: :unexpected_response}} =
               RegentSprites.exec("wb-h05", ["true"])
    end
  end

  describe "read_file/3 and write_file/4" do
    test "a file of any bytes comes back exactly" do
      content = :binary.list_to_bin(Enum.to_list(0..255))

      Req.Test.expect(__MODULE__, fn conn ->
        assert conn.query_string == "cmd=base64&cmd=-w0&cmd=--&cmd=%2Fvar%2Fwb%2Fkey"
        Plug.Conn.send_resp(conn, 200, <<1, Base.encode64(content)::binary, 3, 0>>)
      end)

      assert {:ok, ^content} = RegentSprites.read_file("wb-h05", "/var/wb/key")
    end

    test "a missing file is an error with what the command said" do
      Req.Test.expect(__MODULE__, fn conn ->
        Plug.Conn.send_resp(conn, 200, <<2, "base64: /nope: No such file\n", 3, 1>>)
      end)

      assert {:error, %Error{reason: {:exit, 1, "base64: /nope: No such file\n"}}} =
               RegentSprites.read_file("wb-h05", "/nope")
    end

    test "write sends the content on standard input with the file's mode" do
      Req.Test.expect(__MODULE__, fn conn ->
        query = URI.query_decoder(conn.query_string) |> Enum.to_list()

        assert query == [
                 {"cmd", "sh"},
                 {"cmd", "-c"},
                 {"cmd", ~S(umask 077 && cat > "$1" && chmod "$2" "$1")},
                 {"cmd", "sh"},
                 {"cmd", "/var/wb/key"},
                 {"cmd", "640"},
                 {"stdin", "true"}
               ]

        assert {:ok, "secret-free bytes", conn} = Plug.Conn.read_body(conn)
        Plug.Conn.send_resp(conn, 200, <<3, 0>>)
      end)

      assert :ok =
               RegentSprites.write_file("wb-h05", "/var/wb/key", "secret-free bytes", mode: "640")
    end
  end

  describe "Output.from_frames/1" do
    test "keeps output order within each stream across many pieces" do
      frames = <<1, "a", 2, "x", 1, "b", 1, "c", 2, "y", 3, 7>>

      assert {:ok, %Output{exit_code: 7, stdout: "abc", stderr: "xy"}} =
               Output.from_frames(frames)
    end

    test "a reply that does not start with a mark or lacks the ending is refused" do
      assert :error = Output.from_frames("out\n" <> <<3, 0>>)
      assert :error = Output.from_frames(<<1, "out\n">>)
      assert :error = Output.from_frames(<<3>>)
    end
  end

  test "errors read plainly and never carry the token" do
    error = %Error{reason: {:sprites, 409, "A sprite named 'wb' already exists."}}
    assert Exception.message(error) == "Sprites answered 409: A sprite named 'wb' already exists."
    refute inspect(error) =~ @token
  end

  defp sprite_body(name, status) do
    %{
      "id" => "sprite-0123",
      "name" => name,
      "status" => status,
      "version" => "0.0.1-rc48",
      "url" => "https://#{name}.sprites.app",
      "url_settings" => %{"auth" => "sprite"},
      "organization" => "regent",
      "environment_version" => nil
    }
  end

  defp checkpoint_list(made?) do
    current = %{"id" => "Current", "create_time" => "2026-10-04T17:55:48Z", "is_auto" => false}
    restore = %{"id" => "v1", "create_time" => "2026-10-04T17:40:00Z", "is_auto" => true}

    made = %{
      "id" => "v2",
      "create_time" => "2026-10-04T17:51:04Z",
      "comment" => "baseline H05",
      "is_auto" => false
    }

    if made?, do: [current, made, restore], else: [current, restore]
  end

  defp info(data), do: %{"type" => "info", "data" => data, "time" => "2026-10-04T17:55:47Z"}

  defp complete(data),
    do: %{"type" => "complete", "data" => data, "time" => "2026-10-04T17:55:48Z"}

  defp error(message),
    do: %{"type" => "error", "error" => message, "time" => "2026-10-04T17:55:49Z"}

  defp ndjson(conn, events) do
    Plug.Conn.send_resp(conn, 200, Enum.map_join(events, "\n", &Jason.encode!/1) <> "\n")
  end

  defp json_body(conn) do
    {:ok, body, _conn} = Plug.Conn.read_body(conn)
    Jason.decode!(body)
  end

  defp restore(key, nil), do: Application.delete_env(:regent_sprites, key)
  defp restore(key, value), do: Application.put_env(:regent_sprites, key, value)
end

defmodule RegentHttp.RawBodyReaderTest do
  use ExUnit.Case, async: true

  alias RegentHttp.RawBodyReader

  test "accumulates request bodies returned over multiple reads" do
    conn = Plug.Test.conn(:post, "/", "abcdef")

    assert {:ok, "abcdef", conn} = RawBodyReader.read_body(conn, length: 10, read_length: 2)
    assert conn.assigns.raw_body == "abcdef"
  end

  test "reports oversized request bodies without assigning a raw body" do
    conn = Plug.Test.conn(:post, "/", "abcdef")

    assert {:more, "abc", conn} = RawBodyReader.read_body(conn, length: 3, read_length: 2)
    refute Map.has_key?(conn.assigns, :raw_body)
  end

  test "caps the parser length option at one megabyte" do
    conn = Plug.Test.conn(:post, "/", "small body")

    assert {:ok, "small body", conn} = RawBodyReader.read_body(conn, length: 50_000_000)
    assert conn.assigns.raw_body == "small body"
  end
end

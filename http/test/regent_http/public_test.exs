defmodule RegentHttp.PublicTest do
  use ExUnit.Case, async: true

  alias RegentHttp.Public

  test "only HTTPS addresses without a user or fragment, on a public host, may be fetched" do
    assert Public.valid_url?("https://claude.ai/oauth/mcp-oauth-client-metadata")

    for url <- [
          "http://claude.ai/x",
          "https://user@claude.ai/x",
          "https://claude.ai/x#frag",
          "https://10.0.0.1/x",
          "https://169.254.169.254/latest",
          "https://[::1]/x",
          "https://[::ffff:127.0.0.1]/x",
          "https://claude.ai/a b"
        ] do
      refute Public.valid_url?(url), url
    end
  end

  test "a name that resolves to a non-public address is refused before connecting" do
    assert {:error, :non_public_address} = Public.get("https://localhost/x", max_bytes: 10)
  end
end

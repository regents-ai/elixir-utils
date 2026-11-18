defmodule RegentOAuth.LongValuesTest do
  # OpenAI's apps send a `state` longer than 255 characters, and Allow answered
  # 503: the code's columns held 255 (18 Nov 2026). Every value an accepted
  # request may carry past 255 now reaches the app and back
  # (`RegentOAuth.Migration.V4`).
  use RegentOAuth.Case

  import Plug.Conn
  import Plug.Test

  alias RegentOAuth.Test.Flow

  @verifier String.duplicate("v", 43)

  defp authorize_params(client_id, redirect_uri, state) do
    %{
      "client_id" => client_id,
      "redirect_uri" => redirect_uri,
      "response_type" => "code",
      "scope" => RegentOAuth.scope(),
      "state" => state,
      "resource" => RegentOAuth.resource(),
      "code_challenge" => :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false),
      "code_challenge_method" => "S256"
    }
  end

  # The longest callback consent takes beside this state: its whole query is
  # at most 2048 bytes as JSON.
  defp longest_callback(state) do
    base = "https://claude.ai/api/mcp/auth_callback/"
    room = 2048 - byte_size(Jason.encode!(authorize_params(Ecto.UUID.generate(), base, state)))
    base <> String.duplicate("c", room)
  end

  # Registers an app, opens consent as a signed-in person, presses Allow and
  # exchanges the code, as an app and its person do.
  defp connect(name, redirect_uri, state) do
    registered =
      Flow.post(:register, %{"client_name" => name, "redirect_uris" => [redirect_uri]})

    assert registered.status == 201
    client_id = Jason.decode!(registered.resp_body)["client_id"]
    params = authorize_params(client_id, redirect_uri, state)

    page =
      conn(:get, "/oauth/authorize?" <> URI.encode_query(params))
      |> init_test_session(%{})
      |> assign(:subject, "did:privy:sol")
      |> RegentOAuth.Consent.authorize()

    assert page.status == 200
    pending = get_session(page, :regent_oauth_request)

    allowed =
      conn(:post, "/oauth/authorize")
      |> init_test_session(%{regent_oauth_request: pending})
      |> assign(:subject, "did:privy:sol")
      |> Map.put(:body_params, %{"approval_key" => pending["nonce"], "decision" => "allow"})
      |> RegentOAuth.Consent.approve()

    assert allowed.status == 303
    assert [location] = get_resp_header(allowed, "location")
    assert String.starts_with?(location, redirect_uri <> "?")
    assert %{"code" => code, "state" => ^state} = URI.decode_query(URI.parse(location).query)

    exchanged =
      Flow.post(:token, %{
        "grant_type" => "authorization_code",
        "client_id" => client_id,
        "code" => code,
        "code_verifier" => @verifier,
        "redirect_uri" => redirect_uri,
        "resource" => RegentOAuth.resource()
      })

    assert exchanged.status == 200
    assert %{"access_token" => access} = Jason.decode!(exchanged.resp_body)
    assert {:ok, %{subject: "did:privy:sol"}} = RegentOAuth.verify(access, RegentOAuth.resource())
  end

  test "a state of 1,500 characters comes back with a code that exchanges" do
    state = Base.url_encode64(:crypto.strong_rand_bytes(1125), padding: false)
    assert String.length(state) == 1500

    # Claude's own callback, then the longest consent takes beside this state.
    longest = longest_callback(state)
    assert String.length(longest) > 255

    for redirect_uri <- ["https://claude.ai/api/mcp/auth_callback", longest],
        do: connect("App", redirect_uri, state)
  end

  test "an app with the longest callback consent can carry, and a long name, registers and connects" do
    redirect_uri = longest_callback("state")
    assert String.length(redirect_uri) in 1700..2048

    # 100 characters as a person reads them, each one letter and three accents.
    name = String.duplicate("é́́", 100)
    assert {String.length(name), length(String.codepoints(name))} == {100, 400}

    connect(name, redirect_uri, "state")
  end
end

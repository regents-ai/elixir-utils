defmodule RegentOAuth.ClaudeReplayTest do
  # Claude's connector as it signs in today, from the document claude.ai
  # publishes, byte for byte, with the cache lifetime claude.ai sends. The
  # connector was refused about an hour after connecting, when its access token
  # ran out, and again when it re-authorised (14 Nov 2026).
  use RegentOAuth.Case

  import Ecto.Query
  import ExUnit.CaptureLog
  import Plug.Conn
  import Plug.Test

  alias Boruta.Ecto.Token
  alias RegentOAuth.ClientDocuments.Document
  alias RegentOAuth.Test.{Documents, Flow, Repo, Return}

  @claude "https://claude.ai/oauth/mcp-oauth-client-metadata"
  @document ~s({"client_id":"https://claude.ai/oauth/mcp-oauth-client-metadata","client_name":"Claude","client_uri":"https://claude.ai","redirect_uris":["https://claude.ai/api/mcp/auth_callback"],"grant_types":["authorization_code","refresh_token","urn:ietf:params:oauth:grant-type:jwt-bearer"],"response_types":["code"],"token_endpoint_auth_method":"none"})
  @callback_url "https://claude.ai/api/mcp/auth_callback"
  @verifier String.duplicate("v", 43)

  setup do
    Documents.serve(@claude, %{
      status: 200,
      headers: [{"content-type", "application/json"}, {"cache-control", "public, max-age=300"}],
      body: @document
    })

    :ok
  end

  defp authorize_query do
    URI.encode_query(%{
      "client_id" => @claude,
      "redirect_uri" => @callback_url,
      "response_type" => "code",
      "scope" => RegentOAuth.scope(),
      "state" => "state",
      "resource" => RegentOAuth.resource(),
      "code_challenge" => :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false),
      "code_challenge_method" => "S256"
    })
  end

  # Consent, Allow and the code exchange, as Claude and its person do them.
  defp connect(subject) do
    page =
      conn(:get, "/oauth/authorize?" <> authorize_query())
      |> init_test_session(%{})
      |> assign(:subject, subject)
      |> RegentOAuth.Consent.authorize()

    assert page.status == 200, refused(page)
    pending = get_session(page, :regent_oauth_request)

    approved =
      conn(:post, "/oauth/authorize")
      |> init_test_session(%{regent_oauth_request: pending})
      |> assign(:subject, subject)
      |> Map.put(:body_params, %{"approval_key" => pending["nonce"], "decision" => "allow"})
      |> RegentOAuth.Consent.approve()

    assert approved.status == 200, refused(approved)
    code = URI.decode_query(URI.parse(Return.address(approved)).query)["code"]

    token =
      Flow.post(:token, %{
        "grant_type" => "authorization_code",
        "client_id" => @claude,
        "code" => code,
        "code_verifier" => @verifier,
        "redirect_uri" => @callback_url,
        "resource" => RegentOAuth.resource()
      })

    assert token.status == 200, refused(token)
    Jason.decode!(token.resp_body)
  end

  # The connector's tokens an hour on: the access token has run out.
  defp an_hour_later do
    Repo.update_all(from(t in Token, where: t.type == "access_token"),
      set: [expires_at: System.system_time(:second) - 1]
    )
  end

  defp refresh(refresh_token, extra) do
    params =
      Map.merge(
        %{
          "grant_type" => "refresh_token",
          "client_id" => @claude,
          "refresh_token" => refresh_token
        },
        extra
      )

    {conn, log} = with_log(fn -> Flow.post(:token, params) end)
    assert conn.status == 200, "#{conn.resp_body} #{log}"
    answer = Jason.decode!(conn.resp_body)

    assert {:ok, %{subject: "did:privy:sol"}} =
             RegentOAuth.verify(answer["access_token"], RegentOAuth.resource())

    answer
  end

  defp refused(conn), do: "#{conn.status} #{conn.resp_body}"

  test "Claude refreshes an hour on with or without resource and with its granted scope, and again after its document is read again" do
    %{"refresh_token" => token, "scope" => granted} = connect("did:privy:sol")
    assert_received {:read, @claude}

    # Read again once its own `max-age=300` has passed.
    %Document{refresh_at: refresh_at} = Repo.get!(Document, @claude)
    assert DateTime.diff(refresh_at, DateTime.utc_now()) in 290..300

    an_hour_later()
    %{"refresh_token" => token} = refresh(token, %{"resource" => RegentOAuth.resource()})
    an_hour_later()
    %{"refresh_token" => token} = refresh(token, %{})
    an_hour_later()
    %{"refresh_token" => token, "scope" => ^granted} = refresh(token, %{"scope" => granted})

    # Re-authorising after the document's cache lifetime reads it again.
    Repo.update_all(Document, set: [refresh_at: DateTime.add(DateTime.utc_now(), -1, :second)])
    assert %{"refresh_token" => _new} = connect("did:privy:sol")
    assert_received {:read, @claude}

    an_hour_later()
    refresh(token, %{"resource" => RegentOAuth.resource()})
  end
end

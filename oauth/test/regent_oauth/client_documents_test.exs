defmodule RegentOAuth.ClientDocumentsTest do
  # An app that publishes its identity at an HTTPS address signs in with that
  # address as its client id (Sean, 29 Oct 2026: "can we do the CIMD setting
  # instead of the 'register automatically'?").
  use RegentOAuth.Case

  import Plug.Conn
  import Plug.Test

  alias RegentOAuth.Test.{Documents, Flow}

  @claude Documents.claude_url()
  @callback_url "https://claude.ai/api/mcp/auth_callback"
  @verifier String.duplicate("v", 43)

  setup do
    Documents.serve(@claude, Documents.claude())
    :ok
  end

  defp authorize_query(client_id, redirect_uri \\ @callback_url) do
    URI.encode_query(%{
      "client_id" => client_id,
      "redirect_uri" => redirect_uri,
      "response_type" => "code",
      "scope" => RegentOAuth.scope(),
      "state" => "state",
      "resource" => RegentOAuth.resource(),
      "code_challenge" => :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false),
      "code_challenge_method" => "S256"
    })
  end

  defp consent(subject, query) do
    conn(:get, "/oauth/authorize?" <> query)
    |> init_test_session(%{})
    |> assign(:subject, subject)
    |> RegentOAuth.Consent.authorize()
  end

  defp approve(subject, consent_conn) do
    pending = get_session(consent_conn, :regent_oauth_request)

    conn(:post, "/oauth/authorize")
    |> init_test_session(%{regent_oauth_request: pending})
    |> assign(:subject, subject)
    |> Map.put(:body_params, %{"approval_key" => pending["nonce"], "decision" => "allow"})
    |> RegentOAuth.Consent.approve()
  end

  defp exchange(client_id, code) do
    Flow.post(:token, %{
      "grant_type" => "authorization_code",
      "client_id" => client_id,
      "code" => code,
      "code_verifier" => @verifier,
      "redirect_uri" => @callback_url,
      "resource" => RegentOAuth.resource()
    })
  end

  defp code_from(conn) do
    [location] = get_resp_header(conn, "location")
    assert String.starts_with?(location, @callback_url <> "?")
    URI.decode_query(URI.parse(location).query)["code"]
  end

  test "discovery tells apps they may sign in with a published identity" do
    assert %{
             client_id_metadata_document_supported: true,
             token_endpoint_auth_methods_supported: ["none"]
           } =
             RegentOAuth.server_metadata()
  end

  test "Claude signs in with its published identity: consent, code, tokens, refresh and Connected apps" do
    page = consent("did:privy:sol", authorize_query(@claude))
    assert page.status == 200
    assert page.resp_body =~ "Connect Claude"
    assert page.resp_body =~ "You will return to claude.ai"
    assert_received {:read, @claude}

    approved = approve("did:privy:sol", page)
    assert approved.status == 303
    token = exchange(@claude, code_from(approved))
    assert token.status == 200
    %{"access_token" => access, "refresh_token" => refresh} = Jason.decode!(token.resp_body)

    assert {:ok, %{subject: "did:privy:sol", client_id: client_id}} =
             RegentOAuth.verify(access, RegentOAuth.resource())

    assert [%{id: ^client_id, name: "Claude"}] = RegentOAuth.connected_clients("did:privy:sol")

    refreshed = Flow.refresh(@claude, refresh)
    assert refreshed.status == 200

    # The token endpoint never reads the address; only consent does.
    refute_received {:read, @claude}
  end

  test "a second person's consent uses the recorded identity until it is due, then reads it again" do
    assert consent("did:privy:sol", authorize_query(@claude)).status == 200
    assert_received {:read, @claude}

    assert consent("did:privy:luna", authorize_query(@claude)).status == 200
    refute_received {:read, @claude}

    RegentOAuth.Test.Repo.update_all(RegentOAuth.ClientDocuments.Document,
      set: [refresh_at: DateTime.add(DateTime.utc_now(), -1, :second)]
    )

    assert consent("did:privy:luna", authorize_query(@claude)).status == 200
    assert_received {:read, @claude}
  end

  test "reading the identity again keeps the scopes the app holds" do
    assert consent("did:privy:sol", authorize_query(@claude)).status == 200
    {:ok, id} = RegentOAuth.ClientDocuments.stored(@claude)

    # A scope the app holds that this site no longer offers stays on it, as
    # `RegentOAuth.Migration.ClientScopes` promises.
    kept = RegentOAuth.Test.Repo.insert!(%Boruta.Ecto.Scope{name: "regent.kept", public: false})

    client =
      Boruta.Ecto.Client
      |> RegentOAuth.Test.Repo.get!(id)
      |> RegentOAuth.Test.Repo.preload(:authorized_scopes)

    held = Enum.map([kept | client.authorized_scopes], &%{id: &1.id})
    {:ok, _} = Boruta.Ecto.Admin.Clients.update_client(client, %{authorized_scopes: held})

    RegentOAuth.Test.Repo.update_all(RegentOAuth.ClientDocuments.Document,
      set: [refresh_at: DateTime.add(DateTime.utc_now(), -1, :second)]
    )

    assert consent("did:privy:luna", authorize_query(@claude)).status == 200
    assert_received {:read, @claude}

    scopes =
      Boruta.Ecto.Client
      |> RegentOAuth.Test.Repo.get!(id)
      |> RegentOAuth.Test.Repo.preload(:authorized_scopes)
      |> Map.fetch!(:authorized_scopes)
      |> Enum.map(& &1.name)
      |> Enum.sort()

    assert scopes == Enum.sort(["regent.kept" | RegentOAuth.scopes()])
  end

  test "an identity that does not answer is unavailable, one that answers wrongly is refused, and neither is served from the old record" do
    assert consent("did:privy:sol", authorize_query(@claude)).status == 200

    RegentOAuth.Test.Repo.update_all(RegentOAuth.ClientDocuments.Document,
      set: [refresh_at: DateTime.add(DateTime.utc_now(), -1, :second)]
    )

    {:ok, id} = RegentOAuth.ClientDocuments.stored(@claude)
    due = RegentOAuth.Test.Repo.get!(RegentOAuth.ClientDocuments.Document, @claude).refresh_at

    for answer <- [
          {:error, :timeout},
          {:error, :connection_error},
          %{status: 503, headers: [], body: ""}
        ] do
      Documents.serve(@claude, answer)
      assert consent("did:privy:sol", authorize_query(@claude)).status == 503
    end

    Documents.serve(@claude, %{status: 404, headers: [], body: ""})
    assert consent("did:privy:sol", authorize_query(@claude)).status == 400

    # A failed read is never stored: the record and its app are as they were.
    assert %{client_id: ^id, refresh_at: ^due} =
             RegentOAuth.Test.Repo.get!(RegentOAuth.ClientDocuments.Document, @claude)

    assert %{name: "Claude"} = RegentOAuth.Test.Repo.get!(Boruta.Ecto.Client, id)
  end

  test "reading the identity again takes its new name and callbacks" do
    assert consent("did:privy:sol", authorize_query(@claude)).status == 200
    {:ok, id} = RegentOAuth.ClientDocuments.stored(@claude)

    moved = "https://claude.ai/api/mcp/auth_callback_v2"

    renamed =
      Documents.claude().body
      |> Jason.decode!()
      |> Map.merge(%{"client_name" => "Claude Desktop", "redirect_uris" => [moved]})

    Documents.serve(@claude, %{Documents.claude() | body: Jason.encode!(renamed)})

    RegentOAuth.Test.Repo.update_all(RegentOAuth.ClientDocuments.Document,
      set: [refresh_at: DateTime.add(DateTime.utc_now(), -1, :second)]
    )

    page = consent("did:privy:luna", authorize_query(@claude, moved))
    assert page.status == 200
    assert page.resp_body =~ "Connect Claude Desktop"
    assert {:ok, ^id} = RegentOAuth.ClientDocuments.stored(@claude)

    assert %{name: "Claude Desktop", redirect_uris: [^moved]} =
             RegentOAuth.Test.Repo.get!(Boruta.Ecto.Client, id)

    assert consent("did:privy:luna", authorize_query(@claude)).status == 400
  end

  test "a document is refused unless it is the address's own public client" do
    claude = Jason.decode!(Documents.claude().body)

    for {change, document} <- [
          other_id: Map.put(claude, "client_id", "https://claude.ai/oauth/other"),
          secret: Map.put(claude, "client_secret", "s"),
          secret_client: Map.put(claude, "token_endpoint_auth_method", "client_secret_basic"),
          no_code_grant: Map.put(claude, "grant_types", ["refresh_token"]),
          foreign_callbacks: Map.put(claude, "redirect_uris", ["https://evil.example/cb"]),
          wildcard_callback: Map.put(claude, "redirect_uris", ["https://claude.ai/*"])
        ] do
      Documents.serve(@claude, %{Documents.claude() | body: Jason.encode!(document)})
      assert consent("did:privy:sol", authorize_query(@claude)).status == 400, "#{change}"
    end

    Documents.serve(@claude, %{Documents.claude() | status: 302})
    assert consent("did:privy:sol", authorize_query(@claude)).status == 400

    Documents.serve(@claude, %{Documents.claude() | headers: [{"content-type", "text/html"}]})
    assert consent("did:privy:sol", authorize_query(@claude)).status == 400
  end

  test "only the document's callbacks on its own host are kept" do
    claude = Jason.decode!(Documents.claude().body)
    mixed = Map.put(claude, "redirect_uris", [@callback_url, "https://evil.example/cb"])
    Documents.serve(@claude, %{Documents.claude() | body: Jason.encode!(mixed)})

    assert consent("did:privy:sol", authorize_query(@claude)).status == 200

    assert consent("did:privy:sol", authorize_query(@claude, "https://evil.example/cb")).status ==
             400
  end

  test "addresses that are not a published identity's are refused before anything is read" do
    for url <- [
          "https://claude.ai",
          "https://claude.ai/",
          "https://claude.ai/oauth/../x",
          "https://claude.ai/oauth/x?y=1",
          "https://127.0.0.1/oauth/x",
          "https://claude.ai:8443/oauth/x",
          "https://user@claude.ai/oauth/x"
        ] do
      assert consent("did:privy:sol", authorize_query(url)).status == 400, url
    end

    refute_received {:read, _}
  end

  test "a signed-out visitor never makes the site read an address or record an app" do
    before = RegentOAuth.Test.Repo.aggregate(Boruta.Ecto.Client, :count)

    for n <- 1..5 do
      url = "https://evil.example/app/#{n}"
      Documents.serve(url, %{Documents.claude() | body: Jason.encode!(%{"client_id" => url})})
      page = consent(nil, authorize_query(url, "https://evil.example/cb"))
      assert page.status == 200
      assert page.resp_body =~ "Sign in to connect"
    end

    assert RegentOAuth.Test.Repo.aggregate(Boruta.Ecto.Client, :count) == before
    refute_received {:read, _}
  end

  test "an address and a registered id are never taken for each other" do
    {:ok, client} =
      RegentOAuth.Protocol.request_client(%{
        "client_id" => @claude,
        "redirect_uri" => @callback_url
      })

    # The recorded row cannot be named by its own id.
    assert consent("did:privy:sol", authorize_query(client.id)).status == 400
    assert exchange(client.id, Flow.code!(client.id, "did:privy:sol")).status == 400

    # Nor for a refresh or a revocation of tokens it was given by its address.
    approved = approve("did:privy:sol", consent("did:privy:sol", authorize_query(@claude)))

    %{"access_token" => access, "refresh_token" => refresh} =
      Jason.decode!(exchange(@claude, code_from(approved)).resp_body)

    assert Flow.refresh(client.id, refresh).status == 400
    assert Flow.post(:revoke, %{"client_id" => client.id, "token" => access}).status == 400
    assert {:ok, _} = RegentOAuth.verify(access, RegentOAuth.resource())
    assert Flow.refresh(@claude, refresh).status == 200

    # An address never read at consent is unknown to the token endpoint.
    assert exchange("https://claude.ai/oauth/unknown", "code").status == 400
    refute_received {:read, "https://claude.ai/oauth/unknown"}

    # A registered client still signs in with its id.
    assert {_id, %{"access_token" => _}} = Flow.sign_in!("did:privy:sol")
  end

  test "revocation by address disconnects the app" do
    approved = approve("did:privy:sol", consent("did:privy:sol", authorize_query(@claude)))
    %{"access_token" => access} = Jason.decode!(exchange(@claude, code_from(approved)).resp_body)

    assert Flow.post(:revoke, %{"client_id" => @claude, "token" => access}).status == 200
    assert {:error, :unauthorized} = RegentOAuth.verify(access, RegentOAuth.resource())
    assert RegentOAuth.connected_clients("did:privy:sol") == []
  end
end

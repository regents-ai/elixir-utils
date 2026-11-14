defmodule RegentOAuth.RefusalReasonsTest do
  # Every refusal names the check that refused, in a fixed description and one
  # log line, and never repeats a value from the request (14 Nov 2026: a
  # connector's re-authorisation was answered with a bare `invalid_request`).
  use RegentOAuth.Case

  import Ecto.Query
  import ExUnit.CaptureLog
  import Plug.Conn
  import Plug.Test

  alias Boruta.Ecto.Token
  alias RegentOAuth.ClientDocuments.Document
  alias RegentOAuth.Test.{Documents, Flow, Repo, Site}

  # Sent as the offending value wherever a check reads one.
  @marker "zqmarker7f3a"
  @claude Documents.claude_url()
  @callback_url "https://claude.ai/api/mcp/auth_callback"
  @verifier String.duplicate("v", 43)

  defmodule WiderSite do
    @moduledoc "The test site offering a scope its registered apps do not hold yet."
    @behaviour RegentOAuth

    @impl true
    def config,
      do: Keyword.put(Site.config(), :additional_scopes, %{"regent.rooms.read" => "Read rooms."})

    @impl true
    defdelegate repo, to: Site
    @impl true
    defdelegate current_subject(conn), to: Site
    @impl true
    defdelegate active_subject?(subject), to: Site
  end

  setup do
    Documents.serve(@claude, Documents.claude())
    :ok
  end

  # The answer and the reason named by its one log line; the marker is in neither.
  defp refusal(fun) do
    {conn, log} = with_log(fun)
    refute conn.resp_body =~ @marker
    refute log =~ @marker
    assert [[_line, reason]] = Regex.scan(~r/oauth refused endpoint=\w+ reason=(\w+)/, log)
    {conn, reason}
  end

  defp json_refusal(fun) do
    {conn, reason} = refusal(fun)
    body = Jason.decode!(conn.resp_body)
    assert is_binary(body["error_description"])

    %{
      status: conn.status,
      error: body["error"],
      reason: reason,
      described: body["error_description"]
    }
  end

  defp code_request(client_id, code) do
    %{
      "grant_type" => "authorization_code",
      "client_id" => client_id,
      "code" => code,
      "code_verifier" => @verifier,
      "redirect_uri" => @callback_url,
      "resource" => RegentOAuth.resource()
    }
  end

  defp tokens_table, do: ~s("#{Application.fetch_env!(:regent_oauth, :test_schema)}".oauth_tokens)

  defp authorize_params(client_id) do
    %{
      "client_id" => client_id,
      "redirect_uri" => @callback_url,
      "response_type" => "code",
      "scope" => RegentOAuth.scope(),
      "state" => "state",
      "resource" => RegentOAuth.resource(),
      "code_challenge" => :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false),
      "code_challenge_method" => "S256"
    }
  end

  defp consent(subject, params) do
    conn(:get, "/oauth/authorize?" <> URI.encode_query(params))
    |> init_test_session(%{})
    |> assign(:subject, subject)
    |> RegentOAuth.Consent.authorize()
  end

  defp approve(pending, subject, body) do
    conn(:post, "/oauth/authorize")
    |> init_test_session(%{regent_oauth_request: pending})
    |> assign(:subject, subject)
    |> Map.put(:body_params, body)
    |> RegentOAuth.Consent.approve()
  end

  defp unread(conn), do: Map.put(conn, :body_params, %Plug.Conn.Unfetched{aspect: :body_params})

  test "the token endpoint names each request check that refuses" do
    client_id = Flow.client!()
    request = code_request(client_id, "code")

    for {reason, params} <- [
          {"unexpected_parameter", Map.put(request, @marker, @marker)},
          {"too_large", Map.put(request, "code", String.duplicate(@marker, 700))},
          {"resource", Map.put(request, "resource", "https://#{@marker}.example/mcp")},
          {"scope", Map.put(request, "scope", @marker)},
          {"grant_type", Map.put(request, "grant_type", @marker)},
          {"client_id", Map.put(request, "client_id", @marker)},
          {"client_id", Map.put(request, "client_id", "https://claude.ai/#{@marker}")}
        ] do
      assert %{status: 400, error: "invalid_request", reason: ^reason} =
               json_refusal(fn -> Flow.post(:token, params) end)
    end

    assert %{status: 400, error: "invalid_request", reason: "body"} =
             json_refusal(fn ->
               conn(:post, "/oauth/token") |> unread() |> RegentOAuth.Protocol.call(:token)
             end)
  end

  test "a code or refresh token that fails is answered with one description, and only the log names why" do
    # A second callback, so a code sent with it reaches Boruta's own check.
    moved = "https://claude.ai/#{@marker}"

    client_id =
      :register
      |> Flow.post(%{"client_name" => "App", "redirect_uris" => [@callback_url, moved]})
      |> Map.fetch!(:resp_body)
      |> Jason.decode!()
      |> Map.fetch!("client_id")

    other_id = Flow.client!()
    refused = fn params -> json_refusal(fn -> Flow.post(:token, params) end) end

    used = Flow.code!(client_id, "did:privy:sol")
    assert Flow.exchange(client_id, used).status == 200

    expired = Flow.code!(client_id, "did:privy:sol")

    Repo.update_all(from(t in Token, where: t.value == ^expired),
      set: [expires_at: System.system_time(:second) - 1]
    )

    unbound = Flow.code!(client_id, "did:privy:sol")

    Repo.query!(
      "UPDATE #{tokens_table()} SET mcp_resource = 'https://elsewhere.test/mcp' WHERE value = $1",
      [unbound]
    )

    codes = [
      {"missing_credential", Map.delete(code_request(client_id, "code"), "code")},
      {"unknown_credential", code_request(client_id, @marker)},
      {"other_client", code_request(client_id, Flow.code!(other_id, "did:privy:sol"))},
      {"revoked", code_request(client_id, used)},
      {"expired", code_request(client_id, expired)},
      {"not_bound", code_request(client_id, unbound)},
      {"inactive_subject", code_request(client_id, Flow.code!(client_id, "did:privy:gone"))},
      # Boruta's own refusal, by its error name.
      {"invalid_grant",
       client_id
       |> code_request(Flow.code!(client_id, "did:privy:sol"))
       |> Map.put("redirect_uri", moved)}
    ]

    # Each sign-in registers its own app: `first` is another app's.
    {_id, %{"refresh_token" => first}} = Flow.sign_in!("did:privy:luna")
    {luna_client, %{"refresh_token" => old}} = Flow.sign_in!("did:privy:luna")
    assert Flow.refresh(luna_client, old).status == 200

    described =
      for {reason, params} <- codes do
        assert %{status: 400, error: "invalid_grant", reason: ^reason, described: described} =
                 refused.(params)

        described
      end

    # A refresh token the app already used: refused within the grace period,
    # then reuse disconnects the app, after which every token of it is revoked.
    refresh = fn token ->
      refused.(%{
        "grant_type" => "refresh_token",
        "client_id" => luna_client,
        "refresh_token" => token
      })
    end

    assert %{error: "invalid_grant", reason: "refresh_used_within_grace", described: within} =
             refresh.(old)

    Repo.query!(
      "UPDATE #{tokens_table()} SET refresh_token_revoked_at = refresh_token_revoked_at - interval '31 seconds' WHERE refresh_token = $1",
      [RegentOAuth.hash_token(old)]
    )

    assert %{error: "invalid_grant", reason: "refresh_reuse_revoked", described: reused} =
             refresh.(old)

    assert %{error: "invalid_grant", reason: "revoked", described: revoked} = refresh.(old)

    assert %{error: "invalid_grant", reason: "unknown_credential", described: unknown} =
             refresh.(@marker)

    assert %{error: "invalid_grant", reason: "other_client"} =
             refused.(%{
               "grant_type" => "refresh_token",
               "client_id" => luna_client,
               "refresh_token" => first
             })

    assert [_one] = Enum.uniq(described ++ [within, reused, revoked, unknown])
  end

  test "a refresh token past its lifetime is expired" do
    {client_id, %{"refresh_token" => refresh}} = Flow.sign_in!("did:privy:sol")

    Repo.query!(
      "UPDATE #{tokens_table()} SET inserted_at = inserted_at - interval '31 days' WHERE refresh_token = $1",
      [RegentOAuth.hash_token(refresh)]
    )

    assert %{status: 400, error: "invalid_grant", reason: "expired"} =
             json_refusal(fn -> Flow.refresh(client_id, refresh) end)
  end

  test "Boruta's own refusals keep their error and are logged by its name" do
    client_id = Flow.client!()
    request = code_request(client_id, Flow.code!(client_id, "did:privy:sol"))

    verifier = Map.put(request, "code_verifier", String.pad_trailing(@marker, 43, "x"))

    assert %{status: 400, error: "invalid_request", reason: "invalid_request"} =
             json_refusal(fn -> Flow.post(:token, verifier) end)

    callback = Map.put(request, "redirect_uri", "https://claude.ai/#{@marker}")

    assert %{status: 400, error: "invalid_client", reason: "invalid_client"} =
             json_refusal(fn -> Flow.post(:token, callback) end)
  end

  test "an error the token endpoint does not answer by name is invalid_request, logged by Boruta's error name or as unexpected" do
    conn = conn(:post, "/oauth/token")

    boruta = %Boruta.Oauth.Error{
      status: :internal_server_error,
      error: :unknown_error,
      error_description: @marker
    }

    assert %{status: 400, error: "invalid_request", reason: "unknown_error"} =
             json_refusal(fn -> RegentOAuth.Protocol.token_error(conn, boruta) end)

    assert %{status: 400, error: "invalid_request", reason: "unexpected"} =
             json_refusal(fn -> RegentOAuth.Protocol.token_error(conn, {:failed, @marker}) end)
  end

  test "registration and revocation name each check that refuses" do
    registration = %{"client_name" => "App", "redirect_uris" => [@callback_url]}

    for {reason, params} <- [
          {"too_large", Map.put(registration, "client_name", String.duplicate(@marker, 700))},
          {"too_large", Map.put(registration, "logo", String.duplicate(@marker, 700))},
          {"token_endpoint_auth_method",
           Map.put(registration, "token_endpoint_auth_method", @marker)},
          {"response_types", Map.put(registration, "response_types", [@marker])},
          {"grant_types", Map.put(registration, "grant_types", [@marker])},
          {"grant_types", Map.put(registration, "grant_types", @marker)},
          {"client_name", Map.put(registration, "client_name", "")},
          {"redirect_uris", Map.put(registration, "redirect_uris", [])},
          {"redirect_uri_format",
           Map.put(registration, "redirect_uris", ["http://#{@marker}.example/cb"])}
        ] do
      assert %{status: 400, error: "invalid_client_metadata", reason: ^reason} =
               json_refusal(fn -> Flow.post(:register, params) end)
    end

    {client_id, %{"access_token" => access}} = Flow.sign_in!("did:privy:sol")
    revocation = %{"client_id" => client_id, "token" => access}

    for {reason, params} <- [
          {"unexpected_parameter", Map.put(revocation, @marker, @marker)},
          {"token", Map.delete(revocation, "token")},
          {"client_id", Map.put(revocation, "client_id", @marker)}
        ] do
      assert %{status: 400, error: "invalid_request", reason: ^reason} =
               json_refusal(fn -> Flow.post(:revoke, params) end)
    end

    assert {:ok, _} = RegentOAuth.verify(access, RegentOAuth.resource())
  end

  test "opening consent names each check that refuses" do
    client_id = Flow.client!()
    params = authorize_params(client_id)

    {:ok, confidential} =
      Boruta.Ecto.Admin.Clients.create_client(%{
        RegentOAuth.Protocol.public_client("Private", [@callback_url])
        | confidential: true
      })

    for {reason, query} <- [
          {"unexpected_parameter", Map.put(params, @marker, "1")},
          {"too_large", Map.put(params, "state", String.duplicate(@marker, 200))},
          {"resource", Map.put(params, "resource", "https://#{@marker}.example/mcp")},
          {"scope", Map.put(params, "scope", @marker)},
          {"response_type", Map.put(params, "response_type", @marker)},
          {"code_challenge_method", Map.put(params, "code_challenge_method", "plain")},
          {"state", Map.put(params, "state", "")},
          {"code_challenge", Map.put(params, "code_challenge", @marker)},
          {"client_id", Map.put(params, "client_id", @marker)},
          {"client_id", Map.put(params, "client_id", Ecto.UUID.generate())},
          {"client_id_address", Map.put(params, "client_id", "https://claude.ai/#{@marker}?x=1")},
          {"client_not_public", Map.put(params, "client_id", confidential.id)},
          {"redirect_uri", Map.put(params, "redirect_uri", "https://claude.ai/#{@marker}")}
        ] do
      assert %{status: 400, error: "invalid_request", reason: ^reason} =
               json_refusal(fn -> consent("did:privy:sol", query) end)
    end

    assert %{status: 401, error: "login_required", reason: "inactive_subject"} =
             json_refusal(fn -> consent("did:privy:gone", params) end)
  end

  test "opening consent names each reason a published identity is refused" do
    claude = Jason.decode!(Documents.claude().body)
    params = authorize_params(@claude)

    for {reason, answer} <- [
          {"document_type", %{Documents.claude() | headers: [{"content-type", "text/html"}]}},
          {"document_status", %{Documents.claude() | status: 302}},
          {"document_json", %{Documents.claude() | body: "[]"}},
          {"document_client_id", Map.put(claude, "client_id", "https://claude.ai/#{@marker}")},
          {"document_secret", Map.put(claude, "client_secret", @marker)},
          {"document_auth_method", Map.put(claude, "token_endpoint_auth_method", @marker)},
          {"document_grant_types", Map.put(claude, "grant_types", ["refresh_token"])},
          {"document_response_types", Map.put(claude, "response_types", ["token"])},
          {"document_redirect_uris", Map.put(claude, "redirect_uris", [])},
          {"document_callbacks",
           Map.put(claude, "redirect_uris", ["https://#{@marker}.example/cb"])},
          {"document_client_name", Map.put(claude, "client_name", "bad\u0001#{@marker}")},
          {"document_unreadable", {:error, :too_large}}
        ] do
      answer =
        if is_map(answer) and not Map.has_key?(answer, :status),
          do: %{Documents.claude() | body: Jason.encode!(answer)},
          else: answer

      Documents.serve(@claude, answer)

      assert %{status: 400, error: "invalid_request", reason: ^reason} =
               json_refusal(fn -> consent("did:privy:sol", params) end)
    end

    # An address that does not answer just now keeps its page, and is logged.
    Documents.serve(@claude, {:error, :timeout})
    assert {%{status: 503}, "unavailable"} = refusal(fn -> consent("did:privy:sol", params) end)
    refute Repo.exists?(Document)
  end

  test "a refusal Boruta makes at consent keeps its redirect and is logged by Boruta's error name" do
    client_id = Flow.client!()
    Application.put_env(:regent_oauth, :site, WiderSite)
    on_exit(fn -> Application.put_env(:regent_oauth, :site, Site) end)

    query = Map.put(authorize_params(client_id), "scope", "regent.rooms.read")
    assert {conn, "invalid_scope"} = refusal(fn -> consent("did:privy:sol", query) end)
    assert conn.status == 303
    assert [location] = get_resp_header(conn, "location")
    assert %{"error" => "invalid_scope"} = URI.decode_query(URI.parse(location).query)
  end

  test "approving names each check that refuses and keeps its page" do
    page = consent("did:privy:sol", authorize_params(Flow.client!()))
    assert page.status == 200
    pending = get_session(page, :regent_oauth_request)
    body = %{"approval_key" => pending["nonce"], "decision" => "allow"}

    for {reason, {pending, subject, body}} <- [
          {"no_pending", {nil, "did:privy:sol", body}},
          {"signed_out", {pending, nil, body}},
          {"other_subject", {pending, "did:privy:luna", body}},
          {"unexpected_parameter", {pending, "did:privy:sol", Map.put(body, @marker, @marker)}},
          {"scope", {put_in(pending["params"]["scope"], @marker), "did:privy:sol", body}},
          {"inactive_subject",
           {%{pending | "subject" => "did:privy:gone"}, "did:privy:gone", body}},
          {"expired",
           {%{pending | "created_at" => pending["created_at"] - 601}, "did:privy:sol", body}},
          {"approval_key", {pending, "did:privy:sol", %{body | "approval_key" => @marker}}}
        ] do
      assert {%{status: 401}, ^reason} = refusal(fn -> approve(pending, subject, body) end)
    end

    assert {%{status: 401}, "body"} =
             refusal(fn ->
               conn(:post, "/oauth/authorize")
               |> init_test_session(%{regent_oauth_request: pending})
               |> assign(:subject, "did:privy:sol")
               |> unread()
               |> RegentOAuth.Consent.approve()
             end)

    assert %{status: 400, error: "invalid_request", reason: "decision"} =
             json_refusal(fn ->
               approve(pending, "did:privy:sol", %{body | "decision" => @marker})
             end)
  end

  test "approving when a published identity does not answer keeps its page, and is logged" do
    page = consent("did:privy:sol", authorize_params(@claude))
    assert page.status == 200
    pending = get_session(page, :regent_oauth_request)

    Repo.update_all(Document, set: [refresh_at: DateTime.add(DateTime.utc_now(), -1, :second)])
    Documents.serve(@claude, {:error, :timeout})

    assert {%{status: 503}, "unavailable"} =
             refusal(fn ->
               approve(pending, "did:privy:sol", %{
                 "approval_key" => pending["nonce"],
                 "decision" => "allow"
               })
             end)
  end
end

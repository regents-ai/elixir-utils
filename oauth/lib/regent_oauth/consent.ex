defmodule RegentOAuth.Consent do
  @moduledoc "Consent uses the site's current Privy session; parameters never supply a person."
  @behaviour Boruta.Oauth.AuthorizeApplication
  import Plug.Conn
  alias RegentOAuth.Protocol
  @session_key :regent_oauth_request

  def authorize(conn) do
    conn = fetch_query_params(conn)
    # ChatGPT sends this display hint. It grants no authority and is never
    # forwarded to Boruta or retained in the consent request.
    params = Map.delete(conn.query_params, "ui_locales")

    with true <- RegentOAuth.enabled?(),
         true <- Protocol.authorize_params?(params),
         true <- byte_size(Jason.encode!(conn.query_params)) <= 2048,
         {:ok, _client} <- Protocol.request_client(params) do
      case RegentOAuth.site().current_subject(conn) do
        subject when is_binary(subject) ->
          if RegentOAuth.site().active_subject?(subject) do
            Boruta.Oauth.preauthorize(
              authorization_conn(conn, params),
              %Boruta.Oauth.ResourceOwner{sub: subject},
              __MODULE__
            )
          else
            Protocol.json(conn, 401, %{error: "login_required"})
          end

        _ ->
          page(conn, "Sign in to connect", """
          <p>Open the website and sign in with Privy, then return here to continue.</p>
          <p><a href="/" target="_blank" rel="noopener">Open the website</a></p>
          <p><a href="#{escape(conn.request_path <> "?" <> conn.query_string)}">Continue after signing in</a></p>
          """)
      end
    else
      _ -> Protocol.json(conn, 400, %{error: "invalid_request"})
    end
  rescue
    _ -> Protocol.json(conn, 503, %{error: "temporarily_unavailable"})
  end

  @impl true
  def preauthorize_success(conn, authorization) do
    nonce = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    pending = %{
      "params" => conn.query_params,
      "subject" => authorization.sub,
      "nonce" => nonce,
      "created_at" => System.system_time(:second)
    }

    conn =
      conn |> put_session(@session_key, pending) |> allow_callback(authorization.redirect_uri)

    host = URI.parse(authorization.redirect_uri).host

    page(conn, "Connect #{authorization.client.name}", """
      <p>This app is asking to #{escape(Keyword.fetch!(RegentOAuth.config(), :permission_description))}.</p>
      <p>It cannot post, select a solution, pay or change your wallet. Public reads stay free.</p>
      <p>You will return to #{escape(host)}.</p>
      <form method="post" action="/oauth/authorize" class="rg-feature__actions">
        <input type="hidden" name="_csrf_token" value="#{escape(Plug.CSRFProtection.get_csrf_token())}">
        <input type="hidden" name="approval_key" value="#{nonce}">
        <button class="rg-button rg-button--primary" name="decision" value="allow">Allow updates</button>
        <button class="rg-button rg-button--secondary" name="decision" value="deny">Cancel</button>
      </form>
      <p><a href="/oauth/connections">Manage connected apps</a></p>
    """)
  end

  def approve(conn) do
    pending = get_session(conn, @session_key)
    conn = delete_session(conn, @session_key)
    subject = RegentOAuth.site().current_subject(conn)

    with true <- RegentOAuth.enabled?(),
         true <- is_map(conn.body_params) and not is_struct(conn.body_params),
         true <- Map.keys(conn.body_params) -- ~w(_csrf_token approval_key decision) == [],
         %{"subject" => ^subject, "nonce" => nonce, "params" => params, "created_at" => created} <-
           pending,
         true <- Protocol.authorize_params?(params),
         true <- is_binary(subject) and RegentOAuth.site().active_subject?(subject),
         true <- (System.system_time(:second) - created) in 0..600,
         key when is_binary(key) <- conn.body_params["approval_key"],
         true <- byte_size(key) == byte_size(nonce) and Plug.Crypto.secure_compare(key, nonce),
         {:ok, _} <- Protocol.request_client(params) do
      case conn.body_params["decision"] do
        "allow" ->
          Boruta.Oauth.authorize(
            authorization_conn(conn, params),
            %Boruta.Oauth.ResourceOwner{sub: subject},
            __MODULE__
          )

        "deny" ->
          error = %Boruta.Oauth.Error{
            status: :forbidden,
            error: :access_denied,
            error_description: "Connection declined.",
            format: :query,
            redirect_uri: params["redirect_uri"],
            state: params["state"]
          }

          redirect(conn, Boruta.Oauth.Error.redirect_to_url(error))

        _ ->
          Protocol.json(conn, 400, %{error: "invalid_request"})
      end
    else
      _ ->
        page(
          conn,
          "Start the connection again",
          """
          <p>This connection request has expired or was already used.</p>
          <p>Return to the app and start connecting again. No new access was granted by this request.</p>
          """,
          401
        )
    end
  rescue
    _ -> Protocol.json(conn, 503, %{error: "temporarily_unavailable"})
  end

  @impl true
  def authorize_success(conn, response),
    do: redirect(conn, Boruta.Oauth.AuthorizeResponse.redirect_to_url(response))

  @impl true
  def preauthorize_error(conn, error), do: authorize_error(conn, error)
  @impl true
  def authorize_error(conn, error) do
    # Boruta validates the client before supplying an error redirect. Sanitize
    # descriptions so internal failures never reach URLs or responses.
    if error.format && error.redirect_uri do
      clean = %{error | error_description: "This connection could not be authorized."}
      redirect(conn, Boruta.Oauth.Error.redirect_to_url(clean))
    else
      Protocol.json(conn, 400, %{error: "invalid_request"})
    end
  end

  def connections(conn) do
    case RegentOAuth.enabled?() && RegentOAuth.site().current_subject(conn) do
      subject when is_binary(subject) ->
        items = RegentOAuth.connected_clients(subject)
        csrf = escape(Plug.CSRFProtection.get_csrf_token())

        rows =
          Enum.map_join(items, "", fn app ->
            """
            <li>#{escape(app.name)}
              <form method="post" action="/oauth/connections/revoke">
                <input type="hidden" name="_csrf_token" value="#{csrf}">
                <input type="hidden" name="client_id" value="#{app.id}">
                <button class="rg-button rg-button--secondary">Disconnect</button>
              </form>
            </li>
            """
          end)

        body = if items == [], do: "<p>No apps are connected.</p>", else: "<ul>#{rows}</ul>"
        page(conn, "Connected apps", body)

      _ ->
        Protocol.json(conn, 401, %{error: "login_required"})
    end
  rescue
    _ -> Protocol.json(conn, 503, %{error: "temporarily_unavailable"})
  end

  def revoke_connection(conn) do
    subject = RegentOAuth.site().current_subject(conn)

    with true <-
           RegentOAuth.enabled?() and is_binary(subject) and
             RegentOAuth.site().active_subject?(subject),
         {:ok, client_id} <- Ecto.UUID.cast(conn.body_params["client_id"]),
         {:ok, :ok} <- RegentOAuth.revoke_client(subject, client_id) do
      redirect(conn, "/oauth/connections")
    else
      _ -> Protocol.json(conn, 401, %{error: "not_authorized"})
    end
  rescue
    _ -> Protocol.json(conn, 503, %{error: "temporarily_unavailable"})
  end

  defp page(conn, title, body, status \\ 200) do
    brand = Keyword.get(RegentOAuth.config(), :brand, "platform")
    theme = conn.assigns[:theme]
    theme_attr = if theme in ["light", "dark"], do: ~s( data-theme="#{theme}"), else: ""
    host = URI.parse(RegentOAuth.issuer()).host

    html = """
    <!doctype html><html lang="en" data-brand="#{escape(brand)}"#{theme_attr}><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <meta name="color-scheme" content="light dark">
    <link rel="stylesheet" href="/assets/js/app.css">
    <title>#{escape(title)}</title></head><body>
    <main class="rg-sheet rg-frame" style="max-width:42rem;margin:clamp(2rem,10vh,6rem) auto">
    <section class="rg-panel rg-panel--surface" style="padding:var(--rg-panel-padding,2rem)">
    <p style="margin-bottom:var(--space-3,1.5rem)"><a href="/">#{escape(host)}</a> / Connected apps</p>
    <h1 style="font-size:1.75rem;line-height:1.2;margin-bottom:var(--space-3,1.5rem)">#{escape(title)}</h1>
    <div style="display:grid;gap:var(--space-3,1.5rem)">#{body}</div>
    </section></main></body></html>
    """

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_content_type("text/html")
    |> send_resp(status, html)
  end

  # Chromium checks the return redirect against the submitting document's policy.
  # Only this validated client's origin is added, only to this consent document.
  # Encode untrusted URI characters so client metadata cannot add CSP directives.
  defp allow_callback(conn, redirect_uri) do
    uri = URI.parse(redirect_uri)

    source =
      %URI{scheme: uri.scheme, host: uri.host, port: uri.port}
      |> URI.to_string()
      |> URI.encode(&(URI.char_unreserved?(&1) or &1 in ~c":/[]"))

    policies =
      case get_resp_header(conn, "content-security-policy") do
        [] -> ["default-src 'none'; base-uri 'none'; frame-ancestors 'none'"]
        existing -> existing
      end

    policies =
      policies
      |> Enum.flat_map(&String.split(&1, ",", trim: true))
      |> Enum.map_join(", ", fn policy ->
        directives =
          policy
          |> String.split(";", trim: true)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.reject(&String.match?(&1, ~r/\Aform-action(?:\s|\z)/i))

        Enum.join(directives ++ ["form-action 'self' #{source}"], "; ")
      end)

    put_resp_header(conn, "content-security-policy", policies)
  end

  defp redirect(conn, url),
    do:
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("location", url)
      |> send_resp(303, "")

  # Boruta also accepts request objects from GET bodies and approval POST bodies.
  # Pass only the validated request the person saw, never fresh grant parameters.
  defp authorization_conn(conn, params),
    do: %{conn | query_params: params, body_params: %{}, params: params}

  defp escape(value),
    do: value |> to_string() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end

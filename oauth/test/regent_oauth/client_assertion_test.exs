defmodule RegentOAuth.ClientAssertionTest do
  # An app whose published identity says `private_key_jwt` (ChatGPT's shape)
  # signs every token and revocation request with a key it publishes at its
  # own host.
  use RegentOAuth.Case

  import Plug.Conn
  import Plug.Test

  alias RegentOAuth.Test.{Documents, Flow}

  @app "https://chatgpt.com/oauth/a1b2c3/client.json"
  @keys "https://chatgpt.com/oauth/jwks.json"
  @urn "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
  @verifier String.duplicate("v", 43)

  setup_all do
    %{rsa: signing_key({:rsa, 2048}, "rsa-1", "RS256")}
  end

  setup %{rsa: rsa} do
    # Kept key sets live in Boruta's cache, which outlives each test's
    # rolled-back database.
    {:ok, _} = Boruta.Config.cache_backend().delete_all()
    Documents.serve(@app, document(@app, @keys))
    Documents.serve(@keys, key_set([rsa]))
    :ok
  end

  defp signing_key(kind, kid, alg) do
    private = JOSE.JWK.generate_key(kind)
    {_, public} = JOSE.JWK.to_public_map(private)

    %{
      private: private,
      kid: kid,
      alg: alg,
      public: Map.merge(public, %{"kid" => kid, "alg" => alg, "use" => "sig"})
    }
  end

  defp document(url, keys, changes \\ %{}) do
    body =
      Map.merge(
        %{
          "client_id" => url,
          "client_name" => "ChatGPT",
          "redirect_uris" => [callback(url)],
          "grant_types" => ["authorization_code", "refresh_token"],
          "response_types" => ["code"],
          "token_endpoint_auth_method" => "private_key_jwt",
          "token_endpoint_auth_methods_supported" => ["none", "private_key_jwt"],
          "token_endpoint_auth_signing_alg" => "RS256",
          "jwks_uri" => keys
        },
        changes
      )

    %{status: 200, headers: [{"content-type", "application/json"}], body: Jason.encode!(body)}
  end

  defp key_set(keys) do
    %{
      status: 200,
      headers: [{"content-type", "application/json"}],
      body: Jason.encode!(%{"keys" => Enum.map(keys, & &1.public)})
    }
  end

  defp claims(changes \\ %{}, client \\ @app) do
    now = System.system_time(:second)

    %{
      "iss" => client,
      "sub" => client,
      "aud" => RegentOAuth.issuer(),
      "iat" => now,
      "exp" => now + 300,
      "jti" => Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    }
    |> Map.merge(changes)
    |> Map.reject(fn {_, value} -> is_nil(value) end)
  end

  defp sign(key, claims, header \\ %{}) do
    header =
      %{"alg" => key.alg, "kid" => key.kid, "typ" => "client-authentication+jwt"}
      |> Map.merge(header)
      |> Map.reject(fn {_, value} -> is_nil(value) end)

    {_, token} = key.private |> JOSE.JWT.sign(header, claims) |> JOSE.JWS.compact()
    token
  end

  defp auth(assertion), do: %{"client_assertion_type" => @urn, "client_assertion" => assertion}

  # Each app's callback is on its own host, as a published identity's must be.
  defp callback(client_id),
    do: "https://#{URI.parse(client_id).host}/connector_platform_oauth_redirect"

  defp authorize_query(client_id) do
    URI.encode_query(%{
      "client_id" => client_id,
      "redirect_uri" => callback(client_id),
      "response_type" => "code",
      "scope" => RegentOAuth.scope(),
      "state" => "state",
      "resource" => RegentOAuth.resource(),
      "code_challenge" => :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false),
      "code_challenge_method" => "S256"
    })
  end

  defp consent(subject, client_id) do
    conn(:get, "/oauth/authorize?" <> authorize_query(client_id))
    |> init_test_session(%{})
    |> assign(:subject, subject)
    |> RegentOAuth.Consent.authorize()
  end

  # A code for `subject`, through consent and Allow as a person gives it.
  defp code!(subject, client_id \\ @app) do
    page = consent(subject, client_id)
    200 = page.status
    pending = get_session(page, :regent_oauth_request)

    approved =
      conn(:post, "/oauth/authorize")
      |> init_test_session(%{regent_oauth_request: pending})
      |> assign(:subject, subject)
      |> Map.put(:body_params, %{"approval_key" => pending["nonce"], "decision" => "allow"})
      |> RegentOAuth.Consent.approve()

    [location] = get_resp_header(approved, "location")
    URI.decode_query(URI.parse(location).query)["code"]
  end

  defp exchange(code, extra, client_id \\ @app) do
    Flow.post(
      :token,
      Map.merge(
        %{
          "grant_type" => "authorization_code",
          "client_id" => client_id,
          "code" => code,
          "code_verifier" => @verifier,
          "redirect_uri" => callback(client_id),
          "resource" => RegentOAuth.resource()
        },
        extra
      )
    )
  end

  defp refresh(refresh_token, extra) do
    Flow.post(
      :token,
      Map.merge(
        %{
          "grant_type" => "refresh_token",
          "client_id" => @app,
          "refresh_token" => refresh_token,
          "resource" => RegentOAuth.resource()
        },
        extra
      )
    )
  end

  defp invalid_client?(conn),
    do: conn.status == 401 and Jason.decode!(conn.resp_body) == %{"error" => "invalid_client"}

  test "a document that signs with a key at its own host is kept with its method and keys" do
    assert consent("did:privy:sol", @app).status == 200
    assert_received {:read, @app}

    {:ok, id} = RegentOAuth.ClientDocuments.stored(@app)

    assert %{
             token_endpoint_auth_methods: ["private_key_jwt"],
             jwks_uri: @keys,
             confidential: false,
             pkce: true
           } = RegentOAuth.Test.Repo.get!(Boruta.Ecto.Client, id)

    # Consent never reads the keys; the token address does.
    refute_received {:read, @keys}
  end

  test "an RS256 sign-in: code, refresh, the assertion alone naming the app, and revocation", %{
    rsa: rsa
  } do
    code = code!("did:privy:sol")
    token = exchange(code, auth(sign(rsa, claims())))
    assert token.status == 200
    assert_received {:read, @keys}

    %{"access_token" => access, "refresh_token" => refresh_token} = Jason.decode!(token.resp_body)

    assert {:ok, %{subject: "did:privy:sol", client_id: client_id}} =
             RegentOAuth.verify(access, RegentOAuth.resource())

    assert [%{id: ^client_id, name: "ChatGPT"}] = RegentOAuth.connected_clients("did:privy:sol")

    # The token address's own URL is an audience too, and a refresh may leave
    # out `client_id`: the assertion names the app.
    assertion = sign(rsa, claims(%{"aud" => [RegentOAuth.token_endpoint()]}))

    refreshed =
      Flow.post(:token, %{
        "grant_type" => "refresh_token",
        "refresh_token" => refresh_token,
        "client_assertion_type" => @urn,
        "client_assertion" => assertion
      })

    assert refreshed.status == 200
    %{"access_token" => access} = Jason.decode!(refreshed.resp_body)

    # The kept set served both requests.
    refute_received {:read, @keys}

    # Revocation authenticates the same way.
    assert invalid_client?(Flow.post(:revoke, %{"client_id" => @app, "token" => access}))
    assert {:ok, _} = RegentOAuth.verify(access, RegentOAuth.resource())

    revoked =
      Flow.post(
        :revoke,
        Map.merge(%{"client_id" => @app, "token" => access}, auth(sign(rsa, claims())))
      )

    assert revoked.status == 200
    assert {:error, :unauthorized} = RegentOAuth.verify(access, RegentOAuth.resource())
  end

  test "an ES256 key signs as well" do
    app = "https://agent.example/oauth/client.json"
    keys = "https://agent.example/oauth/jwks.json"
    ec = signing_key({:ec, "P-256"}, "ec-1", "ES256")
    Documents.serve(app, document(app, keys, %{"token_endpoint_auth_signing_alg" => "ES256"}))
    Documents.serve(keys, key_set([ec]))

    token = exchange(code!("did:privy:sol", app), auth(sign(ec, claims(%{}, app))), app)
    assert token.status == 200
    assert %{"access_token" => _} = Jason.decode!(token.resp_body)
  end

  test "each refused assertion is invalid_client and leaves the code unspent", %{rsa: rsa} do
    code = code!("did:privy:sol")
    now = System.system_time(:second)
    other = signing_key({:rsa, 2048}, "rsa-1", "RS256")
    {_, public_pem} = JOSE.JWK.to_pem(JOSE.JWK.to_public(rsa.private))
    raw = &Base.url_encode64(Jason.encode!(&1), padding: false)

    refused = [
      no_assertion: %{},
      pkce_alone_with_type: %{"client_assertion_type" => @urn},
      wrong_type: %{
        "client_assertion_type" => "urn:ietf:params:oauth:client-assertion-type:saml2-bearer",
        "client_assertion" => sign(rsa, claims())
      },
      wrong_iss:
        auth(sign(rsa, claims(%{"iss" => "https://chatgpt.com/oauth/other/client.json"}))),
      wrong_sub:
        auth(sign(rsa, claims(%{"sub" => "https://chatgpt.com/oauth/other/client.json"}))),
      other_server: auth(sign(rsa, claims(%{"aud" => "https://elsewhere.example"}))),
      issuer_prefix: auth(sign(rsa, claims(%{"aud" => RegentOAuth.issuer() <> ".evil.example"}))),
      two_audiences:
        auth(sign(rsa, claims(%{"aud" => [RegentOAuth.issuer(), "https://x.example"]}))),
      expired: auth(sign(rsa, claims(%{"exp" => now - 1}))),
      too_far: auth(sign(rsa, claims(%{"exp" => now + 7_200}))),
      no_exp: auth(sign(rsa, claims(%{"exp" => nil}))),
      not_yet: auth(sign(rsa, claims(%{"nbf" => now + 600}))),
      no_jti: auth(sign(rsa, claims(%{"jti" => nil}))),
      wrong_key: auth(sign(other, claims())),
      hs256_with_public_key:
        auth(
          sign(
            %{private: JOSE.JWK.from_oct(public_pem), alg: "HS256", kid: "rsa-1"},
            claims()
          )
        ),
      alg_none: auth(raw.(%{"alg" => "none", "kid" => "rsa-1"}) <> "." <> raw.(claims()) <> "."),
      not_a_jwt: auth("not.a.jwt")
    ]

    for {name, extra} <- refused do
      assert invalid_client?(exchange(code, extra)), "#{name}"
    end

    # Nothing was spent: the same code still works with a good assertion.
    assert exchange(code, auth(sign(rsa, claims()))).status == 200
  end

  test "a jti is used once" do
    rsa = signing_key({:rsa, 2048}, "rsa-2", "RS256")
    Documents.serve(@keys, key_set([rsa]))
    assertion = sign(rsa, claims())

    token = exchange(code!("did:privy:sol"), auth(assertion))
    assert token.status == 200
    %{"refresh_token" => refresh_token} = Jason.decode!(token.resp_body)

    assert invalid_client?(refresh(refresh_token, auth(assertion)))
    assert invalid_client?(exchange(code!("did:privy:luna"), auth(assertion)))
    assert refresh(refresh_token, auth(sign(rsa, claims()))).status == 200
  end

  test "PKCE is still required of an app that signs", %{rsa: rsa} do
    params = %{
      "grant_type" => "authorization_code",
      "client_id" => @app,
      "code" => code!("did:privy:sol"),
      "redirect_uri" => callback(@app),
      "resource" => RegentOAuth.resource()
    }

    for verifier <- [nil, String.duplicate("w", 43)] do
      params = if verifier, do: Map.put(params, "code_verifier", verifier), else: params
      refused = Flow.post(:token, Map.merge(params, auth(sign(rsa, claims()))))
      assert refused.status == 400
      refute Map.has_key?(Jason.decode!(refused.resp_body), "access_token")
    end
  end

  test "a rotated key is found by reading the keys again once", %{rsa: rsa} do
    assert exchange(code!("did:privy:sol"), auth(sign(rsa, claims()))).status == 200
    assert_received {:read, @keys}

    rotated = signing_key({:rsa, 2048}, "rsa-next", "RS256")
    Documents.serve(@keys, key_set([rsa, rotated]))

    assert exchange(code!("did:privy:luna"), auth(sign(rotated, claims()))).status == 200
    assert_received {:read, @keys}

    # With two keys published, an assertion must say which.
    assert invalid_client?(
             exchange(code!("did:privy:sol"), auth(sign(rsa, claims(), %{"kid" => nil})))
           )
  end

  test "an unknown key id reads the keys again at most once a minute", %{rsa: rsa} do
    assert exchange(code!("did:privy:sol"), auth(sign(rsa, claims()))).status == 200
    assert_received {:read, @keys}

    code = code!("did:privy:luna")
    assert invalid_client?(exchange(code, auth(sign(%{rsa | kid: "nobody"}, claims()))))
    assert_received {:read, @keys}

    for kid <- ["nobody-2", "nobody-3"] do
      assert invalid_client?(exchange(code, auth(sign(%{rsa | kid: kid}, claims()))))
    end

    refute_received {:read, @keys}

    # The known key still signs, and the refusals left the code unspent.
    assert exchange(code, auth(sign(rsa, claims()))).status == 200
  end

  test "keys that cannot be read just now make the request unavailable", %{rsa: rsa} do
    Documents.serve(@keys, {:error, :timeout})
    code = code!("did:privy:sol")

    unavailable = exchange(code, auth(sign(rsa, claims())))
    assert unavailable.status == 503
    assert Jason.decode!(unavailable.resp_body) == %{"error" => "temporarily_unavailable"}
  end

  test "an app that authenticates with nothing may not send an assertion", %{rsa: rsa} do
    claude = Documents.claude_url()
    Documents.serve(claude, Documents.claude())

    {:ok, client} =
      RegentOAuth.Protocol.request_client(%{
        "client_id" => claude,
        "redirect_uri" => "https://claude.ai/api/mcp/auth_callback"
      })

    code = Flow.code!(client.id, "did:privy:sol")

    params = %{
      "grant_type" => "authorization_code",
      "client_id" => claude,
      "code" => code,
      "code_verifier" => @verifier,
      "redirect_uri" => "https://claude.ai/api/mcp/auth_callback",
      "resource" => RegentOAuth.resource()
    }

    assertion = sign(rsa, claims(%{}, claude))
    assert invalid_client?(Flow.post(:token, Map.merge(params, auth(assertion))))
    assert invalid_client?(Flow.post(:token, Map.put(params, "client_assertion_type", @urn)))
    assert Flow.post(:token, params).status == 200
  end

  test "documents that sign are refused unless their keys are at their own host and allowed" do
    for {change, changes} <- [
          keys_elsewhere: %{"jwks_uri" => "https://keys.example/jwks.json"},
          keys_on_another_port: %{"jwks_uri" => "https://chatgpt.com:8443/oauth/jwks.json"},
          keys_over_http: %{"jwks_uri" => "http://chatgpt.com/oauth/jwks.json"},
          no_keys: %{"jwks_uri" => nil},
          keys_written_in: %{"jwks" => %{"keys" => []}},
          disallowed_alg: %{"token_endpoint_auth_signing_alg" => "PS256"},
          shared_secret: %{"token_endpoint_auth_method" => "client_secret_jwt"}
        ] do
      body = @app |> document(@keys) |> Map.fetch!(:body) |> Jason.decode!() |> Map.merge(changes)
      body = Map.reject(body, fn {_, value} -> is_nil(value) end)
      Documents.serve(@app, %{document(@app, @keys) | body: Jason.encode!(body)})
      assert consent("did:privy:sol", @app).status == 400, "#{change}"
    end

    refute_received {:read, @keys}
  end
end

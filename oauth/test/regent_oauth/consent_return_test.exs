defmodule RegentOAuth.ConsentReturnTest do
  # Chromium refused to follow Allow's redirect: it checks every host a form's
  # redirects pass through against the site's `form-action`, and an app's
  # callback sends the browser on to another host (18 Nov 2026). The consent
  # page keeps the site's own policy, and Allow and Cancel answer with a page
  # that takes the browser to the app by itself.
  use RegentOAuth.Case

  import Plug.Conn
  import Plug.Test

  alias RegentOAuth.Test.{Flow, Return}

  @verifier String.duplicate("v", 43)
  @policy "default-src 'none'; style-src 'self'; form-action 'self'; frame-ancestors 'none'"

  defp consent(client_id, state) do
    params = %{
      "client_id" => client_id,
      "redirect_uri" => "https://claude.ai/api/mcp/auth_callback",
      "response_type" => "code",
      "scope" => RegentOAuth.scope(),
      "state" => state,
      "resource" => RegentOAuth.resource(),
      "code_challenge" => :crypto.hash(:sha256, @verifier) |> Base.url_encode64(padding: false),
      "code_challenge_method" => "S256"
    }

    conn(:get, "/oauth/authorize?" <> URI.encode_query(params))
    |> init_test_session(%{})
    |> put_resp_header("content-security-policy", @policy)
    |> assign(:subject, "did:privy:sol")
    |> RegentOAuth.Consent.authorize()
  end

  defp press(page, decision) do
    pending = get_session(page, :regent_oauth_request)

    conn(:post, "/oauth/authorize")
    |> init_test_session(%{regent_oauth_request: pending})
    |> assign(:subject, "did:privy:sol")
    |> Map.put(:body_params, %{"approval_key" => pending["nonce"], "decision" => decision})
    |> RegentOAuth.Consent.approve()
  end

  test "the consent page keeps the site's own policy" do
    page = consent(Flow.client!(), "state")
    assert page.status == 200
    assert get_resp_header(page, "content-security-policy") == [@policy]
  end

  test "Allow and Cancel return a state with quotes, brackets and ampersands exactly, inside the page's address" do
    state = ~s(a"b<c>d&e'f)
    client_id = Flow.client!()

    for decision <- ["allow", "deny"] do
      returned = press(consent(client_id, state), decision)
      assert returned.status == 200
      assert get_resp_header(returned, "location") == []
      assert get_resp_header(returned, "cache-control") == ["no-store"]
      assert get_resp_header(returned, "referrer-policy") == ["no-referrer"]

      # The address never leaves its attribute: no quote or bracket, and each
      # ampersand starts an entity.
      for [value] <- Regex.scan(~r/(?<=content="0;url=|href=")[^"]*/, returned.resp_body),
          value != "/" do
        refute value =~ ~r/[<>"']/
        refute value =~ ~r/&(?!amp;)/
      end

      query = URI.decode_query(URI.parse(Return.address(returned)).query)
      assert query["state"] == state

      case decision do
        "allow" -> assert Flow.exchange(client_id, query["code"]).status == 200
        "deny" -> assert %{"error" => "access_denied"} = query
      end
    end
  end
end

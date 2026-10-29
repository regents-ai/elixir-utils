defmodule RegentMCPAgents do
  @moduledoc """
  A connected app's (ChatGPT's or Claude's) persistent connection to a Regents
  account identity, shared across chats. OAuth authorizes the connection; the
  SIWA service's hosted signing holds its signer, asked with this site's own
  hosted signing key. Every identity request it signs still passes
  exact-request SIWA verification. A site's own tools admit the connection's
  token as the agent it paired, by its address (`address/1`), and sign
  nothing. Conversation IDs, tool arguments and MCP sessions never select the
  signer.

  The connected apps a site offers are `RegentAgents.Harness.hosted/0`.

  A tool answers `{:ok, fields}`; `{:answer, status, body, retry_after}`, the
  site's own answer to a signed request it refused, with its code, words and
  `Retry-After`; `{:refused, status, error}`, a refusal this library makes
  before anything is signed, as an `{"code", "message", "hint"}` map;
  `{:error, {:rate_limited, seconds}}` when the signer or the site said to wait;
  or `{:error, reason}` when no answer came, which a tool call gives in the
  site's `refusal:` words.
  """
  alias RegentAgents.{Harness, PairingCode, Person}

  @identity_scope "regent.identity.manage"
  @posting_scope "patchbay.posts.write"
  @refusal "Connect your Regents account, register the connection, and check its pairing on the account page."

  # The refusals made here, before anything is signed.
  @pairing_input %{
    "code" => "invalid_request",
    "message" =>
      "Pairing takes a code, a name of 1 to 100 characters and one of this site's harnesses.",
    "hint" => "Call pair_identity with code, name and harness as tools/list describes them."
  }
  @pairing_code %{
    "code" => "pairing_code_unknown",
    "message" =>
      "This pairing code isn't a current one from your account: it was used, it is more than ten minutes old, or another account made it.",
    "hint" =>
      "Ask your person for a new code from Pair New Agent, then call pair_identity with it."
  }

  # Where every site mounts `RegentAgents.HTTP`, and how its endpoint reads an
  # agent request there: the SIWA plug's reader keeps the exact bytes, at most
  # 4096 of them.
  @agents_path "/api/agents/v1/"
  @agent_body_limit 4_096
  @agent_parsers [
    parsers: [:json],
    json_decoder: Jason,
    pass: ["*/*"],
    body_reader: {Siwa.AgentAuthPlug, :read_body, [@agent_body_limit]}
  ]

  @doc "Validate opt-in runtime configuration before accepting connections."
  def configure! do
    opts = config()

    if opts[:enabled?] == true do
      # Never fetch!: its KeyError prints the settings it searched, key included.
      signer = opts[:hosted_signer]
      signer = if Keyword.keyword?(signer), do: signer, else: []
      base_url = signer[:base_url]
      key = signer[:key]
      uri = URI.parse(if is_binary(base_url), do: base_url, else: "")

      safe_origin? =
        uri.scheme == "https" or
          (uri.scheme == "http" and uri.host in ["localhost", "127.0.0.1"])

      unless is_binary(base_url) and RegentOAuth.enabled?() and
               @identity_scope in RegentOAuth.scopes() and safe_origin? and
               is_binary(uri.host) and uri.path in [nil, ""] and
               is_nil(uri.query) and is_nil(uri.fragment) and is_nil(uri.userinfo) and
               is_binary(key) and Regex.match?(~r/\A[A-Za-z0-9_-]{32,}\z/, key) and
               opts[:audience] in ["patchbay", "keyfleet", "ash-template"] and
               Harness.hosted() != [] and refusal_text?(Keyword.get(opts, :refusal, @refusal)),
             do:
               raise(
                 ArgumentError,
                 "Hosted identity requires a fixed HTTPS signer, this site's hosted signing key, a known audience, " <>
                   "at least one hosted runtime in `config :regent_agents, hosted_pairing:` and refusal words of 1 to 500 bytes"
               )
    end

    :ok
  end

  def enabled?, do: config()[:enabled?] == true

  def identity_scope, do: @identity_scope
  def posting_scope, do: @posting_scope

  @doc "The words a refused tool call gives: the site's `refusal:` setting, or a plain default."
  def refusal_text, do: Keyword.get(config(), :refusal, @refusal)

  defp refusal_text?(text), do: is_binary(text) and byte_size(text) in 1..500

  @doc "Create or return this account's persistent signer, without pairing it."
  def register(principal) do
    with :ok <- authority(principal, @identity_scope),
         {:ok, _public} <- signer_request(principal, %{"operation" => "register"}) do
      {:ok,
       %{
         identity_id: connection_key(principal),
         account_url: RegentOAuth.issuer() <> "/account"
       }}
    end
  end

  @doc """
  The wallet address of this account's one identity on this site, lowercase, as
  the hosted signer's register answer gives it. A site admits a connected app
  as the agent it paired by this address: the token is the sign-in, the site's
  own pairing record says whose agent it is, and its policies decide the rest,
  so nothing is signed. An account's address on a site never changes, so the
  site may keep it.
  """
  def address(principal) do
    with :ok <- authority(principal, @identity_scope),
         {:ok, %{"address" => address}} when is_binary(address) <-
           signer_request(principal, %{"operation" => "register"}),
         address = String.downcase(address),
         true <- Regex.match?(~r/\A0x[0-9a-f]{40}\z/, address) do
      {:ok, address}
    else
      _ -> {:error, :identity_request_refused}
    end
  end

  @doc "Read the current pairing through a freshly SIWA-signed, non-awarding identity probe."
  def status(principal) do
    with :ok <- authority(principal, @identity_scope),
         {:ok, %{"data" => data}} <- perform(principal, :whoami) do
      {:ok,
       %{
         identity_id: connection_key(principal),
         paired: not is_nil(data["pairing"]),
         account_url: RegentOAuth.issuer() <> "/account"
       }}
    end
  end

  @doc "Check in with a freshly SIWA-signed request, so the person sees the connection is active."
  def check_in(principal) do
    with :ok <- authority(principal, @identity_scope),
         {:ok, %{"data" => data}} <- perform(principal, :check_in) do
      {:ok, Map.put(data, "identity_id", connection_key(principal))}
    end
  end

  @doc """
  Redeem only a code made by the authenticated account, using the hosted signer,
  as the connected app it names, one of the site's `RegentAgents.Harness.hosted/0`.
  """
  def pair(principal, %{"code" => code, "name" => name, "harness" => harness} = args)
      when map_size(args) == 3 and is_binary(code) and byte_size(code) in 1..128 and
             is_binary(name) and is_binary(harness) do
    with :ok <- authority(principal, @identity_scope),
         true <- String.length(name) in 1..100,
         true <- harness in hosted_names(),
         :ok <- own_code(principal.subject, code),
         {:ok, %{"data" => _data}} <-
           perform(principal, {:pair, Jason.encode!(%{code: code, name: name, harness: harness})}) do
      {:ok, %{identity_id: connection_key(principal), paired: true, name: name}}
    else
      {:answer, _status, _body, _retry_after} = answer -> answer
      {:refused, _status, _error} = refused -> refused
      {:error, {:rate_limited, _seconds}} = limited -> limited
      false -> {:refused, 422, @pairing_input}
      _no_answer -> {:error, :pairing_refused}
    end
  end

  def pair(_, _), do: {:refused, 422, @pairing_input}

  @doc "Forward a free question or reply through the site's restricted SIWA participation door."
  def post(principal, name, arguments)
      when name in ["ask_question", "post_reply"] and is_map(arguments) do
    with :ok <- authority(principal, @posting_scope),
         "patchbay" <- config()[:audience] do
      body =
        Jason.encode!(%{
          jsonrpc: "2.0",
          id: Ecto.UUID.generate(),
          method: "tools/call",
          params: %{name: name, arguments: arguments}
        })

      perform(principal, {:post, body})
    else
      _ -> {:error, :posting_refused}
    end
  end

  def post(_, _, _), do: {:error, :posting_refused}

  @doc """
  The key one account's connection has on one site, derived from the site's
  audience and the account. Two sites never derive the same key, so one person's
  signers on different sites are unrelated and their addresses cannot link the
  person's accounts across sites.
  """
  def identity_key(audience, subject) when is_binary(audience) and is_binary(subject) do
    :crypto.hash(:sha256, Jason.encode!(["regent-chatgpt-account-v1", audience, subject]))
    |> Base.encode16(case: :lower)
  end

  @doc "The refusal for a malformed `pair_identity` call, for a site serving the tool itself."
  def pairing_input_refusal, do: @pairing_input

  @doc false
  def hosted_names, do: Enum.map(Harness.hosted(), &Atom.to_string/1)

  defp config, do: Application.get_env(:regent_mcp_agents, :config, [])

  defp authority(
         %{subject: subject, token_id: token, client_id: client, scopes: scopes},
         required
       )
       when is_binary(subject) and is_list(scopes) do
    if config()[:enabled?] == true and required in scopes and
         RegentOAuth.live_token?(token, subject, client),
       do: :ok,
       else: {:error, :connection_required}
  end

  defp authority(_, _), do: {:error, :connection_required}

  defp connection_key(principal),
    do: identity_key(Keyword.fetch!(config(), :audience), principal.subject)

  defp own_code(subject, code) do
    codes =
      PairingCode
      |> Ash.Query.for_read(:for_person, %{}, actor: %Person{privy_user_id: subject})
      |> Ash.read!()

    hash = PairingCode.hash(String.trim(code))

    if Enum.any?(
         codes,
         &(&1.code_hash == hash and is_nil(&1.used_at) and
             DateTime.after?(&1.expires_at, DateTime.utc_now()))
       ), do: :ok, else: {:refused, 403, @pairing_code}
  end

  # The SIWA service takes the audience from this site's hosted signing key and
  # binds every signer to it; the request names no site.
  defp signer_request(principal, payload) do
    signer = Keyword.fetch!(config(), :hosted_signer)

    case http_request(
           method: :post,
           url: Keyword.fetch!(signer, :base_url) <> "/api/shared/siwa/hosted",
           auth: {:bearer, Keyword.fetch!(signer, :key)},
           json: Map.put(payload, "identity_key", connection_key(principal)),
           receive_timeout: 15_000
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %{status: 429} = response} -> response |> retry_after() |> wait()
      _ -> {:error, :identity_request_refused}
    end
  end

  # The only requests the hosted signer is ever asked to sign, each for this
  # account's one identity on this site: the identity probe, the check-in, the
  # pairing and Patchbay's free posts, with the permission each needs. The
  # method and path come from here alone; a tool's arguments reach only the
  # pairing's and a post's body, which their own tools build.
  defp signable(:whoami),
    do: {@identity_scope, %{"method" => "GET", "path" => "/api/agents/v1/whoami"}}

  defp signable(:check_in),
    do: {@identity_scope, %{"method" => "GET", "path" => "/api/agents/v1/me"}}

  defp signable({:pair, body}),
    do: {@identity_scope, %{"method" => "POST", "path" => "/api/agents/v1/pair", "body" => body}}

  defp signable({:post, body}),
    do: {@posting_scope, %{"method" => "POST", "path" => "/chatgpt/agent/mcp", "body" => body}}

  # The connection's own Bearer token never leaves this site: the signer is
  # asked with the site's hosted signing key, and the signed request carries
  # only the headers the signer returned.
  defp perform(principal, operation) do
    {required, request} = signable(operation)

    with {:ok, envelope} <-
           signer_request(principal, %{"operation" => "sign", "request" => request}),
         :ok <- authority(principal, required),
         true <-
           envelope["method"] == request["method"] and envelope["path"] == request["path"] and
             envelope["body"] == request["body"] and is_map(envelope["headers"]),
         # Lowercase names, as Plug keeps them; the signature covers values.
         headers =
           envelope["headers"]
           |> Map.new(fn {name, value} -> {String.downcase(name), value} end)
           |> Map.put("content-type", "application/json"),
         {:ok, status, body, retry_after} <- send_signed(request, headers) do
      answer(status, body, retry_after)
    else
      {:error, {:rate_limited, _seconds}} = limited -> limited
      _ -> {:error, :identity_request_refused}
    end
  end

  # A site's own answer is passed on with its code, words and `Retry-After`; a
  # 429 is a wait instead.
  defp answer(status, body, _retry_after) when status in 200..299 and is_map(body),
    do: {:ok, body}

  defp answer(429, _body, retry_after), do: wait(retry_after)

  defp answer(status, body, retry_after) when is_map(body),
    do: {:answer, status, body, retry_after}

  defp answer(_status, _body, _retry_after), do: {:error, :identity_request_refused}

  # A 429 from the signer or the signed request means wait, not refused: the
  # tool answers with the seconds its `Retry-After` names.
  defp wait(seconds) when is_binary(seconds) do
    case Integer.parse(seconds) do
      {seconds, ""} when seconds > 0 -> {:error, {:rate_limited, seconds}}
      _ -> {:error, :identity_request_refused}
    end
  end

  defp wait(_), do: {:error, :identity_request_refused}

  defp retry_after(response),
    do: response |> Req.Response.get_header("retry-after") |> List.first()

  # An identity request goes to this site's own `RegentAgents.HTTP` in this
  # process, as the exact request the hosted signer signed: its method, path,
  # signed headers and body bytes, read by the SIWA plug's reader as the site's
  # endpoint reads them. The SIWA service verifies it exactly as it would a
  # request that came over the network. Sent over the network it would leave
  # and come back in from the site's own address, so every connected account
  # would share that one address's budget; the per-account budget at the MCP
  # address is the one that bounds it. Patchbay's posting door is that site's
  # own route, outside this library, so a post still goes over HTTPS.
  defp send_signed(%{"path" => @agents_path <> route} = request, headers) do
    body = request["body"] || ""

    if byte_size(body) <= @agent_body_limit,
      do: forward_signed(request, route, body, headers),
      else: :error
  end

  defp send_signed(request, headers) do
    case http_request(
           method: request["method"] |> String.downcase() |> String.to_existing_atom(),
           url: RegentOAuth.issuer() <> request["path"],
           headers: headers,
           body: request["body"],
           receive_timeout: 15_000
         ) do
      {:ok, %{status: status, body: body} = response} ->
        {:ok, status, body, retry_after(response)}

      _ ->
        :error
    end
  end

  # Anything the inner request raises is a refused tool call, never a failed MCP
  # request, and its log metadata is not left on the outer one.
  defp forward_signed(request, route, body, headers) do
    metadata = Logger.metadata()

    try do
      conn =
        request["method"]
        |> Plug.Test.conn(RegentOAuth.issuer() <> request["path"], body)
        |> Map.replace!(:req_headers, Map.to_list(headers))
        |> Plug.Parsers.call(Plug.Parsers.init(@agent_parsers))
        |> Plug.forward(String.split(route, "/"), RegentAgents.HTTP, [])
        |> take_answer()

      with answer when is_binary(answer) <- conn.resp_body,
           {:ok, decoded} <- Jason.decode(answer) do
        {:ok, conn.status, decoded,
         conn |> Plug.Conn.get_resp_header("retry-after") |> List.first()}
      else
        _ -> :error
      end
    rescue
      _ -> :error
    after
      Logger.reset_metadata(metadata)
    end
  end

  # `Plug.Test.conn/3` is Plug's one in-memory connection. It tells this
  # process about each answer it sends, as two messages; they are taken here,
  # as Req takes them for its own in-memory requests, so a connection process
  # that serves the MCP address for many requests is left holding none.
  defp take_answer(%Plug.Conn{adapter: {_adapter, %{ref: ref}}} = conn) do
    receive do
      {^ref, {_status, _headers, _body}} -> :ok
    after
      0 -> :ok
    end

    receive do
      {:plug_conn, :sent} -> :ok
    after
      0 -> :ok
    end

    conn
  end

  # Every request to the signer, and every post, neither retries nor follows a
  # redirect. `config :regent_mcp_agents, :req_options` adds options to them,
  # such as a test's stub.
  defp http_request(options) do
    options
    |> Keyword.merge(Application.get_env(:regent_mcp_agents, :req_options, []))
    |> Keyword.merge(retry: false, redirect: false)
    |> Req.request()
  end
end

defmodule RegentMCPAgents do
  @moduledoc """
  A connected app's (ChatGPT's or Claude's) persistent connection to a Regents
  account identity, shared across chats. OAuth authorizes the connection; the
  SIWA service's hosted signing holds its signer, asked with this site's own
  hosted signing key. Every protected product request still passes exact-request
  SIWA verification. Conversation IDs, tool arguments and MCP sessions never
  select the signer.
  """
  alias RegentAgents.{Harness, PairingCode, Person}

  @identity_scope "regent.identity.manage"
  @posting_scope "patchbay.posts.write"

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
               opts[:audience] in ["patchbay", "keyfleet", "ash-template"],
             do:
               raise(
                 ArgumentError,
                 "Hosted identity requires a fixed HTTPS signer, this site's hosted signing key and a known audience"
               )
    end

    :ok
  end

  def enabled?, do: config()[:enabled?] == true

  def identity_scope, do: @identity_scope
  def posting_scope, do: @posting_scope

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

  @doc "Read the current pairing through a freshly SIWA-signed, non-awarding identity probe."
  def status(principal) do
    with :ok <- authority(principal, @identity_scope),
         {:ok, %{"data" => data}} <-
           perform(principal, %{"method" => "GET", "path" => "/api/agents/v1/whoami"}) do
      {:ok,
       %{
         identity_id: connection_key(principal),
         paired: not is_nil(data["pairing"]),
         account_url: RegentOAuth.issuer() <> "/account"
       }}
    end
  end

  @doc "Check in with a freshly SIWA-signed request; the person sees the connection is active."
  def check_in(principal) do
    with :ok <- authority(principal, @identity_scope),
         {:ok, %{"data" => data}} <-
           perform(principal, %{"method" => "GET", "path" => "/api/agents/v1/me"}) do
      {:ok, Map.put(data, "identity_id", connection_key(principal))}
    end
  end

  @doc """
  Redeem only a code made by the authenticated account, using the hosted signer,
  as the connected app it names (`RegentAgents.Harness.connected_apps/0`).
  """
  def pair(principal, %{"code" => code, "name" => name, "harness" => harness} = args)
      when map_size(args) == 3 and is_binary(code) and byte_size(code) in 1..128 and
             is_binary(name) and is_binary(harness) do
    with :ok <- authority(principal, @identity_scope),
         true <- String.length(name) in 1..100,
         true <- harness in Enum.map(Harness.connected_apps(), &Atom.to_string/1),
         :ok <- own_code(principal.subject, code),
         body = Jason.encode!(%{code: code, name: name, harness: harness}),
         {:ok, %{"data" => _data}} <-
           perform(principal, %{
             "method" => "POST",
             "path" => "/api/agents/v1/pair",
             "body" => body
           }) do
      {:ok, %{identity_id: connection_key(principal), paired: true, name: name}}
    else
      _ -> {:error, :pairing_refused}
    end
  end

  def pair(_, _), do: {:error, :pairing_refused}

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

      perform(principal, %{"method" => "POST", "path" => "/chatgpt/agent/mcp", "body" => body})
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
       ), do: :ok, else: {:error, :pairing_refused}
  end

  # The SIWA service takes the audience from this site's hosted signing key and
  # binds every signer to it; the request names no site.
  defp signer_request(principal, payload) do
    signer = Keyword.fetch!(config(), :hosted_signer)

    case Req.request(
           method: :post,
           url: Keyword.fetch!(signer, :base_url) <> "/api/shared/siwa/hosted",
           auth: {:bearer, Keyword.fetch!(signer, :key)},
           json: Map.put(payload, "identity_key", connection_key(principal)),
           retry: false,
           redirect: false,
           receive_timeout: 15_000
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) -> {:ok, body}
      _ -> {:error, :identity_request_refused}
    end
  end

  defp perform(principal, request) do
    required =
      if request["path"] == "/chatgpt/agent/mcp", do: @posting_scope, else: @identity_scope

    with {:ok, envelope} <-
           signer_request(principal, %{"operation" => "sign", "request" => request}),
         :ok <- authority(principal, required),
         true <-
           envelope["method"] == request["method"] and envelope["path"] == request["path"] and
             envelope["body"] == request["body"],
         {:ok, %{status: status, body: body}} <-
           Req.request(
             method: request["method"] |> String.downcase() |> String.to_existing_atom(),
             url: RegentOAuth.issuer() <> request["path"],
             headers: Map.put(envelope["headers"], "content-type", "application/json"),
             body: request["body"],
             retry: false,
             redirect: false,
             receive_timeout: 15_000
           ),
         true <- status in 200..299 and is_map(body) do
      {:ok, body}
    else
      _ -> {:error, :identity_request_refused}
    end
  end
end

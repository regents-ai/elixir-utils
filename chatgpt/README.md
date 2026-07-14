# RegentChatGPT

Shared Elixir primitives for connecting a ChatGPT account to a Regent product.

This package ports the server-side pieces Regent needs from
`opencoredev/login-with-chatgpt`: OAuth/device-code helpers, token refresh,
safe claim parsing, Codex model listing, responses request normalization,
headers, URL construction, stable errors, and redaction.

It does not own product routes, Privy login, cookies, storage, rate limits,
billing policy, or user-facing copy. Host apps decide those things and inject
their HTTP client, secrets, and token store.

## Usage

```elixir
config = RegentChatGPT.Config.resolve()

{:ok, device} = RegentChatGPT.request_device_code(config)

# Show device.user_code and device.verification_url to the user.
{:ok, %{status: :authorized} = poll} = RegentChatGPT.poll_device_code(config, device)
{:ok, tokens} = RegentChatGPT.exchange_device_authorization(config, poll)

{:ok, fresh} = RegentChatGPT.ensure_fresh_tokens(config, tokens)
{:ok, models} = RegentChatGPT.list_models(config, fresh)
```

For a Codex responses proxy, keep tokens in the host app and only build the
upstream request when the signed-in Regent user is allowed to spend from the
connected ChatGPT account:

```elixir
{:ok, request} =
  RegentChatGPT.responses_request(config, fresh, %{
    "model" => "gpt-5.5",
    "input" => [%{"role" => "user", "content" => "Hello"}]
  })
```

`request` is a keyword list suitable for an injected HTTP client. The body is
normalized for the ChatGPT-backed Codex endpoint: stateless responses,
encrypted reasoning carry-forward, no server-side item ids, and no rejected
max-token fields.

## Boundaries

- Privy remains the Regent login. ChatGPT is a connected account.
- Refresh tokens are product secrets. Store and encrypt them in the host app.
- Do not pass raw ChatGPT tokens into hosted runtimes.
- Do not treat arbitrary client-supplied ChatGPT tokens as identity proof.
- Do not use public copy that says Regent login is powered by ChatGPT.

## Test injection

Pass an HTTP function or module in the config:

```elixir
config =
  RegentChatGPT.Config.resolve(
    http_client: fn request ->
      {:ok, %{status: 200, body: %{}}}
    end
  )
```

A module client implements `RegentChatGPT.HTTP.request/1`.

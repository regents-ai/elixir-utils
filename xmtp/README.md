# XmtpElixirSdk

[Hex package](https://hex.pm/packages/xmtp_elixir_sdk)
[Docs](https://hexdocs.pm/xmtp_elixir_sdk)
[Changelog](CHANGELOG.md)

`xmtp_elixir_sdk` is an Elixir-first XMTP SDK for apps that want to work with
clients, conversations, groups, messages, consent state, and sync flows from
Phoenix or general Elixir applications.

The production path is backed by the official Rust XMTP SDK through a supervised
native bridge. The Elixir modules give Phoenix code a normal supervised runtime,
plain structs, and explicit room/conversation functions while the protocol work
stays in the upstream SDK.

![Rust source explainer](readme-assets/rust-port-explainer.png)

## What You Can Do With It

With this SDK you can:

- create and register XMTP clients for server-owned wallets
- reopen existing XMTP clients by address
- open direct messages and groups
- send, count, sync, and read text messages
- inspect conversations, group members, and inbox reachability
- keep Phoenix room behavior behind a small app wrapper

## How The SDK Is Organized

The main modules are:

- `XmtpElixirSdk`: top-level entrypoint and convenience helpers
- `XmtpElixirSdk.Native`: native-backed client, conversation, and message operations
- `XmtpElixirSdk.Clients`: client creation, registration, accounts, recovery, installations
- `XmtpElixirSdk.Conversations`: create and find DMs and groups
- `XmtpElixirSdk.Messages`: send, list, count, publish, and decode messages
- `XmtpElixirSdk.Groups`: group metadata, membership, roles, and permissions
- `XmtpElixirSdk.Preferences`: inbox state, consent, and preference sync
- `XmtpElixirSdk.Sync`: archive and device sync flows

## Installation

Add the dependency to your `mix.exs`:

```elixir
def deps do
  [
    {:xmtp_elixir_sdk, "~> 0.1.1"}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

The package builds its native bridge during `mix compile`. You can also build
the release bridge directly:

```bash
mix native.build
```

## Quick Start

The smallest useful flow is:

1. start a runtime
2. create a server-owned client
3. create a direct message
4. send a message
5. list messages

```elixir
alias XmtpElixirSdk.Native
alias XmtpElixirSdk.Runtime

{:ok, _pid} = XmtpElixirSdk.start_runtime(name: :demo_xmtp)
runtime = Runtime.new(:demo_xmtp)

{:ok, client} =
  Native.create_client(runtime,
    private_key: System.fetch_env!("XMTP_AGENT_PRIVATE_KEY"),
    env: :dev,
    db_path: "priv/xmtp/demo.sqlite3",
    app_version: "my_app/0.1.0"
  )

{:ok, dm} = Native.create_dm(client, "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
{:ok, _message_id} = Native.send_text(dm, "hello from elixir")
{:ok, messages} = Native.list_messages(dm, limit: 25, direction: :descending)
```

## Common Flows

### Create a native client

Use `XmtpElixirSdk.Native.create_client/2` when the server owns the wallet key
for a room, agent, relay, or moderation worker:

```elixir
{:ok, client} =
  XmtpElixirSdk.Native.create_client(runtime,
    private_key: private_key,
    env: :dev,
    db_path: db_path,
    app_version: "my_app/0.1.0"
  )
```

Use `build_existing_client/3` when the identity is already registered and the
server only needs to reopen it:

```elixir
{:ok, client} =
  XmtpElixirSdk.Native.build_existing_client(runtime, address,
    env: :dev,
    db_path: db_path
  )
```

### Open a direct message

```elixir
{:ok, dm} = XmtpElixirSdk.Native.create_dm(client, peer_address)
```

### Create a group

```elixir
{:ok, group} =
  XmtpElixirSdk.Native.create_group(client, [bob_address, carol_address],
    name: "Product Team",
    description: "Product room"
  )
```

You can pass group options if you want to set a name, description, image, or app
data at creation time.

### Send and read messages

```elixir
{:ok, _message_id} = XmtpElixirSdk.Native.send_text(group, "hello group")
{:ok, listed} = XmtpElixirSdk.Native.list_messages(group, limit: 50)
{:ok, count} = XmtpElixirSdk.Native.count_messages(group)
```

### Inspect a group

```elixir
{:ok, members} = XmtpElixirSdk.Native.members(group)
{:ok, synced} = XmtpElixirSdk.Native.sync_conversation(group)
```

### Check reachability

```elixir
{:ok, result} = XmtpElixirSdk.Native.can_message(client, [peer_address])
{:ok, inbox_id} = XmtpElixirSdk.Native.inbox_id_for(client, peer_address)
```

### List and sync conversations

```elixir
{:ok, _result} = XmtpElixirSdk.Native.sync_all(client)
{:ok, conversations} = XmtpElixirSdk.Native.list_conversations(client, conversation_type: :group)
```

## Browser Wallet Signing

Browser wallet integration belongs at the app layer. For user-owned wallets,
keep the wallet approval in the browser and call your Phoenix wrapper after the
person approves the action. For server-owned wallets, use `XmtpElixirSdk.Native`
from supervised server code.

## Browser Shim

The `browser_shim/` directory is for browser-only work, such as worker-style
actions and browser-managed storage requests. It is not bundled into the Hex
package as a runtime dependency.

If your app runs fully on the server, you can usually ignore it.

## Phoenix Rooms

Phoenix apps should keep room mechanics behind an app wrapper and render from
the room panel the wrapper returns. See
[`docs/phoenix-frontend-agent-guide.md`](docs/phoenix-frontend-agent-guide.md)
for the frontend agent rules.

## Environment Helpers

The SDK includes helpers for XMTP environment URLs:

- `XmtpElixirSdk.api_urls/0`
- `XmtpElixirSdk.history_sync_urls/0`
- `XmtpElixirSdk.Types.env_url/1`

## Publishing

Build the package locally with:

```bash
mix hex.build
```

Generate docs with:

```bash
mix docs
```

Publish the package with:

```bash
mix hex.publish
```

Publish docs with:

```bash
mix hex.publish docs
```

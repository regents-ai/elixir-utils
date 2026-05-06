# XmtpElixirSdk

[Hex package](https://hex.pm/packages/xmtp_elixir_sdk)
[Docs](https://hexdocs.pm/xmtp_elixir_sdk)
[Changelog](CHANGELOG.md)

`xmtp_elixir_sdk` is Regent’s Elixir package for XMTP clients, messages, group
rooms, identity setup, room sync, and Phoenix room panels.

The low-level protocol work is handled by the official Rust XMTP SDK through a
supervised native bridge. The Elixir package gives Phoenix and worker code a
normal OTP surface: supervised runtimes, explicit client functions, typed
message structs, resolver caches, and product-safe room actions.

![Rust source explainer](readme-assets/rust-port-explainer.png)

## Installation

```elixir
def deps do
  [
    {:xmtp_elixir_sdk, "~> 0.1.2"}
  ]
end
```

Then fetch and compile:

```bash
mix deps.get
mix compile
```

The package compiles a native bridge. Install a working Rust toolchain before
building the package in development or release environments.

Build the release bridge directly with:

```bash
mix native.build
```

## When To Use It

Use this package when an Elixir app needs to:

- create or reopen XMTP clients
- register a server-owned XMTP identity
- guide a human or agent through chat identity setup
- resolve wallets to XMTP inbox ids
- create direct messages or groups
- send, list, count, decode, and sync messages
- inspect group members and permissions
- manage consent and preferences
- create Phoenix room panels for product-owned rooms
- mirror room messages into a product database
- encode Regent profile and room metadata

Use product app code for:

- deciding who may create, join, invite, remove, moderate, or archive a room
- storing product room rows and message logs
- deciding which rooms are public
- showing customer-facing room copy
- browser wallet connection and approval UI
- paid access, launch state, research state, and company ownership rules

## Package Layers

There are two useful layers.

### Low-Level SDK

Use `XmtpElixirSdk.*` modules when you need direct XMTP client behavior:

- `XmtpElixirSdk.Native` creates clients, DMs, groups, messages, and sync calls.
- `XmtpElixirSdk.Clients` handles client registration, inbox state, recovery, and installations.
- `XmtpElixirSdk.Conversations` works with conversations.
- `XmtpElixirSdk.Groups` manages group metadata, roles, and permissions.
- `XmtpElixirSdk.Messages` sends, lists, publishes, and decodes messages.
- `XmtpElixirSdk.Preferences` handles consent and preference sync.
- `XmtpElixirSdk.Sync` handles archive and device sync flows.
- `XmtpElixirSdk.BrowserShim` builds browser-worker requests for browser-owned storage.

### Regent Room Layer

Use `Xmtp.*` modules when a Phoenix product app wants rooms:

- `Xmtp.Identity` hides XMTP registration and wallet signature request setup.
- `Xmtp.Resolver` resolves wallets and inbox ids with shared normalization and bounded caches.
- `Xmtp.Installations` reports device status in product-safe terms.
- `Xmtp.RoomDefinition` describes a product-owned room.
- `Xmtp.Rooms` is the action boundary for panels, joining, posting, inviting, kicking, deleting, and heartbeats.
- `Xmtp.RoomPanel` is the display contract Phoenix code should render.
- `Xmtp.Metadata.Profile` encodes silent profile updates.
- `Xmtp.Metadata.GroupAppData` encodes Regent group app data.
- `Xmtp.Sync` helps with idempotent room logs and message ordering.

## Start A Runtime

For direct SDK use, start a runtime under your app supervisor:

```elixir
children = [
  {XmtpElixirSdk.Runtime, name: MyApp.XmtpRuntime}
]
```

Or start one manually in scripts/tests:

```elixir
{:ok, _pid} = XmtpElixirSdk.Runtime.start_link(name: :demo_xmtp)
runtime = XmtpElixirSdk.Runtime.new(:demo_xmtp)
```

## Create A Server-Owned Client

Use server-owned clients for agents, room service wallets, moderation workers,
or relay jobs.

```elixir
{:ok, client} =
  XmtpElixirSdk.Native.create_client(runtime,
    private_key: System.fetch_env!("XMTP_AGENT_PRIVATE_KEY"),
    env: :dev,
    db_path: "priv/xmtp/agent.sqlite3",
    app_version: "my_app/0.1.0"
  )
```

Use `env: :production` for production XMTP network access.

Reopen an existing registered client:

```elixir
{:ok, client} =
  XmtpElixirSdk.Native.build_existing_client(runtime, wallet_address,
    env: :production,
    db_path: "priv/xmtp/agent.sqlite3"
  )
```

## Send And Read Messages

Create a direct message:

```elixir
{:ok, dm} =
  XmtpElixirSdk.Native.create_dm(client, "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")

{:ok, message_id} =
  XmtpElixirSdk.Native.send_text(dm, "hello from elixir")

{:ok, messages} =
  XmtpElixirSdk.Native.list_messages(dm, limit: 25, direction: :descending)
```

Create a group:

```elixir
{:ok, group} =
  XmtpElixirSdk.Native.create_group(client, [bob_address, carol_address],
    name: "Launch Room",
    description: "Launch coordination"
  )

{:ok, members} = XmtpElixirSdk.Native.members(group)
{:ok, _synced} = XmtpElixirSdk.Native.sync_conversation(group)
```

Check whether a wallet can receive XMTP messages:

```elixir
{:ok, result} = XmtpElixirSdk.Native.can_message(client, [peer_address])
{:ok, inbox_id} = XmtpElixirSdk.Native.inbox_id_for(client, peer_address)
```

## Connect A Product Chat Identity

Use `Xmtp.Identity` when a human or agent account needs a chat identity.

The product owns the account row and stores the returned `inbox_id`. The package
creates the signature request and completes XMTP registration.

```elixir
principal = %{
  kind: :human,
  id: human.id,
  wallet_address: human.wallet_address,
  inbox_id: human.xmtp_inbox_id
}

{:ok, state} =
  Xmtp.Identity.ensure_identity(%{
    runtime: MyApp.XmtpRuntime,
    principal: principal,
    stored_inbox_id: human.xmtp_inbox_id
  })
```

When `state.status` is `:ready`, store or keep `state.inbox_id`.

When `state.status` is `:needs_wallet_signature`, ask the connected wallet to
sign `state.signature_request.text`. Then complete registration:

```elixir
{:ok, ready} =
  Xmtp.Identity.complete_signature(%{
    runtime: MyApp.XmtpRuntime,
    wallet_address: state.wallet_address,
    client_id: state.signature_request.client_id,
    request_id: state.signature_request.id,
    signature: wallet_signature
  })
```

Store `ready.inbox_id` on the product account.

## Resolve A Room Invite Target

Start the resolver under supervision:

```elixir
children = [
  {Xmtp.Resolver, name: MyApp.XmtpResolver}
]
```

Resolve by wallet before inviting a person to a room:

```elixir
{:ok, target} =
  Xmtp.Resolver.resolve_for_room_invite(
    MyApp.XmtpResolver,
    client,
    %{wallet_address: "0xabc0000000000000000000000000000000000001"}
  )
```

The result status is one of:

- `:ready`
- `:not_found`
- `:cannot_message`

Use the same resolver across the app so address normalization, missing inboxes,
and null-result caching work one way.

## Add Phoenix Rooms

Start one room manager per Phoenix app:

```elixir
children = [
  Xmtp.child_spec(
    name: MyApp.Xmtp.Manager,
    repo: MyApp.Repo,
    pubsub: MyApp.PubSub,
    rooms: {:mfa, MyApp.XmtpRooms, :rooms, []}
  )
]
```

Provide room definitions from product state:

```elixir
def rooms do
  [
    Xmtp.RoomDefinition.new!(%{
      key: "platform:company:acme",
      name: "Acme Company Room",
      description: "Company updates and coordination",
      app_data: "platform:company:acme",
      agent_private_key: System.fetch_env!("XMTP_ROOM_PRIVATE_KEY"),
      moderator_wallets: ["0x1111111111111111111111111111111111111111"],
      capacity: 200,
      presence_timeout_ms: :timer.minutes(2),
      presence_check_interval_ms: :timer.seconds(30),
      policy_options: %{allowed_kinds: [:human, :agent]}
    })
  ]
end
```

Render a room panel:

```elixir
{:ok, panel} =
  Xmtp.Rooms.panel(MyApp.Xmtp.Manager, "platform:company:acme", principal)
```

Send user actions through `Xmtp.Rooms`:

```elixir
{:ok, panel} =
  Xmtp.Rooms.send_message(
    MyApp.Xmtp.Manager,
    "platform:company:acme",
    principal,
    "Shipping the next update."
  )
```

The room panel is the Phoenix display contract. UI code should render from the
panel and send actions back through the room boundary.

## Room Panel Fields

`%Xmtp.RoomPanel{}` includes:

- `room_key`
- `xmtp_group_id`
- `name`
- `status`
- `membership`
- `connected_wallet`
- `can_join`
- `can_send`
- `can_moderate`
- `pending_signature_request_id`
- `member_count`
- `active_member_count`
- `capacity`
- `seats_remaining`
- `presence_ttl_seconds`
- `last_synced_at`
- `user_copy`
- `messages`

Keep product rooms keyed by a product-owned `room_key`, such as
`platform:company:<slug>`, `autolaunch:subject:<id>`, or
`techtree:node:<id>`. Do not treat the XMTP group id as the product room id.

## Metadata

Encode silent Regent profile messages:

```elixir
{:ok, message} =
  Xmtp.Metadata.Profile.silent_message(%{
    product: :platform,
    principal_type: :human,
    principal_id: "human_123",
    display_name: "Alice",
    avatar_url: "https://example.com/alice.png",
    wallet_address: "0x1111111111111111111111111111111111111111"
  })
```

Encode room app data:

```elixir
{:ok, app_data} =
  Xmtp.Metadata.GroupAppData.encode(%{
    product: "techtree",
    room_key: "techtree:node:node_123",
    room_profile: %{title: "Research discussion"}
  })
```

## Sync And Storage

Use `Xmtp.Sync` when a Phoenix app mirrors messages into its own database:

```elixir
key = Xmtp.Sync.idempotency_key(message)
order_key = Xmtp.Sync.message_order_key(message)
```

The host app should enforce idempotent inserts, stable ordering, and product
visibility rules in its own database. XMTP message existence alone does not mean
a message should appear publicly.

If a Phoenix app uses the provided room mirror storage, copy the versioned
migration template from `priv/templates/xmtp_room_mirror_v1_migration.exs` into
that app and keep product-specific policy in that app.

## Browser Wallets And Browser Storage

Browser wallet connection belongs in the host app. Keep wallet approval in the
browser, then send the signed result back to your Phoenix code.

The `browser_shim/` directory contains narrow browser-worker helpers for
browser-owned storage. Server-only apps can ignore it.

## Product Boundaries

- Platform owns company room policy and public company-page behavior.
- Autolaunch owns launch and subject room policy.
- Techtree owns public, review, research, and node room policy.
- This package owns reusable XMTP mechanics and room contracts.

## Development

```bash
mix deps.get
mix test
mix docs
```

The broader package check also builds the native bridge and browser shim tests:

```bash
mix check
```

## Phoenix Frontend Guide

Read [`docs/phoenix-frontend-agent-guide.md`](docs/phoenix-frontend-agent-guide.md)
before changing Phoenix room UI code.

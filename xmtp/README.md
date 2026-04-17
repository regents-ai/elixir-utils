# XmtpElixirSdk

[Hex package](https://hex.pm/packages/xmtp_elixir_sdk/0.1.0)
[Docs](https://hexdocs.pm/xmtp_elixir_sdk/0.1.0)
[Changelog](CHANGELOG.md)

`xmtp_elixir_sdk` is an Elixir-first XMTP SDK for apps that want to work with
clients, conversations, groups, messages, consent state, and sync flows without
having to build that surface from scratch.

This package ports the public XMTP SDK ideas into an Elixir-friendly shape. It
aims to feel natural in Phoenix and general Elixir applications while keeping
the core XMTP concepts recognizable.

![Rust source explainer](readme-assets/rust-port-explainer.png)

## What You Can Do With It

With this SDK you can:

- create and register XMTP clients
- open direct messages and groups
- send and read text and structured messages
- manage group members, admins, and permissions
- inspect inbox state and consent state
- export and import sync archives
- integrate browser-only storage or worker flows through the browser shim

## How The SDK Is Organized

The main modules are:

- `XmtpElixirSdk`: top-level entrypoint and convenience helpers
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
    {:xmtp_elixir_sdk, "~> 0.1.0"}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

## Quick Start

The smallest useful flow is:

1. start a runtime
2. create two clients
3. create a direct message
4. send a message
5. list messages

```elixir
alias XmtpElixirSdk.Conversations
alias XmtpElixirSdk.Messages
alias XmtpElixirSdk.Runtime
alias XmtpElixirSdk.Types

{:ok, _pid} = XmtpElixirSdk.start_runtime(name: :demo_xmtp)
runtime = Runtime.new(:demo_xmtp)

alice_identifier = %Types.Identifier{
  identifier: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  identifier_kind: :ethereum
}

bob_identifier = %Types.Identifier{
  identifier: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  identifier_kind: :ethereum
}

{:ok, alice} = XmtpElixirSdk.create_client(runtime, alice_identifier, env: :dev)
{:ok, _bob} = XmtpElixirSdk.create_client(runtime, bob_identifier, env: :dev)

{:ok, dm} = Conversations.create_dm_with_identifier(alice, bob_identifier)
{:ok, _message_id} = Messages.send_text(dm, "hello from elixir")
{:ok, messages} = Messages.list(dm)
```

## Common Flows

### Create a client

Use `create_client/3` when you want a registered client immediately:

```elixir
{:ok, client} = XmtpElixirSdk.create_client(runtime, identifier, env: :dev)
```

Use `build_client/3` when you want to create the client first and register it
later:

```elixir
{:ok, built} = XmtpElixirSdk.build_client(runtime, identifier, env: :dev)
{:ok, client} = XmtpElixirSdk.Clients.register(built)
```

### Open a direct message

```elixir
{:ok, dm} = Conversations.create_dm_with_identifier(client, peer_identifier)
```

### Create a group

```elixir
{:ok, group} =
  Conversations.create_group_with_identifiers(client, [bob_identifier, carol_identifier])
```

You can pass group options if you want to set a name, description, image, app
data, or custom permissions at creation time.

### Send and read messages

```elixir
{:ok, _message_id} = Messages.send_text(group, "hello group")
{:ok, listed} = Messages.list(group)
{:ok, count} = Messages.count(group)
```

The messages module also supports markdown, replies, reactions, read receipts,
attachments, actions, intents, transaction references, and wallet-send calls.

### Manage a group

```elixir
alias XmtpElixirSdk.Groups

{:ok, renamed} = Groups.update_name(group, "Product Team")
{:ok, updated} = Groups.add_members(group, ["some-inbox-id"])
{:ok, admins} = Groups.list_admins(group)
```

### Read inbox state and consent

```elixir
alias XmtpElixirSdk.Preferences

{:ok, inbox_state} = Preferences.inbox_state(client)
{:ok, :ok} = Preferences.set_consent_states(client, [%{entity: client.inbox_id, state: :allowed}])
{:ok, state} = Preferences.get_consent_state(client, :inbox_id, client.inbox_id)
```

Inbox consent uses `%{entity: "...", state: ...}`. Group consent uses
`%{group_id: "...", state: ...}`.

### Work with archives and device sync

```elixir
alias XmtpElixirSdk.Sync

key = <<1, 2, 3>>
{:ok, archive} = Sync.create_archive(client, key)
{:ok, metadata} = Sync.archive_metadata(client, archive, key)
{:ok, :ok} = Sync.import_archive(client, archive, key)
```

## Browser Wallet Signing

Browser wallet integration belongs at the app layer.

The SDK stays neutral about which wallet you use. The usual pattern is:

1. create or build the client you want to act as
2. ask the SDK for the signature request text
3. have the wallet sign that exact text
4. send the signature result back to your app
5. apply the signature request through the SDK

That lets Phoenix and other Elixir apps use browser wallets without pushing
wallet-specific code into the core package.

## Browser Shim

The `browser_shim/` directory is for browser-only work, such as worker-style
actions and browser-managed storage requests. It is not bundled into the Hex
package as a runtime dependency.

If your app runs fully on the server, you can usually ignore it.

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

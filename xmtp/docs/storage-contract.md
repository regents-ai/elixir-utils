# XMTP Room Mirror Storage Contract

This package includes reusable room, membership, and message mirror schemas for
Phoenix room wrappers. The host app owns the actual database tables.

## Contract Version

Current contract: `xmtp_room_mirror_v1`

The matching migration template is:

```text
priv/templates/xmtp_room_mirror_v1_migration.exs
```

Copy that file into the host app's own migration folder, rename the module, and
run it from the host app. This package does not run migrations for the host app.

## Ownership Rules

- Host apps own the database, migrations, backups, retention policy, and deletes.
- Host apps own product room meaning, membership rules, moderation rules, and who
  can publish or read a room.
- This package owns only the shared mirror shape used by `Xmtp.RoomServer`.
- XMTP message history is not product workflow truth.
- Product-specific fields belong in product-owned tables that reference
  `room_key`, `conversation_id`, or the host app's room row.

## Tables

`xmtp_rooms` stores the room mirror row. `room_key` is the host app's stable
product key, and `conversation_id` is the XMTP conversation ID.

`xmtp_room_memberships` stores mirrored wallet and inbox membership rows. It is
not entitlement truth.

`xmtp_message_logs` stores the visible public message mirror used by the room
panel. Only use it for product-approved rooms where storing visible message body
text is intended by the host app.

## Product Data

Do not add product workflow fields to this shared template. For example:

- Techtree publish, review, or paid payload state belongs in Techtree tables.
- Autolaunch launch, auction, subject, or trust follow-up state belongs in
  Autolaunch tables.
- Platform company room display choices belong in Platform tables.

If a product needs extra room data, create a product-owned table and link it to
the mirror by the stable room key or XMTP conversation ID.

# Phoenix Frontend Agent Guide For XMTP Rooms

Use this guide when adding or changing Phoenix frontend code that talks to Regent XMTP rooms after the XMTP package is native-backed. The room behavior should match Platform's current public company room flow.

The frontend should treat the host app's XMTP wrapper as the room boundary. Phoenix code asks for a `%Xmtp.RoomPanel{}`, renders that panel, sends user actions back through `Xmtp.Rooms`, and refreshes the panel when the room broadcasts a change. Phoenix code should not build XMTP clients, mutate group membership, or write room logs itself.

## Current Room Shape To Preserve

Platform rooms behave like this:

- The host app owns the room list, policy, database module, and PubSub module it passes into the wrapper.
- The XMTP package keeps the local transport records it needs for the room panel and message flow.
- Each room has a stable room key, name, description, app data, capacity, moderator wallets, and join policy.
- Room processes start on demand when a caller asks for a panel, join, message send, moderation action, or bootstrap.
- Each room has a service wallet that owns the XMTP group.
- Company owners moderate company rooms through their linked wallet addresses.
- People can read the room before joining.
- People can post only after joining.
- Joining may require one wallet approval. The server creates the exact text to sign and applies the returned signature.
- Room updates broadcast `{:xmtp_public_room, :refresh}` on the room topic.
- LiveViews reload the room panel after refresh broadcasts.
- Message lists hide membership-change noise and show the latest public messages.
- Moderators can remove messages and remove people from the room.
- Presence is heartbeat-based. Stale joined memberships can be removed after the room timeout.

## Supervision Setup

Add one application-level wrapper per Phoenix app, then supervise that wrapper from the app supervisor.

The wrapper should call the package child spec with:

```elixir
Xmtp.child_spec(
  name: MyApp.Xmtp.Manager,
  repo: MyApp.Repo,
  pubsub: MyApp.PubSub,
  rooms: {:mfa, MyApp.Xmtp, :rooms, []}
)
```

Use an MFA room loader when rooms come from app state, as Platform does for company rooms. That lets the room manager refresh a room definition when a LiveView action arrives.

Each room definition should include:

- `key`: stable product room key, for example `"company:acme"`.
- `name`: display name for the room.
- `description`: short room purpose.
- `app_data`: product-scoped identifier for the room.
- `agent_private_key`: the service wallet key supplied by the host app.
- `moderator_wallets`: wallet addresses allowed to moderate.
- `capacity`: human member limit.
- `presence_timeout_ms`: how long a person remains active without a heartbeat.
- `presence_check_interval_ms`: how often stale presence is checked.
- `policy_options`: allowed principal kinds and required claims.

Keep app wrappers small. A good wrapper normalizes app records into principals, computes room keys, exposes room actions, and leaves transport mechanics to the XMTP package.

## Starting And Subscribing To Rooms

Load the room panel during mount or page state assignment:

```elixir
case MyApp.Xmtp.company_room_panel(current_human, agent, %{}) do
  {:ok, panel} -> assign(socket, :xmtp_room, panel)
  {:error, _reason} -> assign(socket, :xmtp_room, nil)
end
```

Subscribe only after the LiveView connects:

```elixir
if Phoenix.LiveView.connected?(socket) do
  :ok = MyApp.Xmtp.subscribe(MyApp.Xmtp.company_room_key(agent))
end
```

Handle refresh broadcasts by reloading the product page state or the room panel:

```elixir
def handle_info({:xmtp_public_room, :refresh}, socket) do
  {:noreply, reload_company_page(socket)}
end
```

Do not keep a copied room model in the LiveView. The room panel is the current display contract for Phoenix code.

## Room Panel Fields

Render from the panel instead of making fresh membership decisions in components.

The panel includes:

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

Message entries include the fields the UI needs: key, author, body, time label, side, sender details, visibility state, and moderation permissions.

## Request Join And Wallet Approval Flow

The join button should call the app wrapper:

```elixir
case MyApp.Xmtp.request_join(current_human, room_key, %{}) do
  {:ok, panel} ->
    assign(socket, :xmtp_room, panel)

  {:needs_signature, %{request_id: request_id, signature_text: signature_text, panel: panel}} ->
    socket
    |> assign(:xmtp_room, panel)
    |> Phoenix.LiveView.push_event("xmtp:sign-request", %{
      request_id: request_id,
      signature_text: signature_text,
      wallet_address: panel.connected_wallet
    })

  {:error, reason} ->
    put_room_status(socket, reason_message(reason))
end
```

The browser hook should ask the connected wallet to sign the exact text from `signature_text`. It should then push:

```elixir
%{
  "request_id" => request_id,
  "signature" => signature
}
```

The LiveView should complete the join through the wrapper:

```elixir
case MyApp.Xmtp.complete_join_signature(current_human, request_id, signature, room_key, %{}) do
  {:ok, panel} -> assign(socket, :xmtp_room, panel)
  {:error, reason} -> put_room_status(socket, reason_message(reason))
end
```

Keep the request ID paired with the room panel. Do not trust a browser-supplied wallet address to decide membership. The server should use the current signed-in principal and the pending request stored by the room process.

## Sending Messages

Post messages through the room boundary:

```elixir
case MyApp.Xmtp.send_message(current_human, body, room_key) do
  {:ok, panel} ->
    socket
    |> assign(:xmtp_room, panel)
    |> clear_message_form()

  {:error, reason} ->
    socket
    |> keep_message_form(body)
    |> put_room_status(reason_message(reason))
end
```

The room boundary trims the body, requires joined membership, enforces the message length, sends the XMTP text message, logs it, touches presence, and returns a fresh panel.

Frontend code should:

- Keep the typed message when sending fails.
- Clear the form only after a successful send.
- Disable the composer when `can_send` is false.
- Use the panel's message list after each success or refresh.

## Presence And Heartbeats

Send a heartbeat from the room hook while the room is visible:

```elixir
pushEvent("xmtp_heartbeat", {})
```

The LiveView should call:

```elixir
:ok = MyApp.Xmtp.heartbeat(current_human, room_key)
```

Heartbeat failures should not show a blocking error. The next room refresh or user action will reload the panel. Only show errors for actions the person asked to take, such as joining or posting.

## UI Copy Rules

Room UI copy must explain what the person can do next. Do not expose room internals.

Use copy like:

- "Sign in with your wallet to join the room."
- "Check your wallet to finish joining."
- "You are in the room."
- "Write a message before you send it."
- "Keep the message shorter so the room stays readable."
- "All seats are filled right now. You can still read along from this page."
- "That join request expired. Start again when you are ready."
- "This room is unavailable right now."

Do not show copy like:

- "Sign the XMTP payload."
- "Signature request ID missing."
- "LiveView hook failed."
- "PubSub refresh failed."
- "Client registration failed."
- "Conversation import failed."

Labels should say what the person sees or can do:

- "Join room"
- "Post a message"
- "Send"
- "Remove"
- "Remove person"
- "Room activity"
- "Room status"

Keep the word "XMTP" out of public room copy unless the page is developer documentation.

## Error Handling

Map room errors to plain room status text:

```elixir
def reason_message(:wallet_required), do: "Sign in with your wallet before you join this room."
def reason_message(:room_full), do: "All seats are filled right now. You can still read along from this page."
def reason_message(:message_required), do: "Write a message before you send it."
def reason_message(:message_too_long), do: "Keep the message shorter so the room stays readable."
def reason_message(:kicked), do: "This wallet was removed from the room."
def reason_message(:join_required), do: "Join the room before you post."
def reason_message(:moderator_required), do: "Only the room owner can do that here."
def reason_message(:member_not_found), do: "That person is no longer in the room."
def reason_message(:message_not_found), do: "That message is no longer available."
def reason_message(:signature_request_missing), do: "That join request expired. Start again when you are ready."
def reason_message(_reason), do: "This room is unavailable right now."
```

Treat unknown errors as temporary room unavailability in the UI. Log details outside the public component when the host app needs diagnostics.

## Moderation

Use the panel permissions:

- Show message removal only when `message.can_delete?` is true.
- Show person removal only when `message.can_kick?` is true.
- Call the wrapper for moderation actions.
- Reload the panel from the returned result.
- Show the mapped room status when moderation fails.

Do not infer moderator status from page ownership in the component. The panel already carries `can_moderate` and per-message permissions.

## What Not To Do

- Do not build XMTP clients in LiveViews, components, or browser hooks.
- Do not call native-backed SDK modules directly from Phoenix UI code when a room wrapper exists.
- Do not write room rows, memberships, or message logs from frontend code.
- Do not duplicate membership, capacity, moderator, or policy checks in components.
- Do not accept a browser-supplied wallet address as proof of membership.
- Do not send a message before the room says `can_send`.
- Do not clear a message draft after a failed send.
- Do not show internal error names, request IDs, wallet signing details, or package names in public copy.
- Do not add alternate room shapes, compatibility branches, aliases, adapters, or old-field handling.
- Do not special-case old room keys or old event names.
- Do not add rejection tests for old room shapes. Update callers and fixtures to the current room panel shape.

## Acceptance Checks For Phoenix Changes

Run checks that cover the real room flow:

- The page renders for a signed-out visitor and shows read-only room copy.
- A signed-in wallet can request to join.
- The wallet approval event receives the exact signing text and request ID from the room response.
- A completed wallet approval updates the panel to joined.
- A joined person can post a message.
- An empty message keeps the draft and shows a plain error.
- An overlong message keeps the draft and shows a plain error.
- A non-member cannot post.
- A full room closes joining but keeps the room readable.
- A moderator can remove a message.
- A moderator can remove a person.
- A non-moderator cannot see moderation actions.
- A room refresh broadcast reloads the visible room panel.
- Public copy avoids XMTP, request IDs, hook names, PubSub, client registration, and other implementation details.

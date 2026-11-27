# 048 Order detail window with chat and history: spec

- Status: done
- Created: 2026-11-27
- Target version: next minor (protocol 2.9, schema unchanged)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
One window per order with three tabs: an overview of the whole order, a chat shared with the guild, and the history of
every status change with its date.

## Requirements
- R1: A chat icon in each order row's action column opens the order window; the icon shows the number of unread
  messages.
- R2: Overview tab: recipe (icon, name), quantity, status, requester, crafters who claimed it, created date, note,
  reagents for the ordered quantity with how many I have, tools the recipe needs (when known), guild members who know
  the recipe.
- R3: Chat tab: one row per message (time, author, text), oldest at the top, an input line with Send at the bottom
  (Enter sends). Every guild member with the addon reads and writes every order's chat.
- R4: History tab: one row per status change with date and time: created, claimed, withdrawn, done, cancelled, with
  who did it. Changes made by older addon versions still show (taken from the order's own fields).
- R5: Chat messages and history events sync to every guild member with protocol 2.9, live and after login; members
  with 2.8 or older keep syncing orders as before (they just do not see chat or the extra history).
- R6: A new message from someone else on an order I requested or claimed is order news: badge on the minimap button,
  sound and chat line with the existing notification switches. Opening that order's chat marks it read.
- R7: Peer text is safe: chat text UTF-8, at most 160 bytes, no control characters, escaped on display; an author
  can only send live messages in their own name; per order at most 30 messages and 30 events (the newest are kept).

## Non-goals
- No private chat (addon messages go to the whole guild channel anyway).
- No editing or deleting chat messages.
- No chat relay beyond the order's lifetime: a pruned order takes its chat with it.

## Design
- `Core/Data/Orders.lua` (changed): optional order fields `msgs = { {b, t, x} }` and `ev = { {k, b, t} }`
  (k = claim|withdraw|done|cancel). Sanitize (allow-list, bounds), Merge = union by `b..t` (`k..b..t` for events), keep
  the newest 30, sorted by time. `Orders:AddMessage(orderID, author, text)`; Claim/Withdraw/Close record an event.
  `Orders.ExtraVersion(order)` = sum of the times of messages and events. `Orders.Version` stays as it is (2.8 peers
  compute the same number).
- `Core/Net/Sync.lua` (changed): HELLO field `xdig = { [orderID] = ExtraVersion }` (same newest 100 orders as `odig`,
  only orders with chat or events); `Missing` also returns orders whose extra part the peer lacks (only when the peer
  sent `xdig`). OPUSH batches are cut by size (estimated bytes) as well as by count. New message `OMSG {id, m}` on
  GUILD: one chat message; `m.b` must equal the sender; unknown order -> ignored (it comes with OPUSH). ORDER
  broadcasts carry `ev` but not `msgs`.
- `Core/Base/Init.lua`: PROTOCOL_MINOR 9.
- `Core/Data/Store.lua`, `Core/Game/Api.lua`: catalog entries get optional `tools` (<= 4 names, <= 60 bytes, no `|`),
  read from `GetTradeSkillTools` when the client has it.
- `Core/View/Model.lua`: `OrderHistory(orderBoard, order)` (events from `ev` plus the ones derived from createdAt,
  claims, closedAt, deduplicated), `OrderChatRows(order)`, `OrderOverview(store, orderBoard, order, myName, owned)`.
- `Core/View/Notify.lua`: `UnseenChat(orderBoard, myName, chatSeen)` -> unseen items of kind "chat";
  `MarkChatSeen(chatSeen, order)`; `ChatUnread(order, myName, chatSeen)` for the row badge.
- `UI/OrderWindow.lua` (new, after Window in the TOC): the window with the three tabs.
- `UI/Window.lua`: row action "chat" with the unread count; `UI/Alerts.lua`: chat items in the unseen list.
- Data: `db.ui.chatSeen[orderID] = time of the newest message seen` (local, pruned with the orders).

## Tasks
- [x] T1 (M): Orders: msgs/ev fields, sanitize, merge, AddMessage, events on actions, ExtraVersion, Missing with xdig;
  tests in `tests/test_order_chat.lua`.
- [x] T2 (M): Sync: OMSG, xdig, ORDER without msgs, OPUSH size batches, protocol 2.9; tests.
- [x] T3 (S): catalog `tools` + scan; tests.
- [x] T4 (S): Model history, chat rows, overview; tests.
- [x] T5 (S): Notify chat unread + Alerts; tests.
- [x] T6 (M): UI/OrderWindow.lua + row icon; `test_load` opens the window and sends a message.
- [x] T7 (S): locale, docs (README, CHANGELOG, protocol.md section 18, status), verify.

## Review Focus (failure modes a happy-path test would miss)
1. RF1: A 2.8 peer's digest never matches the extra part: no endless OPUSH to 2.8 peers. Pinned by: T2.
2. RF2: Forged author: an OMSG whose `m.b` is not the sender is dropped. Pinned by: T2.
3. RF3: 31st message: the oldest drops, the merge result is the same on every client whatever the arrival order. Pinned by: T1.
4. RF4: OPUSH of 10 orders with full chats stays under the message size limit. Pinned by: T2.
5. RF5: Garbage `msgs`/`ev` (wrong types, control characters, future times) never rejects the whole order: the bad
  entries are dropped, the order still merges. Pinned by: T1.

## Cross-cutting checklist (answer every line; "n/a: reason" is fine)
- [x] Protocol: minor 2.9 (additive: optional order fields, HELLO `xdig`, message `OMSG`, catalog `tools`).
- [x] Stored data: schema unchanged; new optional fields re-validated on load; older builds drop them (allow-list).
- [x] Trust model: guild members trusted; live messages only in the sender's own name; relayed (OPUSH) messages are
  trusted like claims; all text escaped on display.
- [x] Localization: labels through `Text`; chat text is user text, shown escaped.
- [x] Load order: `UI/OrderWindow.lua` after `UI/Window.lua`.
- [x] Packaging: new file is in the TOC; nothing else.
- [x] Tests: `tests/test_order_chat.lua`, `test_load`.
- [x] Docs: README, CHANGELOG, docs/protocol.md, docs/status.md, doc.md.

## Decisions (user answers and design choices, newest last)
- 2026-11-27: Everyone reads and writes every order's chat (user).
- 2026-11-27: New chat messages on my orders (requested or claimed) notify like order news (user).
- 2026-11-27: The window opens from a chat icon in the row's action column (user).
- 2026-11-27: PROTOCOL 2.9 minor, additive; `Orders.Version` unchanged so 2.8 peers see equal digests; chat and events
  ride in the order record and get their own digest `xdig` (design).
- 2026-11-27: Schema stays 9: the new fields are optional parts of `orders` entries (design).

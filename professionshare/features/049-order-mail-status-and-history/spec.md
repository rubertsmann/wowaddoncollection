# 049 Order mail status and history: spec

- Status: done
- Created: 2026-11-27
- Target version: 1.7.0 (protocol 2.10, schema unchanged)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
Mails sent through the addon's mail queue update the order by themselves: a "Mailed" status when the crafted item is
on its way, and a history row per mail (items and amounts) for the item and the reagent mails.

## Requirements
- R1: A mail the addon sees go out (`MAIL_SEND_SUCCESS` for a queued job, recipient unchanged) records a mail entry on
  the job's order: kind (item | reagents), sender, recipient, time, items and amounts sent, and whether the job is
  complete (nothing left to send).
- R2: "Done" on a queued mail in the mailbox panel records the same entry marked "by hand" (with what was attached,
  if anything).
- R3: In the order window the active crafter can mark the item as mailed / handed over, and the requester the
  reagents, by hand (complete, no items).
- R4: Status: an order that is not closed and has a complete item mail entry has the new status "Mailed" (between
  claimed and done). It stays live: done, withdraw and cancel work as for claimed orders. The requester still closes it.
- R5: History tab: one row per mail entry, "partly" when not complete, "(by hand)" when marked by hand, with the items
  and amounts ("3x Mithril Bar"). The order chat gets no automatic line.
- R6: The mail entries sync to every guild member (live with the ORDER broadcast, and after login with OPUSH);
  members on 2.9 or older keep syncing orders as before and are never pushed orders for their mail entries.
- R7: The recipient of a mail (requester for the item, crafter for reagents) gets order news for it (badge, sound,
  chat line with the existing switches); looking at the Orders tab or the order window marks it seen.
- R8: Orders tab: "Mailed" in the status column with a small mail icon, a "Mailed" entry in the filter, sorted between
  claimed and done.
- R9: Peer data is safe: entries allow-listed (kind from a list, safe names, times in the horizon, at most 12 item
  pairs of positive integers), at most 30 per order (newest kept), the same on every client.

## Non-goals
- No detection of mails sent outside the queue (the manual button covers them).
- No detection of returned or bounced mail.
- No automatic close as done.

## Design
- `Core/Data/Orders.lua`: optional order field `ml = { {m, b, r, t, c?, h?, i?} }` (m = "item"|"mats", b sender,
  r recipient, t time, c = true complete, h = true by hand, i = flat `{itemID, count, ...}` <= 12 pairs). Sanitize,
  merge (union by `m..b..t`, newest 30), `Orders:RecordMail(orderID, entry)` (unique time per sender and kind),
  `Orders.MailVersion`, `Orders:MailDigest(limit)`, `Missing(..., remoteMailDigest)`, `Status` -> "mailed",
  `STATUS_RANK`.
- `Core/Data/MailQueue.lua`: pure `MailQueue.MailEntry(job, sentCounts, complete, byHand, now)`.
- `Core/Game/MailSender.lua`: OnSendSuccess and Done record the entry (via `addon.RecordOrderMail`) and broadcast.
- `Core/Net/Sync.lua`: HELLO `mdig`; `Missing` gets it. ORDER/OPUSH carry `ml` unchanged.
- `Core/Base/Init.lua`: PROTOCOL_MINOR 10.
- `Core/View/Model.lua`: history rows of kind "mail" (mode, recipient, items, partial, byHand); rows: `mailed`,
  live includes mailed, filter key "mailed"; overview: `canMarkItemMailed`, `canMarkMatsMailed`.
- `Core/View/Notify.lua`: `UnseenMail(orderBoard, myName, mailSeen)`, `MarkAllMailSeen`; local `ui.mailSeen[orderID]`.
- `UI/Alerts.lua`, `UI/OrderWindow.lua` (history text, status, button), `UI/Window.lua` (status, icon, filter).
- Locales, `docs/protocol.md` section 19, README, CHANGELOG.

## Tasks
- [x] T1 (M): Orders `ml` + status "mailed" + digest; `tests/test_order_mail.lua`.
- [x] T2 (S): MailQueue.MailEntry + MailSender hooks; tests (send success, partial, Done by hand, other recipient).
- [x] T3 (S): Sync `mdig`, protocol 2.10; tests (2.9 peer never pushed for mail, 2.10 peer is).
- [x] T4 (S): Model history/rows/overview; Notify mail news; tests.
- [x] T5 (M): UI: order window button + history, Orders tab status/icon/filter, Alerts; `test_load`.
- [x] T6 (S): locale, docs, verify.

## Review Focus (failure modes a happy-path test would miss)
1. RF1: A 2.9 peer drops `ml`: no endless OPUSH to it (separate `mdig`). Pinned by: T3.
2. RF2: Mail to someone other than the job's recipient (form changed) records nothing. Pinned by: T2.
3. RF3: Garbage `ml` entries (bad kind, huge item list, negative counts) are dropped, never the order. Pinned by: T1.
4. RF4: Mail for a pruned/unknown order: job still works, nothing recorded, no error. Pinned by: T2.
5. RF5: Mailed orders stay actionable (done, withdraw, cancel, claim). Pinned by: T4.

## Cross-cutting checklist (answer every line; "n/a: reason" is fine)
- [x] Protocol: minor 2.10 (additive: order field `ml`, HELLO `mdig`).
- [x] Stored data: schema unchanged; `ml` re-validated on load; older builds drop it (allow-list).
- [x] Trust model: guild members trusted (like claims); entries only shown escaped; recorded only by the sender's own
  client for its own sends.
- [x] Localization: labels through `Text`; item names from the viewer's client.
- [x] TOC load order: no new files.
- [x] Packaging: no new folders.
- [x] Tests: `tests/test_order_mail.lua`, `test_sync.lua`, `test_load.lua`.
- [x] Docs: protocol.md section 19, README, CHANGELOG, status.

## Decisions (user, 2026-11-27)
1. Both mail kinds count (item -> requester, reagents -> crafter).
2. New status "Mailed" between claimed and done; the requester still closes the order.
3. One history entry per mail; the status changes when nothing is left to send.
4. History shows items and amounts.
5. Notification to the recipient, like order news.
6. "Done" in the mailbox panel counts, marked "by hand".
7. A button in the order window to mark mailed / handed over by hand.
8. History only, no automatic chat line.
9. Synced to the whole guild.
10. Orders tab: own status, filter entry and mail icon.

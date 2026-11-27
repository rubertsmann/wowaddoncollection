# 050 Mail tag and pickup tracking: spec

- Status: done
- Created: 2026-11-27
- Target version: 1.8.0 (protocol 2.11, schema unchanged)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
Queued mails carry a short order tag in the subject, so the recipient's client notices when the items are taken out
and writes that into the order: the crafted item picked up closes the order as done.

## Requirements
- R1: The subject of a queued mail ends with `[#xxxxxx]`: a 6-character code of order id + mail kind, the same on every
  client; the subject stays <= 64 bytes (the name part is cut, never the tag).
- R2: When the player takes items out of a tagged mail (take one, take all, auto loot; also through other mail addons
  that call the same functions), the client records a pickup entry on the order: kind, who picked it up, the mail's
  sender, time, items and amounts taken. Returned mails and mails that only disappear (returned, expired) count not.
- R3: Only the expected recipient's pickup counts: the requester for the item, a crafter (with a claim) for reagents.
- R4: The requester picking up the crafted item closes the live order as done (history: done + "picked up").
- R5: Reagent pickups add a history row only.
- R6: The mail's sender gets order news ("Bob picked up your mail for 2x X").
- R7: The pickup entries sync like the mail entries; 2.10 peers keep syncing and are never pushed orders for them.
- R8: Inbox APIs missing or failing never break anything (guarded; logged).

## Non-goals
- Arrival in the mailbox is not recorded (user decision 2).
- Mails sent outside the queue are not tagged.

## Design
- `Core/Data/MailQueue.lua`: `MailQueue.Tag(orderID, mode)`, `MailQueue.ParseTag(subject)`, `MailQueue.TaggedSubject(text, tag)`,
  `MailQueue.InboxTotals(mails)` and `MailQueue.Pickups(before, after, taking)` (pure diff by tag + sender).
- `Core/Data/Orders.lua`: order field `rcv = { {m, b, r, t, i?} }` (m kind, b who picked it up, r the mail's sender),
  `Orders:RecordPickup`, `Orders.PickupVersion`, `Orders:PickupDigest`, `Missing(..., remotePickupDigest)`,
  `Orders:FindByTag(tag)`.
- `Core/Game/MailReceiver.lua` (new, after MailSender in the TOC): inbox scan on MAIL_SHOW / MAIL_INBOX_UPDATE, hooks on
  `TakeInboxItem` / `AutoLootMailItem` mark a tag as being taken; a decrease in the next scans is the pickup.
- `Core/Game/MailSender.lua`: tagged subject.
- `Core/Net/Sync.lua`: HELLO `rdig`; `Core/Base/Init.lua` minor 11.
- `Core/View/Model.lua`: history rows kind "pickup"; `Core/View/Notify.lua`: pickups of my mails as news;
  `UI/Alerts.lua`, `UI/OrderWindow.lua` texts; `UI/DevProbe.lua` `/psd fake pickup`.

## Tasks
- [x] T1 (M): MailQueue tag/parse/diff + Orders rcv/digest/FindByTag; `tests/test_mail_pickup.lua`.
- [x] T2 (M): MailReceiver + tagged subject; tests with a simulated inbox.
- [x] T3 (S): Sync rdig, protocol 2.11; test.
- [x] T4 (S): history, news, alert, window texts, dev trigger; tests.
- [x] T5 (S): locale, docs, verify.

## Review Focus
1. RF1: A returned or expired tagged mail (no take) records nothing. Pinned by: T1/T2.
2. RF2: A failed take (bags full: items stay) records nothing. Pinned by: T2.
3. RF3: The wrong person (not requester / not a crafter) picking up records nothing. Pinned by: T2.
4. RF4: 2.10 peers: no endless OPUSH (separate field and digest). Pinned by: T3.
5. RF5: Two tagged mails of the same order (partial sends): the second pickup counts too, no double count. Pinned by: T1.

## Cross-cutting checklist
- [x] Protocol: minor 2.11 (additive: order field `rcv`, HELLO `rdig`).
- [x] Stored data: schema unchanged; `rcv` re-validated on load.
- [x] Trust model: guild members trusted; entries written only by the picking-up client for itself.
- [x] Localization: subject prefix already translated; the tag is language-free.
- [x] TOC: `Core/Game/MailReceiver.lua` after `MailSender.lua` (both TOCs via deploy).
- [x] Packaging: under `Core/`, already packaged.
- [x] Tests: `tests/test_mail_pickup.lua`, `test_sync.lua`, `test_load.lua`.
- [x] Docs: protocol.md section 20, README, CHANGELOG, status, api-findings (inbox API when verified).

## Decisions (user, 2026-11-27)
1. The requester picking up the crafted item closes the order as done.
2. Only the pickup is recorded, not the arrival.
3. Reagent pickups by the crafter: history entry, status unchanged.
4. The sender gets order news when the mail was picked up.
5. (Claude) The tag goes in the subject (reading the body would mark the mail read); a separate order field and digest
   so 2.10 peers are not pushed forever.

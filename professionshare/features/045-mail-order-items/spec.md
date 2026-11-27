# 045 Mail order items: spec

- Status: done
- Created: 2026-11-27
- Target version: next minor (UI + local data; protocol unchanged)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
Queue mails for orders from the Orders tab (reagents to the crafter, or the crafted item to the requester); when a
mailbox opens, the queue fills one mail after another (recipient, subject, exact attachments) and the player presses
Send.

## Requirements
- R1: Orders tab: a mode switch "Mats -> crafter" / "Item -> requester" and a button "Add to mail queue (n)" that queues
  one mail job per ticked order. The tick boxes are shown always now (not only with Auctionator).
- R2: Mats mode: recipient = the order's active claimer; with several claimers a menu asks which one; no claimer -> not
  queued, chat message. Items = catalog reagents x order quantity. Item mode: recipient = the requester; items = the
  recipe's product x order quantity. Orders without data (no reagents / no product), or where the recipient is me, are
  not queued (chat line). The same order in the same mode is not queued twice.
- R3: A **Mail** tab next to Orders lists the queue (recipient, order, items, what is missing in my bags), with Remove
  and Move up per job, and the state of the mailbox ("closed" / "filling" / "ready to send").
- R4: The queue is saved per character (local SavedVariables), until a job is sent completely or removed.
- R5: When a mailbox opens and the queue is not empty, the first job is filled: Send Mail tab, recipient, subject
  ("ProfessionShare: <qty>x <recipe>"), attachments. Only the player presses Send.
- R6: Exact amounts: a whole stack is attached when it fits the remaining need; otherwise the needed amount is split into
  an empty bag slot first and that stack is attached. No empty bag slot -> that item is left out (missing).
- R7: Items I do not have (or not enough, or soulbound) are left out; the mail is filled with the rest and the panel
  shows what is missing. After sending, the job keeps only the remaining amounts (removed when nothing remains).
- R8: More than 12 attachments: the first 12 go in this mail; the rest stays in the job for the next mail.
- R9: After a successful send (`MAIL_SEND_SUCCESS`, for a mail to the job's recipient) the job is updated and the next
  job is filled. If that does not happen (event missing, player changed the mail), the job stays; a small panel at the
  mailbox has **Fill next**, **Skip** and **Remove** so the queue can always go on by hand.
- R10: Nothing is ever left on the cursor; no mail is ever sent by the addon; nothing happens in combat.

## Non-goals
- No automatic Send, no COD or money.
- No sync of the queue to other members (protocol unchanged).
- Item mode assumes one product per craft (most recipes); multi-yield recipes may queue too many.

## Design
- `Core/Data/MailQueue.lua` (new, pure): job records, `Add`, `Remove`, `MoveUp`, `Skip`, `First`, `List`,
  `JobForOrder(store, orderBoard, order, mode, recipient)`, `Plan(job, bagStacks, freeSlots)` -> attachment actions
  (whole / split-to-slot) + missing + overflow, `ApplySent(job, sentCounts)`, `SanitizePersisted`.
- `Core/Game/MailSender.lua` (new, client): bag snapshot, executes a plan step by step (split -> drop into empty slot ->
  wait for the slot -> pick up -> `ClickSendMailItemButton`), cursor guard, `MAIL_SHOW` / `MAIL_CLOSED` /
  `MAIL_SEND_SUCCESS` / `MAIL_FAILED`, snapshot of recipient + attachments taken when `SendMail` is called
  (`hooksecurefunc`, post-hook).
- `UI/Window.lua`: Orders tab mode switch + add button, Mail tab; `UI/MailPanel.lua` (new): the panel at the mailbox.
- `Core/Data/Store.lua`: top-level `mailQueue` (`[characterName] = { jobs }`), sanitized on load.
- Data shape change: `db.mailQueue`, `db.ui.mailMode`. Message shape change: none.

Job: `{ id, orderID, mode = "mats"|"item", recipient, recipeID, qty, label, items = { [itemID] = remaining },
createdAt }`.

Probe facts (evidence/probe-run-1.md, -2.md): attaching works; `MAIL_SEND_INFO_UPDATE` fires inside the click;
soulbound items are refused on the client and stay on the cursor (`UI_ERROR_MESSAGE 460`); a split clicked straight
into the mail attaches the whole stack. Not yet seen: the split via an empty bag slot, `SendMailNameEditBox:SetText`
with the mailbox open, `MAIL_SEND_SUCCESS`.

## Tasks
- [x] T1a (S): dev probe `UI/MailProbe.lua` + `tests/test_mail_probe.lua`.
- [x] T1b (S): user: the empty-slot split and filling confirmed in game through the finished feature (046 in-game check).
- [x] T2 (M): `MailQueue.lua` + `tests/test_mail_queue.lua` (jobs, dedupe, plan: whole/split/missing/overflow/bound, apply sent, sanitize).
- [x] T3 (S): Store: `mailQueue` table, sanitize on load.
- [x] T4 (L): `MailSender.lua` (fill, events, send snapshot) + tests against the simulated mailbox.
- [x] T5 (M): Orders tab: mode switch, add button, claimer menu; tick boxes always shown.
- [x] T6 (M): Mail tab + mailbox panel; locale strings.
- [x] T7 (S): docs, verify.md.

## Review Focus (failure modes a happy-path test would miss)
1. RF1: Player changes recipient or attachments before Send -> the job is not marked sent for the wrong mail. Pinned by: T4.
2. RF2: Split stack does not land (no empty slot, server slow) -> item counted missing, nothing on the cursor. Pinned by: T2, T4.
3. RF3: Soulbound item in the plan -> refused, cursor cleared, counted missing. Pinned by: T4.
4. RF4: Order gone (pruned) while queued -> the job still works from its own copy (recipient, items, label). Pinned by: T2.
5. RF5: Corrupt or foreign `mailQueue` in SavedVariables -> dropped by the sanitizer. Pinned by: T2.
6. RF6: Mailbox closed mid-fill -> stops, no error, job unchanged. Pinned by: T4.

## Cross-cutting checklist (answer every line; "n/a: reason" is fine)
- [x] Protocol: unchanged; nothing is sent to peers.
- [x] Stored data: new top-level `mailQueue` (created when missing, sanitized on load); `Store.SCHEMA` unchanged: additive
  and local only, older builds ignore it.
- [x] Trust model: job data comes from peer orders/catalog (already sanitized); recipient names are checked with
  `Utility.IsSafeName`; recipe names escaped before display.
- [x] Localization: labels through `Text`; the subject uses the recipe name in the sender's language.
- [x] Load order: `MailQueue.lua` after `BuyList.lua`; `MailSender.lua` in `Core/Game`; `MailPanel.lua` before `Window.lua`.
- [x] Packaging: new files under `Core/` and `UI/`.
- [x] Tests: `tests/test_mail_queue.lua` (13), `tests/test_mail_sender.lua` (8), `test_load.lua` (Mail tab, mailbox panel).
- [ ] Docs: README, CHANGELOG, docs/status.md, doc.md.

## Decisions (user answers and design choices, newest last)
- 2026-11-27: Build an in-game helper first to test the mail behaviour; the user runs it (user).
- 2026-11-27: Mail queue from the Orders tab, filled one mail after another when the mailbox opens; the player sends;
  the next one follows the send; if that is not possible a job stays in the queue (user).
- 2026-11-27: Orders tab switch: mats to the "I'll craft it" person, or the item to the requester (user).
- 2026-11-27: Exact amounts via a split into a free bag slot; attach what I have and keep the rest in the job; queue
  saved per character; with several claimers a menu asks who gets the mats (user, recommended options).
- 2026-11-27: A Mail tab next to Orders shows the queue (user).
- 2026-11-27: The tick boxes on the Orders tab are shown always (they now serve the mail queue too); feature 044's
  "nothing changes without Auctionator" now only holds for the buy-list controls (design).
- 2026-11-27: `Store.SCHEMA` stays 9: `mailQueue` is additive and local (design).

## Open questions
- Does the split via an empty bag slot land on Forever, and does `MAIL_SEND_SUCCESS` fire? (needs: game, T1b)

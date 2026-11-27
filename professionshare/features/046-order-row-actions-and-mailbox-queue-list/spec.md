# 046 Order row actions and mailbox queue list: spec

- Status: done
- Created: 2026-11-27
- Target version: next minor (UI + local settings; protocol and schema unchanged)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
Rework the Orders tab around the order row (filter dropdown, right-click action menu, inline action icons) and change
the mailbox side of the mail queue from "fill on open" to "list next to the inbox, fill on click".

## Requirements
- R1: One filter dropdown (like the Recipes category dropdown) replaces "Show: ..." and "Show finished": a radio group
  "Show" (All, Open, My requests, I'm crafting, I can craft) and a checkbox "Show finished".
- R2: Right-click on an order row selects it and opens a menu with the order actions (I'll craft it, Withdraw, Mark
  done, Cancel order, Whisper); only the possible ones are enabled; one click runs one action.
- R3: The bottom button row is removed. The secure **Craft** button moves to the top bar (right of the filter) and acts
  on the selected order (a menu entry cannot cast: WoW allows casts only from secure buttons).
- R4: Each order row has an action column with icon buttons and tooltips: I'll craft it, Withdraw, Mark done, Cancel order (as in the menu), "Mail reagents to the crafter" (needs a
  claimer and reagent data), "Mail the crafted item to the requester" (needs the product; not my own order), and, with
  Auctionator, "Add to the Auctionator buy list". Several claimers: a menu asks who gets the mats.
- R5: The tick boxes, the top-bar buy-list button and option, and the mail mode switch / add button are removed.
- R6: The Auctionator action opens a dialog: the order and its reagents, the "Subtract what I have" checkbox (saved),
  the hint that the list is searched the next time the auction house opens, Add / Cancel. Add puts the order into one
  collected buy list (saved per character), rebuilds the Auctionator list from all collected orders and sets the search
  for the next auction house visit (at the auction house: searches now). The collection is cleared when the auction
  house closes after its search ran.
- R7: Opening a mailbox no longer fills a mail. A panel next to the inbox lists every queued mail: recipient, order,
  items with have/missing counts, and per entry **Fill**, **Done**, **Delete**; a status line on top (number of mails,
  items ready, items missing).
- R8: Fill fills that entry's mail (recipient, subject, exact attachments, as in 045). After a confirmed send the
  amounts are taken off the job; nothing is filled until the next click.
- R9: Done takes the items attached in the mail form off that job (what is still missing stays as the reduced need);
  with nothing attached the job is removed. Delete removes the job.

## Non-goals
- No change to the mail filling itself (045) or to the Auctionator API use (044).

## Design
- `Core/View/Model.lua`: order rows get `canMailMats`, `canMailItem`, `hasClaimers`; `OrderFilterLabel`.
- `Core/Data/BuyList.lua`: pure collection helpers `CollectionAdd`, `CollectionPrune`.
- `Core/Game/MailSender.lua`: `FillJob(jobID)`, `Done(jobID)`; no fill on MAIL_SHOW, no fill after a send.
- `Core/Game/Auctionator.lua` + `Core/Game/Events.lua`: the collection is cleared on `AUCTION_HOUSE_CLOSED` after a search.
- `UI/Window.lua`: Orders tab rebuilt (filter dropdown, Craft in the top bar, context menu, action column, buy-list
  dialog); Mail tab "Fill" acts on the selected job.
- `UI/MailPanel.lua`: list of all jobs with Fill / Done / Delete.
- Data: `db.ui.buyListOrders[characterName] = { orderID, ... }`; `db.ui.mailMode` no longer used.

## Tasks
- [x] T1 (S): Model row flags + BuyList collection helpers + tests.
- [x] T2 (M): MailSender FillJob / Done / no auto fill + tests.
- [x] T3 (M): Auctionator collection flow (dialog logic, clear on AH close) + tests.
- [x] T4 (L): Orders tab rebuild (dropdown, menu, Craft in top bar, action column, dialog).
- [x] T5 (M): Mailbox panel list; Mail tab Fill on the selected job.
- [x] T6 (S): locale, docs, verify; deviation notes in 044 and 045.

## Review Focus (failure modes a happy-path test would miss)
1. RF1: The Craft button in the top bar still updates only out of combat and acts on the selected order. Pinned by: T4 (READ-ONLY + in game).
2. RF2: Done with items of another job (or the player's own) in the form -> only this job's items count. Pinned by: T2.
3. RF3: A collected order that was pruned -> dropped from the buy list without error. Pinned by: T1.
4. RF4: The mailbox panel with many jobs stays inside its frame (scrolls / caps rows). Pinned by: T5.

## Cross-cutting checklist (answer every line; "n/a: reason" is fine)
- [x] Protocol: unchanged.
- [x] Stored data: `Store.SCHEMA` unchanged; `db.ui.buyListOrders` is local and optional (unknown ui keys are kept).
- [x] Trust model: unchanged; recipe names and player names escaped before display.
- [x] Localization: new labels through `Text`, deDE added.
- [x] Load order: no new files.
- [x] Packaging: n/a (no new files).
- [x] Tests: model flags + buy collection (`test_buy_list.lua`), mail sender (`test_mail_sender.lua`), `test_load.lua` (buy list flow, mail action, panel).
- [x] Docs: README, CHANGELOG, docs/status.md, doc.md.

## Decisions (user answers and design choices, newest last)
- 2026-11-27: One filter dropdown with categories; right-click menu for the order actions; inline action icons for the
  mail modes and Auctionator; no tick boxes; mailbox panel lists the queue, fill on click, Delete and Done (user).
- 2026-11-27: Bottom row removed; Craft was asked into the right-click menu, which WoW does not allow (a cast needs a
  secure button), so Craft moves to the top bar and acts on the selected order (user + constraint).
- 2026-11-27: Buy list orders are collected until the auction house, then the collection starts fresh (user).
- 2026-11-27: After a confirmed send the job is updated and the next mail waits for a click (user).
- 2026-11-27: Done subtracts what is attached; nothing attached removes the job (user).
- 2026-11-27: The order actions (claim, withdraw, done, cancel) also get row icons; Craft cannot (an inline secure button per row would make the window protected in combat) (user + constraint).
- 2026-11-27: The Mail tab gets the same inline icons per mail (Move up, Fill, Done, Delete) instead of its bottom buttons; one shared helper draws both action columns (user + design).

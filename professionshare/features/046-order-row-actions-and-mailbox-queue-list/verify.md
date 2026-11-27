# 046 Order row actions and mailbox queue list: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.

Baseline before work: `luajit tests/run.lua` -> `382 passed, 0 failed`
Result after work:    `luajit tests/run.lua` -> `384 passed, 0 failed`

| ID | Requirement / Review Focus | How verified | Level | Evidence | Result | Date |
|---|---|---|---|---|---|---|
| R1 | One filter dropdown (radio + Show finished) | `test_load` builds and refreshes the Orders tab (stub dropdown) | READ-ONLY (menu) | suite 384 | pending in game | 2026-11-27 |
| R2 | Right-click menu with the order actions | code (`showOrderMenu`, `runOrderAction`) | READ-ONLY | - | pending in game | 2026-11-27 |
| R3 | Bottom row gone, Craft in the top bar | code (SecureDock placement next to the filter) | READ-ONLY | - | pending in game | 2026-11-27 |
| R4 | Action icons with tooltips; claimer menu | row flags: `buy list: order rows say which mail actions are possible`; `test_load` mail action | OFFLINE (flags) / NOT-VERIFIED (look) | suite 384 | pass offline | 2026-11-27 |
| R5 | Ticks and old controls removed | grep: no references left | READ-ONLY | - | pass | 2026-11-27 |
| R6 | Buy-list dialog, collection, search at the next AH, cleared after the visit | `buy list: the collection takes each order once ...`, bridge `TakeSearchedThisVisit`, `test_load` (two orders -> one list of 9, clear) | OFFLINE (logic) / NOT-VERIFIED (dialog, AH) | suite 384 | pass offline | 2026-11-27 |
| R7 | Mailbox panel lists every job, nothing filled on open | `mail sender: opening the mailbox fills nothing ...`; `test_load` renders the panel | OFFLINE (logic) / NOT-VERIFIED (look) | suite 384 | pass offline | 2026-11-27 |
| R8 | Fill on click; after a send no automatic fill | `... a click fills that mail ...`, `... the next mail waits for a click` | OFFLINE (sim) | suite 384 | pass | 2026-11-27 |
| R9 | Done subtracts what is attached; Delete removes | `mail sender: Done subtracts what is attached ...` | OFFLINE (sim) | suite 384 | pass | 2026-11-27 |
| RF1 | Craft button still out-of-combat only, selected order | unchanged `refreshCraftButton`; placement only | READ-ONLY | - | pending in game | 2026-11-27 |
| RF2 | Done counts only this job's items | `Done` caps by the job's items (code + test) | OFFLINE | suite 384 | pass | 2026-11-27 |
| RF3 | Pruned collected order dropped | `buy list: the collection ... drops orders that are gone` | OFFLINE | suite 384 | pass | 2026-11-27 |
| RF4 | Many jobs: panel caps at 8 rows + "n more" | code (`MAXIMUM_ROWS`) | READ-ONLY | - | pending in game | 2026-11-27 |

## In-game checklist (user)
`/reload` is enough (no new files). `/console scriptErrors 1`.
- [ ] Orders tab: one filter dropdown top left (Show: All / Open / My requests / I'm crafting / I can craft, and "Show finished"); **Craft** next to it; no buttons at the bottom; no tick boxes.
- [ ] Right-click an order: menu with I'll craft it, Withdraw, Mark done, Cancel order, Whisper, the mail actions (and the buy list with Auctionator); impossible ones greyed out.
- [ ] Row icons (hammer = I'll craft it, pass = Withdraw, check = Mark done, cross = Cancel order, bag, letter, coin with Auctionator): tooltips; greyed out when not possible; each does its action. `/psd fake linen` -> the bag icon queues the mats (menu for two claimers).
- [ ] Coin icon: dialog with the reagents, Subtract checkbox, hint; Add twice with two orders -> chat "Buy list: 2 orders ..."; at the auction house the Shopping tab searches; after closing the auction house the next Add starts a fresh list.
- [ ] Mailbox: the panel lists every queued mail with ready/missing counts; nothing is filled on open; **Fill** fills that mail; after Send nothing new is filled; **Done** with items attached keeps the missing rest; **Delete** removes.
- [ ] Craft from the top bar on a selected order you can craft (open profession, then craft).
- [ ] Mail tab: each mail has icons (arrow = Move up, letter = Fill, check = Done, cross = Delete); no bottom buttons; Fill is greyed out unless a mailbox is open; Move up is greyed out on the first mail.

## Accepted gaps
- none yet

## In-game result (2026-11-27)
The user ran the in-game checklist on the dev build after feature 046 (Orders tab rework, row icons, buy-list dialog,
mailbox panel, Mail tab icons) and reported: "looks fine and works as expected". On that report the rows marked
READ-ONLY or NOT-VERIFIED above count as IN-GAME (user report, no screenshot or SavedVariables evidence on disk).
Accepted by the user on 2026-11-27. MULTI-CLIENT (a second real guild member receiving mails) was not part of the check.

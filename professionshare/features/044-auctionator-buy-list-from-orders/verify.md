# 044 Auctionator buy list from orders: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> `337 passed, 1 failed` (stale generated dev TOC; fixed by `tools/deploy.ps1`)
Result after work:    `luajit tests/run.lua` -> `354 passed, 0 failed` (350 before the search part)

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence (output line, file, screenshot) | Result | Date |
|---|---|---|---|---|---|---|
| R1 | Tick box per order, any order, session-only, dropped when the order is gone, cleared after a created list | Code: `buyListTicks` + prune in `refreshOrders`; render with Auctionator in `test_load` | READ-ONLY | `load: all TOC files run in order ...` passes (render only, no click) | pending in game | 2026-11-27 |
| R2 | Controls hidden without Auctionator | `auctionator bridge: unavailable without Auctionator or without the shopping list API`; `test_load` renders both ways | OFFLINE (logic) / NOT-VERIFIED (look) | suite 350 passed | pass offline | 2026-11-27 |
| R3 | Reagents x qty summed per item | `buy list: reagents x order quantity are summed per item across ticked orders` | OFFLINE | suite 350 passed | pass | 2026-11-27 |
| R4 | Full / subtract modes | `buy list: subtract mode ...`, `buy list: full mode ignores what I own` | OFFLINE | suite 350 passed | pass | 2026-11-27 |
| R5 | List created through the API, exact terms with quantity | `auctionator bridge: creates the list with exact terms and quantities` (stub) | OFFLINE (stub) / NOT-VERIFIED (real Auctionator) | suite 350 passed | pass offline | 2026-11-27 |
| R6 | Missing recipe data and unloaded names reported | `buy list: orders without reagent data ...`, `buy list: an item without a loaded name ...`; chat lines in `exportBuyList` | OFFLINE (logic) | suite 350 passed | pass offline | 2026-11-27 |
| R7 | Failure -> modal with error + import text | `auctionator bridge: an error inside Auctionator is caught ...`; dialog itself in game | OFFLINE (logic) / NOT-VERIFIED (dialog) | suite 350 passed | pass offline | 2026-11-27 |
| R8 | Nothing ticked / nothing to buy -> no API call | button disabled at 0 ticks; `buy list: empty selection ...`, subtract-covered test | OFFLINE (logic) | suite 350 passed | pass offline | 2026-11-27 |
| R9 | At the AH: list created, then searched at once | `auctionator bridge: search runs only with the auction house open, exact terms with quantities` (stub); handler branch in `exportBuyList` | OFFLINE (bridge) / NOT-VERIFIED (real tab switch) | suite 354 passed | pass offline | 2026-11-27 |
| R10 | Away from the AH: search waits for the next opening, runs once; setting on settings page | `auctionator bridge: a pending search runs once, on the next auction house opening`; settings page built with a stub in `test_load` | OFFLINE (logic) / NOT-VERIFIED (event + 1 s timing on Forever) | suite 354 passed | pass offline | 2026-11-27 |
| RF6 | AH closed / no search API / search raising; pending kept without Auctionator | `auctionator bridge: a search error is caught ...`, `... a pending search is kept while Auctionator is missing` | OFFLINE | suite 354 passed | pass | 2026-11-27 |
| RF1 | Auctionator absent / old API -> no controls, no error | bridge unavailable test (`Auctionator = { API = { v1 = {} } }`) | OFFLINE | suite 350 passed | pass | 2026-11-27 |
| RF2 | Auctionator raises -> caught, copy text | bridge error test; broken `ConvertToSearchString` fallback test | OFFLINE | suite 350 passed | pass | 2026-11-27 |
| RF3 | `;` `^` `"` in names stripped | `buy list: separators and quotes are stripped from item names` | OFFLINE | suite 350 passed | pass | 2026-11-27 |
| RF4 | Vanished order / no reagent data -> skipped, reported | `buy list: orders without reagent data are reported, vanished orders are skipped` | OFFLINE | suite 350 passed | pass | 2026-11-27 |
| RF5 | Uncached item without name -> reported, never empty term | `buy list: an item without a loaded name ...`; separators-only name test | OFFLINE | suite 350 passed | pass | 2026-11-27 |

## In-game checklist (things only the user can do)
Dev build (`/psd`), Auctionator enabled, `/console scriptErrors 1`.
- [ ] Orders tab shows a tick box left of every icon, plus **Auctionator buy list (0)** (greyed) and **Subtract what I have** in the top bar; the help text does not overlap them.
- [ ] Tick 2 orders -> button reads `(2)`; switch the filter and back -> ticks kept.
- [ ] After a successful export every tick box is empty and the button reads `(0)`; after a failed export (failure path below) the ticks stay.
- [ ] Click the button -> chat: `Auctionator shopping list ProfessionShare buy list created with N items...`.
- [ ] AH -> Auctionator -> Shopping: list **ProfessionShare buy list** holds one exact entry per reagent; note whether a quantity is shown (open question in spec).
- [ ] Tick **Subtract what I have** with a reagent in your bags -> export again -> that item's amount is lower or gone; `/reload` -> option still ticked.
- [ ] Disable Auctionator, `/reload` -> no tick boxes, no buy-list controls, Orders tab as before.
- [ ] At the auction house (Auctionator open): click the export button -> Auctionator switches to Shopping and searches the items at once; chat: `...created; searching N items in the Shopping tab.`
- [ ] Away from the auction house: export -> chat says the search starts when you open the auction house -> talk to an auctioneer -> about 1 s later the Shopping tab searches the items. Open/close the AH again -> no second search.
- [ ] Settings page (`/psd options`): section **Auctionator**, untick **Search the buy list when I open the auction house** -> export away from the AH -> opening the AH does not search; `/reload` -> still unticked.
- [ ] Optional failure path: `/run Auctionator.API.v1.CreateShoppingList = function() error("test") end`, click export -> window with the error and import text; paste the text in Shopping -> Import works. `/reload` afterwards.

## Accepted gaps
- none yet

## In-game result (2026-11-27)
The user ran the in-game checklist on the dev build after feature 046 (Orders tab rework, row icons, buy-list dialog,
mailbox panel, Mail tab icons) and reported: "looks fine and works as expected". On that report the rows marked
READ-ONLY or NOT-VERIFIED above count as IN-GAME (user report, no screenshot or SavedVariables evidence on disk).
Accepted by the user on 2026-11-27. MULTI-CLIENT (a second real guild member receiving mails) was not part of the check.

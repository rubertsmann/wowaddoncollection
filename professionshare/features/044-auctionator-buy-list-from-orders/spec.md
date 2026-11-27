# 044 Auctionator buy list from orders: spec

- Status: done
- Created: 2026-11-27
- Target version: next minor (UI + local setting only)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
On the Orders tab, tick any orders and turn the reagents they need into an Auctionator shopping list with one click,
when (and only when) Auctionator is installed.

## Requirements
- R1: Every order row on the Orders tab has a checkbox. Any visible order can be ticked, whoever requested or claimed
  it. Ticks live for the session, survive refreshes and filter changes, and are dropped for orders that no longer exist.
  After a list was created successfully all ticks are cleared; after a failure (or nothing to buy) they stay.
- R2: (tick boxes: always shown since feature 045) The buy-list controls (button "Auctionator buy list" + "Subtract what I have" checkbox) are hidden unless the
  Auctionator shopping-list API (`Auctionator.API.v1.CreateShoppingList`) exists. Without Auctionator nothing changes.
- R3: The buy list = for each ticked order, every catalog reagent x reagent count x order quantity, summed per item.
- R4: Mode "full" buys the whole amount; mode "subtract" buys `max(0, need - owned)` with owned = bags + bank
  (`Api.ItemCount`); items fully covered are left out. The mode is a saved local setting (default: full).
- R5: The list is created through Auctionator's API as one exact-match search term per item with its quantity, under a
  fixed list name; an existing list of that name is replaced (Auctionator's own behaviour).
- R6: Ticked orders whose recipe has no reagent data, and reagents whose item name is not loaded yet, are reported in
  chat after the export (never silently dropped). Item names come from the client (viewer's language), falling back to
  the scanned reagent name.
- R7: If the API call fails (error raised, API changed), a modal shows the error text and a read-only copy box with the
  list in Auctionator's import format (`ListName^term^term`, Shopping -> Import) that the user can paste.
- R8: Nothing ticked, or nothing left to buy: no API call, a short chat message instead.
- R9: Export while the auction house is open: after the list is created, Auctionator's Shopping tab opens and searches
  the items at once (`API.v1.MultiSearchAdvanced`, exact terms with quantities). A failed search is reported in chat;
  the list stays.
- R10: Export away from the auction house with the setting "Search the buy list when I open the auction house" on
  (default on, settings page section "Auctionator", only shown with Auctionator): the search waits and starts once, about
  1 s after the next `AUCTION_HOUSE_SHOW`. The next export replaces a waiting search; it is not kept across `/reload`.

## Non-goals
- No price lookup and no buying: Auctionator searches, the player buys.
- Addons cannot open the auction house window (the client opens it only through an auctioneer), so there is no "open
  Auctionator" from elsewhere.
- No sync of ticks or of the buy list to other members (protocol unchanged).
- No recursion into sub-reagents (e.g. bars for an item that needs bars made from ore).
- No support for other AH addons (TSM, Auction-Flip).

## Design
- Files touched:
  - `Core/Data/BuyList.lua` (new, pure): `Build(store, orderBoard, orderIDs, options)` -> `{ items, missingRecipes,
    unnamed }`; `SearchTerm(name, quantity)` (exact, `;`/`^`/`"` removed from the name); `ImportText(listName, terms)`.
  - `Core/Game/Auctionator.lua` (new, client side, the only file that touches Auctionator): `IsAvailable()`,
    `SearchStrings(items)` (uses `API.v1.ConvertToSearchString`, falls back to `BuyList.SearchTerm`),
    `CreateShoppingList(name, strings)` wrapped in `pcall` -> `ok, err`.
  - `UI/Window.lua` (changed): row checkbox, controls on the Orders tab, export handler, error modal with copy box
    (generalises the existing `UI.ShowExport` dialog: title + hint + text parameters).
  - `Locales/enUS.lua`, `Locales/deDE.lua`: new strings.
  - `ProfessionShare.toc` and the dev TOC generator: `## OptionalDeps: Auctionator` (Auctionator loads first when
    present), new files after `Core/Data/Orders.lua` / in `Core/Game`.
  - `Core/Game/Auctionator.lua` (search, R9/R10): `IsAuctionHouseOpen()`, `Search(items)`,
    `SetPendingSearch`/`HasPendingSearch`/`RunPendingSearch(after, report)`.
  - `Core/Game/Events.lua` (changed): `AUCTION_HOUSE_SHOW` also runs a waiting search.
  - `UI/Alerts.lua` (changed): settings section "Auctionator" with the search-on-open checkbox.
- Data shape change: `db.ui.buyListSubtract` (true or absent), `db.ui.buyListSearchOnOpen` (false or absent = on); both local only.
- Message shape change: none.
- Pure logic lives in: `Core/Data/BuyList.lua`; Auctionator calls only in `Core/Game/Auctionator.lua`.

Auctionator facts (read from the installed Forever build, version 354, `Source/API/v1/ShoppingLists.lua`,
`Source/Search/Advanced.lua`, `Source/Shopping/ImportExport.lua`):
- `CreateShoppingList(callerID, name, searchStrings)` deletes a same-named list, creates it, appends the strings and
  fires `ListImportFinished`; it does not need the AH to be open. Raises `error()` on bad arguments.
- Search string = `strjoin(";", query, categoryKey, minIlvl, maxIlvl, minLvl, maxLvl, minCrafted, maxCrafted, minPrice,
  maxPrice, quality, tier or "#", expansion, quantity)`; `query` is `"Name"` for exact matches.
- Import text: one list per line, `ListName^item1^item2`.
- `MultiSearchAdvanced(callerID, terms)` (`Source/API/v1/MultiSearch.lua`) errors unless `AuctionFrame` or
  `AuctionHouseFrame` is shown, rejects string values containing `;`/`^` or wrapped in quotes, clicks
  `AuctionatorTabs_Shopping` and searches a temporary list "<callerID> (temporary)".
- On `AUCTION_HOUSE_SHOW` the legacy Auctionator frame calls `ShowDefaultTab()` at once and again via
  `C_Timer.After(0, ...)` (`Source_LegacyAH/Core/Mixin.lua`), so a search started in the same frame would be switched
  away; hence the 1 s delay.

## Tasks
- [x] T1 (M): `Core/Data/BuyList.lua` + `tests/test_buy_list.lua`. Verify: aggregation, both modes, missing recipe,
  unnamed item, name sanitising, import text, empty selection.
- [x] T2 (S): `Core/Game/Auctionator.lua` with an Auctionator stub in tests (available / missing / raising). Verify:
  `tests/test_buy_list.lua` adapter cases.
- [x] T3 (S): TOC (`OptionalDeps`, file order), dev TOC generator, `db.ui.buyListSubtract` default. Verify: `test_load.lua`.
- [x] T4 (M): Orders tab UI: checkboxes, controls hidden without Auctionator, export handler + chat report, error modal
  with copy box; locale strings. Verify: `test_load.lua`, `test_locale_files.lua`, in game.
- [x] T5 (S): docs (doc.md, README, CHANGELOG, docs/status.md), verify.md.
- [x] T6 (S): `Bridge.Search` + pending search, tests first. Verify: `tests/test_buy_list.lua` search/pending cases.
- [x] T7 (S): export handler searches at the AH or leaves a waiting search; `AUCTION_HOUSE_SHOW` hook; settings
  section; deDE strings. Verify: `test_load.lua` (settings page with an Auctionator stub), in game.
- [x] T8 (S): docs and verify rows for R9/R10, RF6.

## Review Focus (failure modes a happy-path test would miss)
1. RF1: Auctionator absent or an older build without `API.v1.CreateShoppingList` -> no controls, no Lua error. Pinned by: T2, T4.
2. RF2: Auctionator raises inside the call (changed signature, bad string) -> modal with error + copy text, addon keeps
   working. Pinned by: T2.
3. RF3: Item name with `;`, `^` or `"` (peer-supplied scanned name) would corrupt the search/import string -> stripped.
   Pinned by: T1.
4. RF4: Ticked order pruned/merged away -> skipped (its tick is dropped); recipe without catalog reagents -> skipped and counted in chat; never a crash. Pinned by: T1.
5. RF5: Uncached item (GetItemInfo nil, no scanned name) -> reported as "not loaded, try again", never exported as an
   empty name. Pinned by: T1.
6. RF6: Search started while the AH is closed / Auctionator without `MultiSearchAdvanced` / search raising -> no call
   or a caught error, chat line, list kept; a waiting search runs exactly once and is kept while Auctionator is missing.
   Pinned by: T6.

## Cross-cutting checklist (answer every line; "n/a: reason" is fine)
- [x] Protocol: unchanged; nothing is sent.
- [x] Stored data: `Store.SCHEMA` unchanged; `db.ui.buyListSubtract` is an optional local boolean, missing = false
  (checked: `Store.lua` keeps unknown `ui` keys; it only removes a fixed list of old ones).
- [x] Trust model: reagent names come from peers' catalog entries (already allow-listed, no `|`); `;^"` are stripped
  before they reach Auctionator; the error text is escaped before display.
- [x] Localization: list name and all labels through `Text`; item names from the client in the viewer's language.
- [x] Load order: `BuyList.lua` after `Orders.lua`; `Auctionator.lua` with the other `Core/Game` files; `OptionalDeps`.
- [x] Packaging: new files are under `Core/`, already packaged; `features/` stays ignored. CurseForge relation
  "optional dependency: auctionator" in `tools/curseforge.json` (sent by `../tools/upload-curseforge.ps1`) and `.pkgmeta`.
- [x] Tests: `tests/test_buy_list.lua` (adversarial: separators in names, missing data, unloaded names, API missing or raising).
- [x] Docs: README (Orders tab), CHANGELOG, docs/status.md, doc.md.

## Decisions (user answers and design choices, newest last)
- 2026-11-27: Orders are chosen by a checkbox per row; ownership does not matter (user).
- 2026-11-27: Full amount vs subtract-owned is a user option (user). Default full; owned = bags + bank.
- 2026-11-27: Controls hidden without Auctionator; on export failure a modal with the error and a copy-paste buy list (user).
- 2026-11-27: Call `Auctionator.API.v1.CreateShoppingList` directly instead of only exporting text: it exists on the
  Forever build and needs no AH window (design).
- 2026-11-27: Fixed list name (localized "ProfessionShare buy list"); each export replaces it (design; Auctionator
  replaces same-named lists anyway).
- 2026-11-27: "Open Auctionator right away": search at once at the AH, and optionally when the AH next opens; both
  implemented (user: "do it"). Only the public `MultiSearchAdvanced` is used, not Auctionator internals (EventBus,
  `AuctionatorTabs_Shopping`), so the search runs on Auctionator's temporary list next to the named one (design).
- 2026-11-27: Search-on-open defaults to on: it only acts after the player clicked the export button (design).
- 2026-11-27: A successful export clears all ticks (user); a failed one keeps them so the player can retry (design).

## Open questions
- Does Auctionator on Forever honour the `quantity` field in the Shopping tab (shows "x / N")? (needs: game)

# 011 Item categories and text search: spec

- Status: verifying
- Created: 2026-11-16
- Target version: 0.5.0 (UI + local cache, no protocol/schema change expected)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
Find recipes by what they make: a category selector (e.g. only head pieces, elixirs, buff food), a profession dropdown and
a free-text search that also matches the item's effect text (e.g. "Intelligence").

## Requirements
- R1: Category selector on the Recipes tab, built from the item each recipe makes (`catalog[id].produces`): class,
  subclass, equip slot (`GetItemInfoInstant`). Checkbox-style multi-select if the client offers it, else a dropdown;
  categories follow the selected profession. Recipes without an item (enchants) get their own group.
- R2: The professions toggle button becomes a dropdown with one entry per profession.
- R3: The search field is free text: words in any order match name, reagents, category and the effect/tooltip text
  of the item (or of the recipe spell when there is no item), in the viewer's own client language.
- R4: Effect/tooltip text is read and cached on this client only; it is never sent to peers (trust model unchanged).
- R5 (dev): a dev-only probe records what the client returns for items, spells, tooltips, profession filters and UI
  templates, written to SavedVariables for offline analysis.

## Non-goals
- No own item database: everything comes from the client's item/spell data.
- No sending of category or tooltip text over the wire.

## Design
- Files touched: `Core/Model.lua` (CategoryKey, RecipeCategories, TooltipSearchText, BuildRecipeRows with categories +
  word search), `Core/ItemText.lua` (new: tooltip text cache and reader queue), `Core/Api.lua` (ItemCategoryInfo,
  CategoryLabel, CategoryGroupLabel, ItemTooltipLines), `Core/Store.lua` (`itemText` table, emptied by Clean),
  `UI/Window.lua` (profession dropdown, category checkbox menu, SearchBoxTemplate, text pump while the tab is open,
  fallbacks without menus), `UI/DevProbe.lua` (dev only), `Locales/deDE.lua`, `TalentShare.toc`, `tests/run.lua`,
  `tests/test_categories.lua`.
- Data shape change: `db.itemText = { locale, items = { [itemID] = text } }` (this client only, max 400 bytes per item,
  starts over when the client language changes); `devProbe` in the dev SavedVariables only. No schema bump (new
  optional key, read defensively).
- Message shape change: none.
- Pure logic lives in: `Core/Model.lua` (category buckets, search matching); WoW calls in `Core/Api.lua`.

## Tasks
- [x] T1 (S): dev probe (button on the Debug tab, `/tsd itemprobe [itemID ...]`). Verify: user runs it, file read from disk
- [x] T2 (M): category buckets + selector (R1). Verify: tests + in-game
- [x] T3 (S): profession dropdown (R2). Verify: in-game
- [x] T4 (M): free-text search incl. cached effect text (R3, R4). Verify: tests + in-game

## Review Focus (failure modes a happy-path test would miss)
1. RF1: item not cached yet -> category from `GetItemInfoInstant` still works, text filled in later. Pinned by: T4
2. RF2: recipe without `produces` (enchant, old catalog entry) -> "no item" group, searchable by name and reagents only (recipe ids are not spell ids on Forever). Pinned by: T2
3. RF3: hundreds of items -> tooltip reading spread over frames, cached. Pinned by: T4
4. RF4: client language changes -> text cache rebuilt. Pinned by: T4

## Cross-cutting checklist
- [x] Protocol: unchanged.
- [x] Stored data: `db.itemText` local cache, no schema bump, garbage entries ignored and re-read; `/ts clean` empties it.
- [x] Trust model: tooltip text local only (R4); categories from the client's item data for an id (`produces`, validated
  by `Store.SanitizeCatalogEntry`); profession names still escaped.
- [x] Localization: category names from the client (`_G[equipLoc]`, `C_Item.GetItemClassInfo/GetItemSubClassInfo`);
  new UI strings in deDE.
- [x] Load order: `UI/DevProbe.lua` after `UI/Alerts.lua`.
- [x] Packaging: DevProbe ships but is inert in the live build (no button, no command).
- [x] Tests (`tests/test_categories.lua`, 7), Docs (README, CHANGELOG, doc.md).

## Decisions (user answers and design choices, newest last)
- 2026-11-16: User asked for a dev output button first, so the unknown client APIs are checked before building R1-R3.
- 2026-11-16: User wants checkbox-style category select if possible, else dropdown per current profession; professions
  toggle -> dropdown; search -> free text.
- 2026-11-16: Probe answered the API questions (docs/api-findings.md); user: "implement the features".
- 2026-11-16: Several checked categories = any of them (OR); none checked = all. Changing the profession clears them.
- 2026-11-16: Armor by slot (robe = chest); weapons and everything else by subclass; recipes without item in "Other".
- 2026-11-16: Effect text from `C_TooltipInfo.GetItemByID` (gear stats and "Use:" text in one source), read 8 items per
  0.2 s only while the Recipes tab is open.

## Open questions
- Exact look of WowStyle1DropdownTemplate / FilterDropdown texts on Forever (OverrideText) (needs: game)
- Enchanting/alchemy items not seen by the probe (needs: game, a guild member with those recipes)

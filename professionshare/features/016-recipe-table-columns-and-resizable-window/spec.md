# 016 Recipe table columns and resizable window: spec

- Status: done
- Created: 2026-11-18
- Target version: 0.7.x (UI + local settings only)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
The Recipes list becomes a sortable table with column headers, recipe names in item-quality colour, columns chosen in
the options panel, and the main window can be resized with a grip at its bottom right while every tab scales with it.

## Requirements
- R1: Recipe names in the Recipes list are coloured by the crafted item's quality (poor grey ... legendary orange);
  recipes without an item, or whose item is not cached yet, use the default (white) colour. Quality colour is
  refreshed when the client delivers item data (`GET_ITEM_INFO_RECEIVED`), debounced.
- R2: The Recipes list is a table with a header row. Columns: Name (icon + name, always shown), Item level,
  Required level, Profession, Skill (recipe's `minSkill`), Category (feature 011 category label).
- R3: Each optional column can be switched on/off with its own checkbox in the options panel (section "Recipe list");
  several can be on at once. The choice is saved per account in `TalentShareDB.ui.recipeColumns`. Default: all on.
- R4: Default sort is item level, highest first. Missing values (no item / not cached) always sort last, whatever the
  direction; ties sort by name, then recipe id. Clicking a header sorts by that column (second click flips direction);
  the options panel has a "Sort by" choice (item level / required level / name / profession / skill / category) and a
  direction choice. Header clicks and the option write the same saved value `ui.recipeSort`.
- R5: Column layout: optional columns have fixed widths, Name takes the rest (minimum width); hidden columns leave no gap.
- R6: The main window has a resize grip at the bottom right; dragging it resizes the window between a minimum
  (780 x 520, today's size) and the screen size. The size is saved (`ui.windowSize`) and restored on the next open.
- R7: All four tabs scale with the window: the scroll lists of Recipes, Orders, Available and Debug grow/shrink in both
  directions (more rows when taller); the Recipes detail panel keeps a fixed width at the right; bottom buttons stay at
  the bottom.
- R8: Invalid saved values (wrong types, unknown column/sort keys, absurd sizes) fall back to defaults; no Lua error.

## Non-goals
- No Crafters column (user did not choose it; crafters stay in the detail panel and tooltip). The "{n} crafters" text
  at the right of each row goes away.
- No column reordering or drag-resizing of individual columns.
- Orders / Available / Debug lists stay single-label rows (they only scale).
- No change to LibGuildSync's `Widgets.CreateScrollList` (shared with GuildGames); TalentShare gets its own resizable list.

## Design
- Files touched:
  - `Core/View/RecipeTable.lua` (new, pure): column definitions, settings get/set with validation (columns, sort,
    window size), `Layout(visibleColumns, totalWidth)`, `Sort(rows, sort)`, `QualityHex(quality)` fallback table,
    `ClampWindowSize`.
  - `Core/View/Model.lua` (changed): `BuildRecipeRows` fills `quality`, `itemLevel`, `requiredLevel`, `skill`,
    `categoryLabel` via an optional `lookups.itemDetails(itemID)` / `lookups.label`.
  - `Core/Game/Api.lua` (changed): `Api.ItemDetails(itemID)` -> quality, itemLevel, requiredLevel (C_Item.GetItemInfo,
    requests the load when uncached); `Api.QualityHex(quality)` via `C_Item.GetItemQualityColor` / `ITEM_QUALITY_COLORS`,
    else RecipeTable's table.
  - `UI/Table.lua` (new, client-only): `CreateResizableList(parent, createRow, fillRow)` (same `SetData/Refresh/offset`
    API as the library list; rows created on demand in `OnSizeChanged`), `CreateHeader(parent, onClick)`, `CreateTableRow`.
  - `UI/Window.lua` (changed): Recipes table + header; all lists anchored to their tab; resize grip; size save/restore;
    debounced recipe refresh on ITEM_INFO.
  - `UI/Alerts.lua` (changed): options panel section "Recipe list" (column checkboxes, sort key + direction buttons);
    fallback window taller.
  - `Locales/enUS.lua`, `Locales/deDE.lua`: new texts. `TalentShare.toc`: new files.
- Data shape change: new local-only keys under `TalentShareDB.ui`: `recipeColumns` (table<string, boolean>),
  `recipeSort` ({ key, descending }), `windowSize` ({ width, height }). Read through validators; no schema bump.
- Message shape change: none.
- Pure logic lives in: `Core/View/RecipeTable.lua`, `Core/View/Model.lua`; WoW calls only in `Core/Game/Api.lua` and `UI/`.

## Tasks
- [x] T1 (M): `Core/View/RecipeTable.lua` + `tests/test_recipe_table.lua` (settings validation, layout, sort incl. nil-last and direction, quality fallback, size clamp). Verify: `luajit tests/run.lua`
- [x] T2 (S): `Model.BuildRecipeRows` item details + category label fields; tests in the same file. Verify: suite
- [x] T3 (S): `Api.ItemDetails`, `Api.QualityHex`. Verify: `tests/test_load.lua` (loads), READ-ONLY for client behaviour
- [x] T4 (M): `UI/Table.lua` resizable list + header. Verify: test_load; in game
- [x] T5 (L): `UI/Window.lua`: recipe table, quality colour, header sort, all tabs anchored, resize grip, size save. Verify: in game
- [x] T6 (M): `UI/Alerts.lua` options section; locales; TOC. Verify: `test_locale_files`, `test_load`; in game
- [x] T7 (S): docs (doc.md, README, CHANGELOG, docs/status.md, INDEX). Verify: read

## Review Focus (failure modes a happy-path test would miss)
1. RF1: item not cached on first open -> name white, item level blank and sorted last, then coloured/filled after
   GET_ITEM_INFO_RECEIVED without a refresh storm (debounced). Pinned by: T1 (nil-last sort), T5 (debounce)
2. RF2: saved settings corrupted / from a future version (`recipeColumns = "x"`, `recipeSort.key = "foo"`,
   `windowSize = { width = 1e9 }`) -> defaults/clamped. Pinned by: T1
3. RF3: all optional columns off -> Name fills the whole width; very narrow width -> Name keeps its minimum. Pinned by: T1
4. RF4: window resized while scrolled to the bottom -> offset clamped, no empty rows at the top, slider range updated. Pinned by: T4 (READ-ONLY + in game)
5. RF5: peer-supplied recipe names stay escaped inside the colour code (no markup injection). Pinned by: T2 test

## Cross-cutting checklist (answer every line; "n/a: reason" is fine)
- [x] Protocol: unchanged; nothing is sent.
- [x] Stored data: `Store.SCHEMA` unchanged (5); new optional keys in `ui` are local, read through validators that fall back to defaults; older versions ignore them.
- [x] Trust model: recipe names still come from `Model` escaped; the colour code wraps the escaped text; numbers come from the viewer's own client.
- [x] Localization: column titles and options via `Text[...]`; quality/levels are numbers from the client; nothing stored as display text.
- [x] Load order: `Core/View/RecipeTable.lua` after `Core/View/Model.lua` (pure, uses Utility only); `UI/Table.lua` before `UI/Window.lua`.
- [x] Packaging: new files are under `Core/` and `UI/`, which `tools/package.ps1` already ships; `features/` stays excluded.
- [x] Tests: `tests/test_recipe_table.lua`: corrupted settings, all columns off, narrow width, nil-last both directions, escaped names.
- [x] Docs: README (Recipes tab, resize), CHANGELOG, docs/status.md, doc.md.

## Decisions (user answers and design choices, newest last)
- 2026-11-18: Column toggles live in the options panel (`/ts options`, Options button), one checkbox per column (user).
- 2026-11-18: Default sort item level, highest first; header click re-sorts; option picks the saved sort (user).
- 2026-11-18: Columns: Item level, Required level, Profession, Skill, Category; Name always shown; no Crafters column (user).
- 2026-11-18: TalentShare-local resizable list (`UI/Table.lua`) instead of changing LibGuildSync's list, so GuildGames is untouched (design).
- 2026-11-18: Header click and the option share one saved sort value, so there is one source of truth (design).

## Open questions
- none

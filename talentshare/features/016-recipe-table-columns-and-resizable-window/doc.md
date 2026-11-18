# 016 Recipe table columns and resizable window

## What it does
- The Recipes list is a table. Name (icon + recipe name in the crafted item's quality colour) is always shown; the
  optional columns are Item level, Req. level (required character level), Profession, Skill (profession skill the
  recipe needs) and Category.
- Default order: item level, highest first. Recipes without an item (enchants) or whose item data is not loaded yet
  have empty cells and are always listed last. Ties sort by name.
- Click a column title to sort by it (numbers highest first, text A-Z); click it again to flip. A small arrow marks the
  sorted column.
- The main window has a grip at the bottom right. Drag it to resize (minimum = the old 780 x 520, maximum = screen).
  All tab lists grow; the recipe detail panel keeps its width at the right. The size is remembered.

## How to use
- `/ts options` (or the Options button) -> section "Recipe list": one checkbox per column (any combination), "Sort by"
  cycles the sort column, the direction button flips it. Changes apply to the open window at once.

## How it works
- `Core/View/RecipeTable.lua` (pure): column list, settings get/set with validation, layout (fixed widths, Name takes
  the rest, minimum 140 px), sort (missing values last), quality colour fallback, window size clamp.
- `Core/View/Model.lua`: `BuildRecipeRows` adds `quality`, `itemLevel`, `requiredLevel`, `skill`, `categoryLabel`.
- `Core/Game/Api.lua`: `Api.ItemDetails` (C_Item.GetItemInfo; requests the load when uncached), `Api.QualityHex`
  (`ITEM_QUALITY_COLORS`, else the standard colours).
- `UI/Table.lua`: resizable scroll list (rows created on demand on size change), header, table rows.
  LibGuildSync's fixed-size list is unchanged (GuildGames uses it).
- Item data that arrives later (`GET_ITEM_INFO_RECEIVED`) redraws the Recipes table at most once a second.
- Saved (account-wide, local only, never sent) in `TalentShareDB.ui`: `recipeColumns` { [columnKey] = boolean },
  `recipeSort` { key, descending }, `windowSize` { width, height }. Invalid values fall back to defaults. No schema or
  protocol change.

## Limits / known issues
- No Crafters column; the "{n} crafters" text per row was removed (crafters are in the detail panel and the icon tooltip).
- Columns cannot be reordered or resized individually.
- Item level / required level / quality come from the viewer's client: empty until the client has loaded the item.
- The maximum window size is the screen size at the time the window is built (UI scale changes need a `/reload`).

## Localization
New texts (enUS keys, deDE translations): Name, Item level, Req. level, Profession, Skill, Recipe list, the options hint,
Sort by, Descending, Ascending. Removed: "{n} crafter", "{n} crafters".

## Verification
See [verify.md](verify.md): pure logic OFFLINE (`tests/test_recipe_table.lua`, 11 tests); everything on screen still
NOT-VERIFIED in game.

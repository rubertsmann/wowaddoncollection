# Item categories and text search

Status: verifying | Since version: 0.5.0 | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
The Recipes tab can be narrowed down by what a recipe makes: a dropdown picks the profession, a category menu with
checkboxes picks item kinds (head, chest, feet ..., food, armor kits, leather, ...), and the search box takes free text,
also matching the item's effect and stats ("Beweglichkeit" finds agility food and gear).

## How to use
- Profession dropdown: "All" or one profession. Changing it clears the categories.
- **Category**: tick one or more; a recipe that matches any ticked category is shown. "Show all" clears. The button
  shows how many are ticked.
- Search: words in any order, case and accents ignored; every word has to appear in the name, a reagent, the category
  or the item's tooltip text.

## How it works
- `Model.CategoryKey(classID, subClassID, equipLoc)`: armor by slot (`slot:INVTYPE_HEAD`, robe = chest), everything
  else by class and subclass (`class:0:5` = food); no item -> `none`. `Model.RecipeCategories` lists the categories of
  the current profession with counts.
- Item data from the viewer's client: `C_Item.GetItemInfoInstant` (no server query), names from
  `C_Item.GetItemClassInfo/GetItemSubClassInfo` and `_G[equipLoc]` (`Core/Api.lua`).
- Effect text: `Core/ItemText.lua` reads `C_TooltipInfo.GetItemByID` (fallback hidden GameTooltip), cleans it with
  `Model.TooltipSearchText` and caches it in `db.itemText` (this client only, per language, 400 bytes per item). It is
  read 8 items per 0.2 s while the Recipes tab is open; items the client has not loaded are requested and retried.
- Data: `db.itemText` only; no message change. Nothing new is sent.
- Without the menu templates the controls fall back to cycle buttons.
- Dev only: `UI/DevProbe.lua` (Debug tab "Item probe", `/tsd itemprobe`) records client item data to the dev SavedVariables.

## Localization
Category names come from the client in its language; new labels in `Locales/deDE.lua`.

## Limits and known issues
- A recipe whose catalog entry has no `produces` (enchantments, entries from very old scans) is in "Other".
- Effect text appears a moment after the first search on a fresh cache.

## Changelog line
- Recipes tab: profession dropdown, category filter with checkboxes (slot, food, ...), free-text search that also matches item effects and stats.

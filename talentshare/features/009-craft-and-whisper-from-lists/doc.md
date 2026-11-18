# Craft and whisper from lists

Status: verifying | Since version: 0.5.0 | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
On the Orders tab a **Craft** button opens the profession of the selected order with the ordered recipe selected, and the
next click crafts the ordered quantity. On the Recipes, Orders and Available tabs the icon of a row shows the recipe (or
item) on hover, and a click opens a whisper with the link already typed in.

## How to use
- Orders tab: select an order you can craft -> **Open profession** -> **Craft Nx**.
- Recipes tab: hover the icon (crafted item, reagents); click it to whisper the best crafter. Clicking a crafter in the detail panel also inserts the link.
- Orders tab: click the icon to whisper the requester (on your own order: the crafter who claimed it) with `link xN`.
- Available tab: click the icon to whisper the owner with the item link.

## How it works
- Data (SavedVariables): no change. Messages: no change.
- `Core/Model.lua`: `CraftTarget`, `OrderContact`, `RecipeContact`, `ChatText` (pure, `tests/test_craft_whisper.lua`).
- `Core/Api.lua`: `RecipeLink`, `ItemLink`, `OpenProfessionName`, `SelectRecipe` (`C_TradeSkillUI.OpenRecipe`), `CraftRecipe` (`C_TradeSkillUI.CraftRecipe`).
- `Core/Events.lua`: TRADE_SKILL_SHOW/CLOSE set `Api.open.tradeskill` and fire `TRADESKILL`.
- `UI/Window.lua`: icon button in `makeSelectableRow`, `recipeTooltip`, `whisper(name, text)`, secure Craft button (macro `/cast <profession>` while the window is closed, craft call while it is open).

## Localization
New UI strings in `Locales/deDE.lua`. Links are built by the viewer's client; a peer's recipe name only ever appears as plain `[Name]` with `|` removed.

## Limits and known issues
- Opening a profession needs a real click (Forever blocks addons), hence two clicks.
- Whether `CraftRecipe` from an addon click works on Forever is not verified; if it does not, the recipe stays selected and the game's Create button crafts it.
- The secure button is not updated in combat (updated when combat ends).

## Changelog line
- Orders tab: Craft button (open the profession with the recipe selected, then craft the ordered quantity); list icons show the recipe on hover and whisper with the link on click.

# 009 Craft and whisper from lists: spec

- Status: verifying
- Created: 2026-11-16
- Target version: 0.5.0 (UI only, no protocol/schema change)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
From the Orders tab, open the right profession with the ordered recipe selected and craft it; on the Recipes and Orders
tabs, hovering a row's icon shows the recipe and clicking it whispers the right person with the recipe link in the message.

## Requirements
- R1: Orders tab has a **Craft** button for the selected order, enabled only when I know the recipe and the order is open/claimed by me.
- R2: When the order's profession window is not open, the button is a real (secure) click that opens it (`/cast <profession>`, same macro as the scan buttons); when it opens, the ordered recipe is selected in the profession window.
- R3: When that profession window is open, the button crafts the order's quantity (`C_TradeSkillUI.CraftRecipe(recipeID, qty)`); if the client refuses, the recipe stays selected so the game's own Create button works, and the failure is logged.
- R4: In combat the secure button is not reconfigured (taint-free); it is brought up to date after combat.
- R5: Recipes tab and Orders tab: hovering a row's icon shows the recipe: the crafted item's tooltip when the recipe produces an item, otherwise its name, plus its reagents (counts).
- R6: Clicking a row's icon opens a whisper with the recipe link already in the message:
  Recipes tab -> the best crafter who is not me (Store.Crafters order: highest rank first); Orders tab -> the requester, or, on my own order, the first claimer; the order message includes the quantity (`<link> x3`).
- R7: Crafter lines in the Recipes detail panel (already "click to whisper") also insert the recipe link.
- R8: The link is built by THIS client only (own recipe link, else the produced item's link, else `[Name]` with every `|` removed): nothing a peer sent becomes a hyperlink or escape code in chat.
- R9: Available tab: the icon keeps showing the item tooltip (the icon becomes its own button, so the row's tooltip would be lost otherwise); clicking it whispers the owner with the item link.

## Non-goals
- Crafting from the Recipes tab or for recipes I do not know.
- Opening a profession without a real click (blocked on Forever, docs/api-findings.md).
- Marking the order done automatically after crafting (the crafter still trades the item and presses "Mark done").

## Design
- `Core/Model.lua` (changed, pure): `Model.CraftTarget(store, me, recipeID, live)` -> own profession row (for `CastMacro`) or nil, why; `Model.OrderContact(row, me)`; `Model.RecipeContact(crafters, me)`; `Model.ChatText(link, name, qty)`.
- `Core/Api.lua` (changed): `Api.RecipeLink(recipeID, produces)`, `Api.CraftRecipe(recipeID, qty)`, `Api.SelectRecipe(recipeID)`, `Api.OpenProfessionName()`; `Api.open.tradeskill`.
- `Core/Events.lua` (changed): TRADE_SKILL_SHOW / TRADE_SKILL_CLOSE set `Api.open.tradeskill`, fire `TRADESKILL` (UI selects the pending recipe and refreshes the Craft button).
- `UI/Window.lua` (changed): icon button in `makeSelectableRow` (`r.onIconEnter`, `r.onIconClick`), recipe tooltip, `whisper(name, text)`, secure Craft button on the Orders tab, PLAYER_REGEN_ENABLED refresh.
- Data shape change: none. Message shape change: none.

## Tasks
- [x] T1 (S): Model helpers + tests `tests/test_craft_whisper.lua`. Verify: `craft: *`, `whisper: *` tests
- [x] T2 (S): Api wrappers + Events tradeskill state. Verify: `load: all TOC files run ...`
- [x] T3 (M): icon button, recipe tooltip, whisper with link (Recipes, Orders, detail crafters, Available). Verify: in game (verify.md)
- [x] T4 (M): secure Craft button (open+select / craft), combat handling. Verify: in game (verify.md)
- [x] T5 (S): locale deDE, CHANGELOG, doc.md. Verify: locale test

## Review Focus (failure modes a happy-path test would miss)
1. RF1: recipe name from a peer containing `|H...|h` or `|T...|t` -> never inserted raw in chat; `|` removed. Pinned by: `whisper: a peer recipe name cannot inject a link`
2. RF2: my own order with no claimer / recipe whose only crafter is me -> no whisper to myself (nothing happens, short hint). Pinned by: `whisper: never to myself`
3. RF3: Craft button clicked while ANOTHER profession window is open -> `/cast` switches to the right one (no craft of a wrong recipe). Pinned by: UI only crafts when `OpenProfessionName() == target.spellName`; READ-ONLY + in game.
4. RF4: combat -> no SetAttribute/Show/Hide on the secure button. Pinned by: code (`InCombat` guard); READ-ONLY.
5. RF5: a recipe I know in a profession that is not in my live spellbook list (stale record) -> button disabled, no empty macro. Pinned by: `craft: no target without a live profession`

## Cross-cutting checklist
- [x] Protocol: unchanged (no message change).
- [x] Stored data: unchanged, schema 3.
- [x] Trust model: links only from this client (R8); names already pass `Util.IsSafeName`; whisper target via `Util.WhisperTarget`.
- [x] Localization: new strings through `L` with deDE.
- [x] Load order: no new file.
- [x] Packaging: no new file.
- [x] Tests: `tests/test_craft_whisper.lua`.
- [x] Docs: CHANGELOG, README (Orders tab), doc.md.

## Decisions
- 2026-11-16: User asked "is it possible ... and I want ..."; implemented without a separate plan round, defaults below logged as assumptions.
- 2026-11-16: Icon click target: Recipes -> highest-rank crafter that is not me; Orders -> requester, or first claimer on my own order. Row click keeps selecting.
- 2026-11-16: One Craft button, two modes (open+select / craft) instead of crafting on the first click: the profession must be open to craft, and addons cannot open it.
- 2026-11-16: No version bump now: the TOC is bumped when releasing.
- 2026-11-16: R9 (Available tab icon) added: the icon becoming its own button would otherwise swallow the row tooltip there; the whisper click is the same behaviour as the other tabs.

## Open questions
- Does `C_TradeSkillUI.CraftRecipe` work from an addon button click on Forever, and does `C_TradeSkillUI.OpenRecipe` select the recipe? (needs: game)

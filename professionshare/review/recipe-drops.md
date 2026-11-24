# Review: recipe drop alerts, dev tools menu, grouped settings page

Date: 2026-11-24 · Scope: uncommitted change for features 026 (RecipeCheck, Dev tools, Api tooltip/bag helpers), 027
(RecipeDrops, Drops, Sync `DROP`/`DROPA`, protocol 2.7) and 029 (settings page) · Method: code read plus the offline suite
(310 passed) and the in-game evidence in the features' `verify.md` (single client, fake triggers). Two-member traffic is
NOT verified.

## Checklist results

| # | Check | Result |
|---|---|---|
| 1 | Secrets | none in the diff; no new untracked artifacts besides the feature folders and tests |
| 2 | Inbound gate | `DROP`/`DROPA` arrive through `Channel.OnAddonMessage` -> `Guard.Accept` like every type: GUILD, or WHISPER from a roster member |
| 3 | Input validation | `RecipeDrops.SanitizeDrop` (item 1..10 000 000 integer), `SanitizeAnswer` (item, `s` "g"/"r", `r` 0..1000); a handler error rejects the message; answers stored only for my own drops of the last 15 min (max 20 drops) |
| 4 | Display | answerer names: `Utility.Escape` in the tooltip (`HintRows`), `Utility.ChatSafe` in chat lines and the `|Hplayer:` link, `Escape(ShortName)` in the minimap tooltip; item names and links come from the viewer's own client |
| 5 | Version compatibility | additive minor 2.7; a 2.6 peer drops `DROP`/`DROPA` as unknown types (test `recipe drops sync (RF2)`); no stored shape change (`ui.drops` settings only) |
| 6 | Persistence | `RecipeDrops.Get` type-checks stored values (wrong type -> default); dev-only `devFake`/`devChecks` are never read back except `devFake` names (kept-names set) |
| 7 | Resource bounds | drops 20, alerts 10, duplicate table pruned on every call; answers per drop bounded by the roster |
| 10 | WoW specifics | no secure frames touched; tooltip and chat-hover hooks are `HookScript`/`AddTooltipPostCall` wrapped in `Log.Protected` |
| 11 | Tests | `test_recipe_check.lua`, `test_recipe_drops.lua`, `test_load.lua` drop/dev/settings blocks |

## Findings

### D1. A DROP for a non-recipe item could raise "you can learn it" (Low) — FIXED in this change
`Drops.OnDrop` read any announced item's tooltip. Crafted gear can carry its own "Requires <profession> (n)" line
(engineering goggles), so a DROP for such an item (an old or buggy peer, or a guild member's mistake) made receivers
alert and answer. Fix: `Core/Game/Drops.lua` `OnDrop` requires `Api.ItemClass(itemID) == Offers.RECIPE_CLASS` before
anything else (status `notRecipe`). Regression: `test_load.lua` "not a recipe ... no answer, no alert".

### D2. No rate limit on incoming DROP (Info, accepted)
The user decided "no limit". A guild member can make every online member read tooltips and whisper answers by sending
many DROPs with different ids. Within the trust model (guild members are trusted) and bounded by the sender's token
bucket; non-guild senders are gated. The same sender+item within 60 s is ignored.

### D3. Any guild member can answer for my drop (Info, accepted)
`DROPA` is accepted from any gated sender, without checking that it answers a DROP that sender received. It only adds a
name to my own tooltip; trusted by the trust model.

### D4. Real character names in the dev SavedVariables (Info)
`devChecks.request` stores my own name as the realm request asked it; `lootLines` strip other players' names. The dev
SavedVariables are local and never committed; keep evidence copied into `features/*/evidence` free of names.

## Priority table

| ID | Severity | Status | Action |
|---|---|---|---|
| D1 | Low | fixed in this change | none |
| D2 | Info | accepted (user decision) | revisit if spam is reported |
| D3 | Info | accepted (trust model) | none |
| D4 | Info | rule | no names in committed evidence |

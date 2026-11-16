# 009 Craft and whisper from lists: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> 170 passed, 0 failed
Result after work:    `luajit tests/run.lua` -> 178 passed, 0 failed (mutation: ChatText without stripping -> 1 FAIL)

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence | Result | Date |
|---|---|---|---|---|---|---|
| R1 | Craft button enabled only for known, live orders | `craft: order rows say whether I can craft them`, `craft: no target for a recipe I do not know`; button in game: checklist 1 | OFFLINE + IN-GAME | test run; user "crafting menu works" | pass | 2026-11-16 |
| R2 | first click opens profession, recipe selected | checklist 2 | IN-GAME | user report after the OpenWindowHasRecipe fix | pass | 2026-11-16 |
| R3 | second click crafts qty; fallback message | checklist 3 | IN-GAME | TalentShare-Dev.lua debug log: `craft.start 2544 1 ok` (x30+), `craft.start 6499 1 ok`, `craft.start 2149 1 ok`; user "crafting menu works" | pass | 2026-11-16 |
| R4 | no secure changes in combat | `refreshCraft` returns on `InCombat`; PLAYER_REGEN_ENABLED refresh | READ-ONLY | UI/Window.lua refreshCraft | | 2026-11-16 |
| R5 | icon hover shows recipe | checklist 4 | NOT-VERIFIED | needs game | | |
| R6 | icon click whispers the right person with link | `whisper: never to myself`, `whisper: the recipe crafter is the highest rank that is not me`; checklist 5 | OFFLINE (target) / NOT-VERIFIED (chat) | test run | pass | 2026-11-16 |
| R7 | detail crafter lines insert link | checklist 6 | NOT-VERIFIED | needs game | | |
| R8 | links only from this client | `whisper: a peer recipe name cannot inject a link`, `whisper: a local link is used as is ...` | OFFLINE | test run, mutation 1 FAIL | pass | 2026-11-16 |
| R9 | Available icon tooltip + whisper | checklist 7 | NOT-VERIFIED | needs game | | |
| RF1 | peer name injection | `whisper: a peer recipe name cannot inject a link` | OFFLINE | test run | pass | 2026-11-16 |
| RF2 | never whisper myself | `whisper: never to myself` | OFFLINE | test run | pass | 2026-11-16 |
| RF3 | other profession open -> no wrong craft | craft mode only when `Api.OpenProfessionName() == target.spellName`; checklist 8 | READ-ONLY | UI/Window.lua refreshCraft | | 2026-11-16 |
| RF4 | combat | as R4 | READ-ONLY | | | 2026-11-16 |
| RF5 | stale profession -> disabled | `craft: no target without a live profession` | OFFLINE | test run | pass | 2026-11-16 |

## In-game checklist (things only the user can do; `/console scriptErrors 1` first)
- [x] 1. Orders tab, select an order for a recipe you know: **Open profession** is enabled; for one you do not know: **Craft** is greyed out.
- [x] 2. Click **Open profession**: the profession window opens with the ordered recipe selected; the button now reads **Craft 2x** (order quantity).
- [x] 3. Click **Craft 2x** with the reagents in the bags: the character crafts 2. If not: does chat say "Could not start crafting..."? `/ts export` and send the `craft.` lines of the debug log.
- [ ] 4. Hover a recipe icon on the Recipes and Orders tabs: tooltip of the crafted item, recipe name, reagents with "have n".
- [ ] 5. Click a recipe icon (Recipes tab): a whisper to the best crafter opens with the recipe link typed in; Orders tab: to the requester (own order: the claimer) with "link x<qty>".
- [ ] 6. Recipes tab detail panel: click a crafter: whisper with the recipe link.
- [ ] 7. Available tab: icon hover shows the item, icon click whispers the owner with the item link.
- [ ] 8. With ANOTHER profession window open, select an order: the button says **Open profession**, a click switches to the right profession.

## Accepted gaps
- none yet

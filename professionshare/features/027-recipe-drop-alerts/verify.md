# 027 Recipe drop alerts: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> 302 passed, 0 failed
Result after work:    `luajit tests/run.lua` -> 310 passed, 0 failed

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence (output line, file, screenshot) | Result | Date |
|---|---|---|---|---|---|---|
| R1 | my loot -> in bags -> DROP; bind on pickup not | test_load drop block ("announced,bound", 1 broadcast) | OFFLINE | 310 passed | pass | 2026-11-24 |
| R1 | a real recipe drop on Forever | loot a tradeable recipe | NOT-VERIFIED | needs user + a drop | | |
| R2 | receiver decides from own tooltip, answers g/r | test_load (learnable -> "g" 150); test_recipe_drops "answer status..." | OFFLINE | 310 passed | pass | 2026-11-24 |
| R2 | on Forever | Dev tools -> "Recipe drop from a member", devChecks.dropIn from WTF | IN-GAME | item 273098: status learnable, answer s=g r=144 (captured), alert 1; log "drops.incoming ... answer=g" | pass | 2026-11-24 |
| R3 | alert chat line + minimap icon, cleared on open | test_load (alert stored, WINDOW_OPENED clears) | OFFLINE | 310 passed | pass | 2026-11-24 |
| R3 | look in game | user clicked through the triggers | IN-GAME | user: "clicked a lot"; no warnings or errors in the saved log | pass (no screenshot) | 2026-11-24 |
| R4 | tooltip list: green first, skill, max 3, "..." | test_recipe_drops "hint rows..."; test_load tooltip lines | OFFLINE | 310 passed | pass | 2026-11-24 |
| R4 | bag / chat link hover in game | Dev tools -> "Answers to my recipe drop", devChecks.dropMine | IN-GAME | rows Fake Cook 300, Fake Alchemist 280, Fake Skinner 265 (green), more=1 | pass | 2026-11-24 |
| R5 | switches + /ps drops | test_recipe_drops "settings..."; test_load (/ps drops chat off) | OFFLINE | 310 passed | pass | 2026-11-24 |
| R6 | duplicates within 60 s ignored | test_recipe_drops "the same DROP..." | OFFLINE | 310 passed | pass | 2026-11-24 |
| R7 | dev triggers | test_load (dropin learnable/g, dropmine 3 rows + 1 more, removed by Remove all fake data) | OFFLINE | 310 passed | pass | 2026-11-24 |
| RF1b | DROP for a non-recipe item (review D1) | test_load "not a recipe ... no answer, no alert" | OFFLINE | 310 passed | fixed | 2026-11-24 |
| RF1 | hostile DROP / DROPA | test_recipe_drops "(RF1)..." x2, sync test ("error", "ignored") | OFFLINE | 310 passed | pass | 2026-11-24 |
| RF2 | 2.6 peer drops DROP | test_recipe_drops "(RF2)..." | OFFLINE | 310 passed | pass | 2026-11-24 |
| RF3 | names escaped | test_recipe_drops "hint rows... (RF3)" | OFFLINE | 310 passed | pass | 2026-11-24 |
| RF4 | item not loaded -> retried, then silent | Drops.ReadRecipe (3 tries); test_recipe_check api test (nil, no error) | OFFLINE / READ-ONLY (retry timer) | 310 passed | pass | 2026-11-24 |
| RF5 | share off -> no DROP, no answer | test_load (OnLootLine nil, OnDrop "off") | OFFLINE | 310 passed | pass | 2026-11-24 |
| - | two members: DROP, alert, DROPA, tooltip at the looter | two guild members on this build | NOT-VERIFIED | needs user + second player | | |

## In-game checklist (things only the user can do)
- [ ] `powershell tools/deploy.ps1` (done by Claude), **restart the game** (new files), `/console scriptErrors 1`.
- [ ] `/psd drops`: "Recipe drops: share on, chat on, minimap icon on".
- [ ] Recipe items in the bags (one learnable). Dev tools -> "Recipe drop from a member": chat line "... dropped for [Fake Looter]: you can learn it (your skill N)" and the minimap icon turns into the letter; hover the minimap button: the drop is listed. Open the window: the icon is back to normal.
- [ ] Dev tools -> "Answers to my recipe drop": hover the item in the bags and the link in the chat line: "Guild members who can use it:", Fake Cook (300), Fake Alchemist (280), Fake Skinner (265) in green, "... and 1 more".
- [ ] `/psd drops chat off`, repeat "Recipe drop from a member": no chat line, icon still. `/psd drops chat on`.
- [ ] Dev tools -> "Remove all fake data": the fake answers are gone from the tooltip.
- [ ] `/reload`, tell Claude (reads devChecks.dropIn / dropMine).
- [ ] With a second member on this build: one of you loots a tradeable recipe the other can learn.

## Accepted gaps
- R1 a real recipe drop, and the two-member row: not seen yet.
- 2026-11-24, user ("check everything commit then finalize"): the remaining NOT-VERIFIED rows above are accepted; they
  stay listed and are checked when they happen in play.

# 026 Debug fake data menu and recipe probe: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> 295 passed, 0 failed
Result after work:    `luajit tests/run.lua` -> 302 passed, 0 failed

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence (output line, file, screenshot) | Result | Date |
|---|---|---|---|---|---|---|
| R1 | one Dev tools menu, /psd fake | test_load dev block (unique keys, sections, RunEntry, /psd fake list) | OFFLINE | 301 passed | pass | 2026-11-24 |
| R1 | menu look in game | in-game checklist | IN-GAME | user: "did that - looks fine" | pass | 2026-11-24 |
| R2 | one fake-member helper, survives reload | test_load (devFake roles, RestoreFakeMembers) | OFFLINE | 301 passed | pass | 2026-11-24 |
| R3 | remove all fake data, nothing else | test_load ("Fake Person" and my record kept) | OFFLINE | 301 passed | pass | 2026-11-24 |
| R4 | recipe probe reads own tooltip | test_recipe_check (reading, decision, api colours) | OFFLINE | 301 passed | pass | 2026-11-24 |
| R4 | real tooltips on Forever: Requires line, red colour, BoP | recipe probe in game (deDE), devChecks.recipes read from WTF ProfessionShare-Dev.lua | IN-GAME | 5 items: 1 learnable (Kürschnerei 140, mine 144, white), 2 low (Kochkunst 175/200, mine 150, red 1/0.13/0.13), 2 noProfession (Alchimie, red); BoP read on 3; 0 mismatches, 0 unreadable | pass | 2026-11-24 |
| R4 | "Already known" on Forever | recipe probe with a recipe I already know | NOT-VERIFIED | no known recipe was in the bags | | |
| RF1 | requirement line order on Forever | same probe | IN-GAME | created item first, recipe's "Benötigt <Beruf> (n)" LAST (after the reagents); the first-line rule was wrong -> changed to last line | fixed | 2026-11-24 |
| R5 | loot recorder tells mine from others | test_recipe_check "(RF4)..."; test_load loot lines | OFFLINE | 301 passed | pass | 2026-11-24 |
| R5 | real loot formats; simulated lines on Forever | devChecks.loot / lootOther / lootLines read from WTF | IN-GAME | "Ihr erhaltet Beute: <link>" -> self, wouldAnnounce=true; other -> kind other, name not stored; links use the new "|cnIQ2:" colour form, item id still parsed | pass | 2026-11-24 |
| R5 | a REAL recipe loot line and the bag timing | loot a recipe | NOT-VERIFIED | no real recipe dropped yet (all lines simulated) | | |
| R6 | fake recipe loot runs the same path | test_load SimulateRecipeLoot("other"); in game both triggers | OFFLINE + IN-GAME | devChecks.loot.ok, lootOther.ok | pass | 2026-11-24 |
| R7 | results readable from disk | test_load (devChecks keys, lootOther, recipes) | OFFLINE | 301 passed | pass | 2026-11-24 |
| RF1 | only the last Requires line | test_recipe_check "(RF1)...", "a real Forever tooltip..." | OFFLINE | 302 passed | pass | 2026-11-24 |
| RF2 | German and positional formats | test_recipe_check "(RF2)...", "patterns from client format strings..." | OFFLINE | 301 passed | pass | 2026-11-24 |
| RF3 | item not loaded | test_recipe_check api test (nil, no error); probe retries after 3 s | OFFLINE / READ-ONLY (retry) | 301 passed | pass | 2026-11-24 |
| RF4 | other players' loot never mine | test_recipe_check "(RF4)..." | OFFLINE | 301 passed | pass | 2026-11-24 |
| RF5 | real "Fake..." member kept | test_load remove block | OFFLINE | 301 passed | pass | 2026-11-24 |

## In-game checklist (things only the user can do)
- [x] `powershell tools/deploy.ps1` (done by Claude), **restart the game** (new file), `/console scriptErrors 1`.
- [x] `/psd debug` -> Debug tab: one "Dev tools" dropdown left of "Export report"; it shows Members / Triggers / Probes / Cleanup.
- [x] Put 2-3 recipe items in your bags (one you can learn, one too high, one of another profession; one you already know if you have it). Dev tools -> "Recipes in my bags".
- [x] Dev tools -> "Recipe loot (me)" and "Recipe loot (other player)": after ~10 s a "loot line ..." chat line each.
- [ ] If possible: loot a real recipe (or have a group member loot one near you).
- [~] Dev tools -> Members (any), then "Remove all fake data" (ran; removed 0: no member had been added): the chat lists what was removed.
- [x] `/reload`, then tell Claude: it reads `devChecks` from `WTF\Account\<ACCOUNT>\SavedVariables\ProfessionShare-Dev.lua`.

## Accepted gaps
- "Already known" (R4) and a REAL recipe loot line (R5): not seen yet.
- 2026-11-24, user ("check everything commit then finalize"): the remaining NOT-VERIFIED rows above are accepted; they
  stay listed and are checked when they happen in play.

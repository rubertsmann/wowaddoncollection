# 039 Rope needs a fight instead of range: verification

Levels: `OFFLINE` | `IN-GAME` | `MULTI-CLIENT` | `READ-ONLY` | `NOT-VERIFIED`.

Baseline before work: `luajit tests/run.lua` -> 193 passed, 0 failed (4 new assertions failing after the tests were written)
Result after work:    `luajit tests/run.lua` -> 193 passed, 0 failed

| ID | Requirement / Review Focus | How verified | Level | Evidence | Result | Date |
|---|---|---|---|---|---|---|
| R1 | no CheckInteractDistance call | `grep -rn CheckInteractDistance Core UI` -> no hit | OFFLINE | grep output empty | pass | 2026-11-26 |
| R1b | no more `caught.blocked` in combat | fight several enemies with the icon on | NOT-VERIFIED | needs user, in game | - | |
| R2 | throw / trap refuse `nofight`, nil allowed | test_azecaught "a throw needs low health...", test_items "traps catch..." | OFFLINE | 193 passed | pass | 2026-11-26 |
| R3 | icon greyed when not fighting | emulator run nofight/fight (table below) | OFFLINE (emulator) | alpha 0.5 + desaturated vs alpha 1 | pass | 2026-11-26 |
| R4 | hide on dead / health 0 | test_load IconHiddenReason "health 0 with a hidden dead flag" | OFFLINE | 193 passed | pass | 2026-11-26 |
| R5 | hide after a failed throw, also after 60 s | test_azecaught `Tried` after ExpireThrows; test_load "a failed throw hides the icon" | OFFLINE | 193 passed | pass | 2026-11-26 |
| RF1 | threat unknown -> allowed | test_azecaught "fighting unknown: allowed" | OFFLINE | 193 passed | pass | 2026-11-26 |
| RF2 | Second Chance -> icon back | test_item_batch "Second Chance: the icon comes back" | OFFLINE | 193 passed | pass | 2026-11-26 |
| RF3 | armed throw keeps the icon | test_azecaught + test_load "an armed throw keeps the icon" | OFFLINE | 193 passed | pass | 2026-11-26 |
| RF4 | pet tanks -> greyed | reasoned | READ-ONLY | - | accepted design | |

## Emulator runs (wow-ui-sim v0.1.41, Forever UI, faked unit API: a hostile "Testwolf" target at 20 %, target frame mode)
Not the game: no server, no combat lockdown, no taint, so it cannot show the block is gone. Script: [evidence/sim-scenario.lua](evidence/sim-scenario.lua) (MODE nofight | fight | dead; `CheckInteractDistance` replaced by a trap that reports any call).

| Case | Icon | Throw binding (chat) | CheckInteractDistance called | Date |
|---|---|---|---|---|
| load only | - | - | - (0 Lua errors in GuildGames) | 2026-11-26 |
| nofight (UnitThreatSituation nil) | shown, alpha 0.5, greyed true | "It is not fighting you: attack it first." | no | 2026-11-26 |
| fight (UnitThreatSituation 1) | shown, alpha 1, greyed false; armed after the throw | "Rope thrown at Testwolf: kill it within 3 seconds!" | no | 2026-11-26 |
| dead (UnitIsDead true, health 0) | hidden | "It is already dead." | no | 2026-11-26 |
| failed throw, icon stays gone | not run: the emulator's C_Timer did not fire within the run | - | - | - |

Screenshot: [evidence/sim-icon-nofight-vs-fight.png](evidence/sim-icon-nofight-vs-fight.png) (top not fighting: faded; bottom fighting, after the throw: net icon, gold ring). The rope picture itself does not render in the emulator.

## In-game checklist
- [ ] `/reload`, fight 3-4 enemies with nameplates on: no "blocked" chat line, `/gg debug` shows no new `caught.blocked`.
- [ ] Target an enemy you have not hit: rope icon greyed, click says "It is not fighting you". Hit it: icon in colour.
- [ ] Throw, kill too slow: icon gone and stays gone on the living enemy after a minute.

## Accepted gaps
- none yet

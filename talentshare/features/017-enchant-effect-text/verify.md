# 017 Enchant effect text: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` | `READ-ONLY` | `NOT-VERIFIED`.

Baseline before work: `luajit tests/run.lua` -> `229 passed, 0 failed`
Result after work:    `luajit tests/run.lua` -> `231 passed, 0 failed`

| ID | Requirement / Review Focus | How verified | Level | Evidence | Result | Date |
|---|---|---|---|---|---|---|
| R1 | Tooltip shows the effect | dev build, Fake enchanter, hover | IN-GAME | user report 2026-11-18: "seems to be working correctly" | pass | 2026-11-18 |
| R2 | Detail line shows the effect | dev build, select an enchant | IN-GAME | same user report | pass | 2026-11-18 |
| R3 | Search finds enchants by effect | `search: an enchant is found by its effect text...` | OFFLINE | suite 231 passed | pass | 2026-11-18 |
| R4 | Local read, nothing sent, logged | code: no Communication/Store writes; log line `window.effectProbe` | READ-ONLY | - | which source works is not yet read from the log | 2026-11-18 |
| R5 | Dev fake enchanter survives prune | `prune: a name in Store.keptNames survives...`; button in game | OFFLINE + IN-GAME | suite; user report | pass | 2026-11-18 |
| RF1 | Spell not loaded yet | `Api.SpellDescription` requests the load | READ-ONLY | - | - | 2026-11-18 |
| RF2 | Item recipes never ask the spell | search test (`asked[1] == nil`) | OFFLINE | suite | pass | 2026-11-18 |
| RF3 | Escaped before display | `Utility.Escape` in tooltip and detail line | READ-ONLY | - | - | 2026-11-18 |
| RF4 | Exemption does not keep real leavers | prune test | OFFLINE | suite | pass | 2026-11-18 |

## In-game checklist
- [x] `/tsd` -> Debug -> Fake enchanter; Recipes -> Enchanting: enchants listed, hover shows the effect, detail line shows it (user, 2026-11-18).
- [ ] `/reload` after hovering, so the `window.effectProbe` lines name the working source (for docs/api-findings.md).
- [ ] Search "Beweglichkeit" / "agility" finds Enchant Cloak - Minor Agility (search R3 in game).

## Accepted gaps
- R4 source detail, R3 in game: accepted by the user on 2026-11-18 ("seems to be working correctly - add it").

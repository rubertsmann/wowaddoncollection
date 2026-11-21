# 017 Enchant effect text: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` | `READ-ONLY` | `NOT-VERIFIED`.

Baseline before work: `luajit tests/run.lua` -> `229 passed, 0 failed`
Result after work:    `luajit tests/run.lua` -> `231 passed, 0 failed`

| ID | Requirement / Review Focus | How verified | Level | Evidence | Result | Date |
|---|---|---|---|---|---|---|
| R1 | Tooltip shows the effect | dev build, Fake enchanter, hover | IN-GAME | 0.7.2 failed (0.7.2: log showed tools/reagents lines used as the effect for 5 of 6 enchants (TalentShare-Dev.lua, window.effectProbe 21:57:45); fixed, re-test needed); 0.7.3: all 6 enchants found their description (TalentShare-Dev.lua, window.effectText 22:12:05-10) | pass | 2026-11-18 |
| R2 | Detail line shows the effect | dev build, select an enchant | IN-GAME | same log as R1; user re-test "done" 2026-11-18 | pass | 2026-11-18 |
| R3 | Search finds enchants by effect | `search: an enchant is found by its effect text...` | OFFLINE | suite 231 passed | pass | 2026-11-18 |
| R4 | Local read, description only, nothing sent | log: description works once loaded (7771), tooltips hold tools/reagents | IN-GAME (source) | TalentShare-Dev.lua window.effectProbe lines | source found | 2026-11-18 |
| R5 | Dev fake enchanter survives prune | `prune: a name in Store.keptNames survives...`; button in game | OFFLINE + IN-GAME | suite; user report | pass | 2026-11-18 |
| RF1 | Spell not loaded yet | `Api.SpellDescription` requests the load | READ-ONLY | - | - | 2026-11-18 |
| RF2 | Item recipes never ask the spell | search test (`asked[1] == nil`) | OFFLINE | suite | pass | 2026-11-18 |
| RF3 | Escaped before display | `Utility.Escape` in tooltip and detail line | READ-ONLY | - | - | 2026-11-18 |
| RF4 | Exemption does not keep real leavers | prune test | OFFLINE | suite | pass | 2026-11-18 |

## In-game checklist
- [x] `/tsd` -> Debug -> Fake enchanter; Recipes -> Enchanting: enchants listed, hover shows the effect, detail line shows it (user, 2026-11-18).
- [x] `/reload` after hovering: the `window.effectProbe` lines named the working source (description; docs/api-findings.md).
- [x] 0.7.3 fix: Fake enchanter, hover each enchant (twice) and select one: real effect text (e.g. "Einen Umhang dauerhaft so verzaubern, dass er die Rüstung um 10 erhöht."), never "Werkzeuge: ..." or colour codes. `/reload` -> one `window.effectText` line per enchant.
- [ ] Search "Beweglichkeit" / "agility" finds Enchant Cloak - Minor Agility (search R3 in game).

## Accepted gaps
- R3 in game (search by effect): accepted by the user on 2026-11-18 (release requested); proven OFFLINE.

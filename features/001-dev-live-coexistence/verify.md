# 001 Dev live coexistence: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` | `READ-ONLY` | `NOT-VERIFIED`.

Baseline before work: `luajit tests/run.lua` -> 26 passed, 0 failed
Result after work:    `luajit tests/run.lua` -> 30 passed, 0 failed

| ID | Requirement / Review Focus | How verified | Level | Evidence | Result | Date |
|---|---|---|---|---|---|---|
| R1 | Dev folder loads as its own addon | AddOns listing shows `TalentShare-Dev` junction; generated TOC has own title/version/SV | READ-ONLY | deploy output + `TalentShare-Dev.toc` | files in place, loading not seen | 2026-11-16 |
| R2 | No shared state (SV, prefix, slash, frames) | `identity: dev build shares nothing with live` | OFFLINE | tests/test_identity.lua | pass | 2026-11-16 |
| R3 | Identity derived only in Init.lua | grep for `TShare`/`TalentShareDB` literals outside Init | OFFLINE | tests/test_identity.lua + grep (only Init.lua, TOC, probe) | pass | 2026-11-16 |
| R4 | deploy.ps1 links dev, removes old junction safely, `-InstallLive` guarded | ran the script; repo intact afterwards | READ-ONLY | script output; `-InstallLive` branch not executed | partly run | 2026-11-16 |
| R5 | Release zip unaffected | listed zip entries | OFFLINE | only `TalentShare\TalentShare.toc`, 18 entries | pass | 2026-11-16 |
| RF1 | Prefix <= 16 bytes | `identity: addon-message prefixes fit the 16 byte limit` | OFFLINE | test | pass | 2026-11-16 |
| RF2 | Junction removal never deletes repo files | script removed only the link; `Test-Path TalentShare.toc` true | IN-GAME? no: filesystem | output | pass | 2026-11-16 |
| RF3 | Live and dev never answer on one prefix | distinct-prefix test | OFFLINE | test | pass | 2026-11-16 |

## In-game checklist (things only the user can do)
- [ ] Start the game; AddOns list shows "TalentShare (dev)" (and "TalentShare" once the live zip is installed).
- [ ] `/tsd version` -> `v0.2.0-dev (protocol 1, prefix TShareDev)`; `/tsd` opens the window, its title reads "TalentShare (dev)".
- [ ] With live installed too: `/ts version` -> `v0.2.0 ...`, both windows open at once, two minimap buttons.
- [ ] `/tsd scan` works; `TalentShareDevDB.lua` appears in SavedVariables after /reload.

## Accepted gaps
- none yet

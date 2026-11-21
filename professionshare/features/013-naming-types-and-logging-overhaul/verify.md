# 013 Naming types and logging overhaul: verification

Levels: `OFFLINE` | `IN-GAME` | `MULTI-CLIENT` | `READ-ONLY` | `NOT-VERIFIED`.

Baseline before work: `luajit tests/run.lua` -> 204 passed, 0 failed
Result after work:    `luajit tests/run.lua` -> 209 passed, 0 failed

| ID | Requirement / Review Focus | How verified | Level | Evidence | Result | Date |
|---|---|---|---|---|---|---|
| R1 | full-word names | renamer leftover scan over Core/UI/Locales (only documented exceptions remain) | READ-ONLY | log.md | pass | 2026-11-17 |
| R2 | wire/saved/slash unchanged | test_sync, test_offers, test_hardening (wire), test_version_reset, test_core (saved), test_load (slash commands) | OFFLINE | 209 passed | pass | 2026-11-17 |
| R3 | annotations | code read | READ-ONLY | no LuaLS run (not installed) | open | 2026-11-17 |
| R4 | one logging helper | tests/test_log.lua (6 tests) | OFFLINE | 209 passed | pass | 2026-11-17 |
| R5 | failures logged | code read (Store.Migrate, Events, Communication, Api, Window, Alerts) | READ-ONLY | - | pass | 2026-11-17 |
| R6 | behaviour unchanged | full suite incl. test_load (all TOC files load, window builds) | OFFLINE | 209 passed | pass | 2026-11-17 |
| RF2 | log escaping | test_log "peer text is escaped" | OFFLINE | 209 passed | pass | 2026-11-17 |
| RF3 | log bounded | test_log "repeats are folded, the ring is bounded" | OFFLINE | 209 passed | pass | 2026-11-17 |
| RF4 | client-only code | in-game checklist below | NOT-VERIFIED | needs the user | open | |

## In-game checklist (things only the user can do)
- [ ] `powershell tools/deploy.ps1`, RESTART the game (TOC changed), `/console scriptErrors 1`, `/tsd`: no "not loaded" line, no Lua error, all four tabs work.
- [ ] Open a profession window, `/tsd scan`, `/tsd dump`; click a profession button; `/tsd debug 20` shows lines like `time LEVEL [area] message :: key=value`.
- [ ] Orders tab: request, claim, Craft button (open, then craft); Available tab: dibs, whisper owner; Options panel opens.
- [ ] `/tsd export`: the report ends with the "log" section.
- [ ] (optional) VS Code with the Lua extension: open the repo and check the Problems panel for annotation errors.

## Accepted gaps
- none yet

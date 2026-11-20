# 019 Code structure like TalentShare: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> 116 passed, 0 failed
Result after work:    `luajit tests/run.lua` -> 121 passed, 0 failed

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence (output line, file, screenshot) | Result | Date |
|---|---|---|---|---|---|---|
| R1 | Core grouped by role, Library split, bus in Events.lua | test_load "load: all TOC files run in order for both identities; the window builds, a flip and a spin run" (every TOC file runs, window + every game) | OFFLINE | 121 passed | pass | 2026-11-20 |
| R2 | nested files covered by TOC test, lint, harness, coinflip tool | test_load "load: the TOC lists every addon file in Core, UI and Locales" ([%w_/]+); locale lint reads nested files (the guard lint asserts >20 files scanned); `luajit tools/coinflip.lua H 200` runs | OFFLINE | 121 passed; coinflip "200 flips of 2s 50c: ..." | pass | 2026-11-20 |
| R3 | no needless module guards | "conventions: no guard on another addon module outside the allowed exceptions" (red first with 2 finds) | OFFLINE | 121 passed | pass | 2026-11-20 |
| R4 | each helper once | grep: no play/frameLevel/iconOr/setTextureOr/minutesText/duration copies; "utility: Clamp ..."; "model: Duration ..."; "model: CommonRefusalText ..." | OFFLINE | 121 passed | pass | 2026-11-20 |
| R5 | names: ID, no dt/t/info | "conventions: identifiers spell ids as ID, not Id" (red first: otherId); dt/t/info by grep | OFFLINE | 121 passed | pass | 2026-11-20 |
| R6 | docs/coding-conventions.md | file exists, every name it cites checked by grep | READ-ONLY | docs/coding-conventions.md | pass | 2026-11-20 |
| R7 | no behaviour change except the duration text | full suite unchanged + new tests; the game itself not started | OFFLINE | 116 -> 121 passed | pass (offline) | 2026-11-20 |
| RF1 | a load-time use of a module that now loads later | test_load runs every TOC file for live and dev identity | OFFLINE | 121 passed | pass | 2026-11-20 |
| RF2 | tests skip nested files | patterns changed to [%w_/]+; lint asserts scannedCount > 20 | OFFLINE | 121 passed | pass | 2026-11-20 |
| RF3 | a removed guard where the module can be absent | full suite (harness without Api/UI), coinflip tool, test_games_ui stub | OFFLINE | 121 passed | pass | 2026-11-20 |
| RF4 | merged refusal text loses a literal key | locale lint (every Text[...] key translated, every deDE key used) | OFFLINE | 121 passed | pass | 2026-11-20 |
| RF5 | rename hits a saved/wire field | diff check: the only renamed table key is nextID on the in-memory survivor run; sanitize tests pass | OFFLINE + READ-ONLY | 121 passed | pass | 2026-11-20 |
| R8 | identity + diagnostics once, in LibGuildSync | libguildsync tests/test_addon.lua (live/dev names for both addons, TOC flag, -dev once, SavedVariables warning, dispatcher, diagnostics output, MINOR 1 -> 2 upgrade); TalentShare test_build_flag/test_identity/test_hardening; GuildGames test_load | OFFLINE | libguildsync 33 passed; TalentShare 231 passed; GuildGames 121 passed | pass | 2026-11-20 |
| IG1 | the dev build loads in the client with the new TOC (no "not loaded" line, no Lua error), the four games and AZEcaught open | user, steps below | NOT-VERIFIED | | | |

## In-game checklist (things only the user can do)
- [ ] `powershell tools/deploy.ps1` (already run on 2026-11-20 22:35), then RESTART the game (a new TOC is not read by /reload).
- [ ] `/console scriptErrors 1`, `/ggd`: no "not loaded: ..." line in chat, no Lua error. Play one coin flip, one slot spin, start and give up a survivor run, open AZEcaught (companion, collection, guild views; hover the model for the NPC info).
- [ ] Minimap tooltip and companion bars show times as "1h 30m" / "2h" (Decision 2).
- [ ] `/ggd debug 20` shows no new ERROR line; `/ggd comm`, `/ggd trace 5` and `/ggd version` (LibGuildSync minor 2) answer.
- [ ] TalentShare dev build (`tools/deploy.ps1` there, restart): `/tsd` opens, `/tsd comm` answers, no "not loaded" line.

## Accepted gaps
- none yet

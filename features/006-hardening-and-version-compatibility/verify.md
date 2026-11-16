# 006 Hardening and version compatibility: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work (branch point 6e660a1): `luajit tests/run.lua` -> 59 passed, 0 failed. Baseline on master tip 2ea7200 after the rebase (checked on a `git archive` snapshot): 55 passed, 0 failed
Result after work (rebased onto master 2ea7200): `luajit tests/run.lua` -> 87 passed, 0 failed (32 new tests in `tests/test_hardening.lua`; older tests updated to the new protocol constants and schema)

Mutation check (2026-11-16, script kept out of the repo): each protection was broken on its own and the suite must fail; every one was caught (re-run after the rebase with the same result), files restored, suite back to green:
whisper gate accepts anyone -> 3 failing | parser accepts inf -> 1 | catalog ids unrestricted -> 1 | note not escaped -> 1 | no downgrade guard -> 1 | foreign major not rejected -> 2.

| ID | Requirement / Review Focus | How verified (test name) | Level | Evidence | Result | Date |
|---|---|---|---|---|---|---|
| R1 / RF1 | non-guild WHISPER and foreign channels dropped before parse/buffer/answer | `guard: only GUILD, or WHISPER from a roster member...`, `comm: a WHISPER from a non-guild character is dropped...`, `comm: foreign channels and a missing roster are rejected...` | OFFLINE | suite green | pass | 2026-11-16 |
| R1 (live) | the roster cache is filled in the real client and legit whispers (WANT/SNAP) still get through right after login | needs the game: two guild members, `/ts comm` shows `roster=N` and `received` grows | NOT-VERIFIED | needs user + second guild member | open | |
| R2 / RF2 | newer major or legacy header: no buffer, one notice per kind | `comm: a newer major or a legacy header creates no buffer...`, `codec: malformed headers are rejected, legacy ... recognised` | OFFLINE | suite | pass | 2026-11-16 |
| R2 (live) | the notice text appears in the chat frame in English and German | needs the game | NOT-VERIFIED | needs user | open | |
| R3 / RF7 | same major syncs across minors; different major does not and both sides are told | `comm: two clients on different minors sync; different majors do not`, `comm: a newer MINOR is processed and noted...`, `codec: compatibility rule...` | OFFLINE | suite (in-process, no real chat channel) | pass | 2026-11-16 |
| R3 (live) | two real clients with different builds | needs a second guild member | NOT-VERIFIED (MULTI-CLIENT) | needs second player | open | |
| R4 | per-session salt in message ids | `comm: message ids start with the per-session salt...`, `comm: every chunk fits one addon message` | OFFLINE | suite | pass | 2026-11-16 |
| R5 | limits defined once and consistent | `codec: transport limits are defined once and Decode accepts what the transport can deliver` (also fails if Comm redefines CHUNK/MAX_PARTS) | OFFLINE | suite | pass | 2026-11-16 |
| R6 / RF3 | non-finite numbers and out-of-range timestamps rejected | `codec: the parser rejects non-finite numbers...`, `sync: HELLO with a non-finite, negative or future rev...`, `orders: far-future or negative timestamps...`, `store: character records with out-of-range...`, `store: an unsynced clock (server time 0) never wipes saved data...` | OFFLINE | suite | pass | 2026-11-16 |
| R7 / RF4 | allow-list copies; unknown keys dropped; bad optional fields rejected | `sync: SNAP stores a clean copy...`, `store: catalog entries with hostile or wrongly typed fields are rejected`, `orders: control characters are stripped from notes...` | OFFLINE | suite | pass | 2026-11-16 |
| R8 / RF4 | catalog ids only for the sender's own recipes | `sync: SNAP stores a clean copy...` (recipe 2 refused); mutation "catalog ids unrestricted" fails it | OFFLINE | suite + mutation check | pass | 2026-11-16 |
| R9 / RF5 | peer text escaped in view-models; debug log escaped | `model: peer text is escaped...`, `util: the debug log escapes peer text...`; mutation "note not escaped" fails it | OFFLINE | suite + mutation check | pass | 2026-11-16 |
| R9 (live) | a note containing `\|cffff0000...` shows as literal text in the order list | needs the game (type the note in the request box, look at the board) | NOT-VERIFIED | needs user | open | |
| R10 / RF6 | migration 1 -> 2, downgrade guard, corrupt/non-table SV, interplay with `/ts clean` (feature 004-clean-command) | `store: a missing, corrupt or non-table SavedVariable starts empty`, `store: /ts clean during a downgrade-guarded session...`, `store: /ts clean keeps the schema marker...`, `store: saved data from a NEWER schema is left untouched...`, `store: schema 1 data is migrated...` | OFFLINE | suite | pass | 2026-11-16 |
| R10 (live) | `Events.lua` really assigns the original table back for "newer" so the file stays intact; notice shows 5 s after login | READ-ONLY: `Core/Events.lua` ADDON_LOADED/PLAYER_LOGIN; needs the game with a hand-edited `schema = 99` in `TalentShareDB.lua` | NOT-VERIFIED | needs user | open | |
| R11 | version from TOC metadata with a pinned fallback | `version: the protocol constants match Core/Init.lua and the TOC version has a CHANGELOG entry`, `version: Init reads the version from addon metadata...` (stubbed `GetAddOnMetadata`) | OFFLINE | suite | pass | 2026-11-16 |
| R11 (live) | `C_AddOns.GetAddOnMetadata` / `GetAddOnMetadata` exists on Forever (otherwise the fallback is used) | `/ts version` prints the TOC version | NOT-VERIFIED | needs user | open | |
| R12 | tag filter `v*`, token scoped to the step, tag/TOC check | `workflow: releases trigger on v* tags only...` checks the file text; real run not done | OFFLINE (text) / NOT-VERIFIED (CI run) | suite; GitHub Actions run needs a pushed tag | partial | 2026-11-16 |
| R13 | adversarial regression tests exist | `tests/test_hardening.lua` (32 tests) + mutation check above | OFFLINE | suite | pass | 2026-11-16 |
| R14 | docs | `docs/protocol.md`, `docs/vendored-libs.md`, CHANGELOG, README, `docs/status.md`, review files updated | READ-ONLY | files exist; content reviewed by the author only | n/a | 2026-11-16 |
| (pkg) | package script output | `powershell tools/package.ps1` -> 22 files after the rebase (AutoScan.lua is gone on master), every TOC file present, no backslash entries | OFFLINE (script run) | `built ...TalentShare-0.2.0.zip (22 files)`, check script: `missing from zip: []`, `backslash names: []` | pass | 2026-11-16 |

## In-game checklist (things only the user can do)
- [ ] `/reload`, then `/ts version`: shows the TOC version, `protocol 2.0, schema 2`. No Lua errors (`/console scriptErrors 1`).
- [ ] `/ts comm`: shows `protocol=2.0`, `roster=<guild size>` a few seconds after login, `rejected=0` in a quiet guild.
- [ ] Hand-edit `WTF\...\SavedVariables\TalentShareDevDB.lua` (dev build) to `schema = 99`, log in: a notice appears after ~5 s, `/ts chars` works, and after logout the file still says `schema = 99` with the old data.
- [ ] Create a request with the note `|cffff0000RED|r` on the Recipes tab: the Orders board shows the text literally, not in red.
- [ ] With a second guild member on this build: `/ts hello`, both see each other's recipes (`/ts chars`). With one still on 0.2.0: the 0.3 client prints the "older version" notice once.

## Accepted gaps
- none yet (every `NOT-VERIFIED` row above needs the user or a second guild member).

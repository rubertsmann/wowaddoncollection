# 015 Games extraction and shared sync library: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: talentshare `luajit tests/run.lua` -> `254 passed, 0 failed` (including the 0.6.0 games tests)
Result after work:    talentshare -> `211 passed, 0 failed`; guildgames -> `51 passed, 0 failed`; libguildsync -> `27 passed, 0 failed`

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence (output line, file, screenshot) | Result | Date |
|---|---|---|---|---|---|---|
| R1 | Embedded library with several files; newest copy wins, equal or older copies skipped | libguildsync `test_core`: "core: a newer copy loaded second upgrades every module in place...", "...older copy loaded second is skipped...", "...same version is skipped...", "every library file registers with Core's MINOR" | OFFLINE | `27 passed, 0 failed` | pass | 2026-11-18 |
| R1 | Both addons loaded in one client really share one copy | user loaded TalentShare (dev) and GuildGames (dev) together after the Window.lua fix | IN-GAME | user report 2026-11-18 "seems to be working now fine" (no version output captured) | pass (basic) | 2026-11-18 |
| R2 | Shared helpers in the library (Utility, Log, Trace, Codec, Guard, Locale, Events, Widgets, Guild) | libguildsync `test_core` (log/trace/locale/events/codec tests); both addons' suites run all their code on them | OFFLINE | the three suite lines above | pass | 2026-11-18 |
| R3 | Channel + generic Sync engine | libguildsync `test_sync` (8 tests: pull, GUILD retry, give-up/reset, forgery, required field, login budget, asked name, hooks) and `test_channel` (9 tests) | OFFLINE | `27 passed, 0 failed` | pass | 2026-11-18 |
| R4 | TalentShare on the library, wire unchanged, suite green | talentshare suite unchanged except 4 source-text tests rewritten as behaviour tests (prefix, whisper target, codec alias, load) | OFFLINE | `211 passed, 0 failed` (incl. test_soak, test_sync, test_canon, test_forever_names, test_hardening) | pass | 2026-11-18 |
| R4 | TalentShare 0.7 still syncs with real members | two members (0.7 + 0.7, and 0.7 + 0.6.0): recipes, orders, items | NOT-VERIFIED | needs the user + a second member | | |
| R5 | No games in TalentShare; schema 5 drops them | test_hardening "015: protocol 2.3 and schema 5 are pinned; migration 4 -> 5 drops games...", test_load "games moved" assertions | OFFLINE | `211 passed` | pass | 2026-11-18 |
| R6 | GuildGames works as the 0.6.0 games did | guildgames: 43 moved games tests unchanged in substance (sync over a bus incl. a 10-peer soak at 10% loss, UI against widget stubs, rules), test_load (both builds: window builds, flip and spin run) | OFFLINE | `51 passed, 0 failed` | pass | 2026-11-18 |
| R6 | GuildGames in the game: window, animation, minimap button | `/ggd` and the minimap coin in the dev client | IN-GAME | user report 2026-11-18 "seems to be working now fine" | pass (basic) | 2026-11-18 |
| R6 | GuildGames between two members (shared leaderboard) | a second guild member with GuildGames | NOT-VERIFIED | needs the user + a second member | | |
| R7 | Suites, deploy and package in each repo; zip has real library files | `tools/deploy.ps1` (both addons), `tools/package.ps1` self-check lists every LibGuildSync.xml file in the zip | OFFLINE | `built ...\GuildGames-0.1.0.zip (36 files)`; TalentShare test build `TalentShare-0.7.0-test.zip (43 files)` with Libs/LibGuildSync/*.lua listed | pass | 2026-11-18 |
| RF1 | Two library copies of different minors, either order | libguildsync test_core (3 load-order tests) | OFFLINE | `27 passed` | pass | 2026-11-18 |
| RF2 | Two addons together keep the server rate | libguildsync test_channel "one token bucket for every channel..." | OFFLINE | `27 passed` | pass | 2026-11-18 |
| RF3 | 0.6.0 peers: wire meaning unchanged, games messages ignored | talentshare test_hardening "015: a 0.6 peer's games messages are ignored, the rest of its HELLO still works" + all existing sync tests | OFFLINE | `211 passed` | pass | 2026-11-18 |
| RF4 | Shared name state, per-addon identity | libguildsync "utility: the name state is shared, Me is not part of the library", test_channel echo test (a realm learned by one channel re-keys the other addon) | OFFLINE | `27 passed` | pass | 2026-11-18 |
| RF5 | GuildGames outside a guild: no sends, no errors | guildgames test_load "not in a guild -> the channel stays inactive and a play is still stored" | OFFLINE | `51 passed` | pass | 2026-11-18 |

## In-game checklist (things only the user can do)
- [ ] Restart the game (new files and TOCs). Enable TalentShare (dev) and GuildGames (dev); `/console scriptErrors 1`.
- [ ] `/tsd version` and `/ggd version`: no errors; `/ggd version` prints `LibGuildSync minor 1`.
- [ ] `/tsd`: no Games tab; Recipes/Orders/Available/Debug work; Debug tab trace shows HELLOs.
- [ ] `/ggd`: window opens; coin flip and slot machine animate as in 0.6.0; leaderboard shows the play.
- [ ] `/tsd comm` and `/ggd comm`: both `active=true` in a guild.
- [ ] With a second member: their flips appear on your GuildGames leaderboard; TalentShare recipes/orders still sync (also with a member on 0.6.0).

## Accepted gaps
- (none yet)

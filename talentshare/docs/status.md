# Implementation status (updated 2026-11-16, after release 0.3.2)

**Sync failure in 0.4.0 (user report, live guild):** orders sync (with a wrong name), known recipes and recipe items do not. Analysis: `review/sync-0.4.0-diagnosis.md` (every failing path is a whisper round trip; the name-form comparisons on that path are the probable cause). Feature 008 (v0.4.1, `verifying`, protocol 2.2) adds the Debug tab, `/ts export`, canonical player names, pull retries over GUILD, order name snapshots and fixes for the same-realm whisper target and stale identity. Proven OFFLINE only (incl. a test where every whisper is lost); the in-game effect is NOT confirmed until two members run it and send exports.

**Releases (GitHub tags, built by `.github/workflows/release.yml`):** v0.3.0, v0.3.1 (build flag `ns.BUILD`, dev/live isolation checks), v0.3.2 (same-realm whispers addressed by character name; names in lists without the realm suffix). v0.4.0 adds feature 007 (Available tab, protocol 2.1, schema 3). v0.4.1 adds feature 008 (surname-aware player names, pull retries over GUILD, Debug tab and `/ts export`, protocol 2.2). User-reported: an "addon action blocked" dialog in the live build on a second click. Cause found 2026-11-18: the window holds secure buttons and so could not be shown or hidden in combat; fixed in 0.7.1 by `UI/SecureDock.lua` (confirmed in game by the user, 2026-11-18); blocked actions are now logged. Sync between two real players (live build) is unverified: the live 0.3.1 folder was not loaded in the first test session (a restart is needed after installing the folder).

**Current:** `luajit tests/run.lua` -> see the last line of the suite (feature 006 added 30 hardening tests on top of master's suite). Per-feature state lives in `features/INDEX.md` (001 dev/live coexistence, 002 localization, 004 clean command, 005 profession scan buttons, 006 hardening and version compatibility: `verifying`; 003 auto profession scan was abandoned: the game blocks addons from opening professions), waiting for the in-game checklists in their `verify.md`. Feature 006 (protocol 2.0, schema 2, inbound guild gate, strict validation) is proven OFFLINE only; the roster gate after login and two-client interop of the new header are NOT verified in game.
**Feature 007 (Available tab: recipe items + dibs, protocol 2.1, schema 3):** built and proven OFFLINE (`tests/test_offers.lua`, `test_offers_model.lua`, `test_items_api.lua`); the client APIs for bank/mail/guild bank/auction scanning and the tab layout are NOT verified in game (`/ts offers` is the probe), nor is two-client sync.
**Feature 014 (Games tab: coin flip + guild leaderboard, protocol 2.3, schema 4; moved to GuildGames by 015):** built and proven OFFLINE (`tests/test_games*.lua`, `test_coinflip.lua`, `test_load.lua`); the look of the animation, the animation API facts (probe `/tsd anim`, P1-P8), and two-client sync are NOT verified in game. Checklist: `features/014-guild-game-base/verify.md`.
**Feature 015 (games moved to the GuildGames addon, comms + helpers into the embedded LibGuildSync-1.0, schema 5):** built and proven OFFLINE in all three repos (talentshare `211 passed`, guildgames `51 passed`, libguildsync `27 passed`). NOT verified in game: both addons loaded together (one active library copy, shared send budget), TalentShare 0.7 syncing with 0.6.0 members, GuildGames between two members. Checklist: `features/015-games-extraction-and-shared-sync-library/verify.md`. Known gap: the inactive GitHub release workflow (`.pkgmeta`) does not fetch LibGuildSync; releases are built with `tools/package.ps1`.
**Feature 016 (Recipes table: quality-coloured names, switchable columns, sort by item level; resizable window; UI + local settings only):** logic proven OFFLINE (`tests/test_recipe_table.lua`; suite `222 passed, 1 failed`, the failure is the pre-existing stray `Core/Play/Slots.lua`). NOT verified in game: the table look, header sorting, options section, resize grip and scaling of every tab. Checklist: `features/016-recipe-table-columns-and-resizable-window/verify.md`.
**Feature 017 (enchant effect text, 0.7.2, fixed in 0.7.3, UI only):** effect text of recipes without an item in the tooltip, detail panel and search, from the spell description (0.7.2 showed tools/reagents for most enchants; fixed). Confirmed in game with the dev fake enchanter (all 6 enchants). Checklist: `features/017-enchant-effect-text/verify.md`.
**Verified in game (user, 0.1.0 dev build):** profession scan (23 recipes, reagents), `/ts scan` and `/ts dump`, window opens, API probe (see `docs/api-findings.md`). **Not verified in game:** two-player sync, the 0.2.0 changes (localized UI, dev/live side by side), CurseForge auto-release.

Table below is the original plan status from the first night (T1-T19), kept for history.

Legend: DONE = written; UNVERIFIED = needs the check in the last column.

| Plan task | State | What proves it |
|---|---|---|
| T1 scaffold, deploy | DONE, UNVERIFIED | `powershell tools/deploy.ps1`, start game, `/ts version` |
| T2 test harness | DONE, UNVERIFIED | `luajit tests/run.lua` (needs `winget install DEVCOM.LuaJIT`) |
| T3 API probe | DONE (addon), findings pending | `tools/deploy.ps1 -WithProbe`, `/tsp` with a profession window open, `/reload`, read `TalentShareProbeDB.lua` |
| T4 libs | LibStub + LibDeflate vendored (copied from the installed Spoken addon, zlib licence). **AceComm / ChatThrottleLib / LibSerialize are NOT used**; replaced by `Core/Net/Codec.lua` (own safe serializer) and `Core/Net/Communication.lua` (own chunking + token-bucket pacing) | tests + in-game `/ts comm` |
| T5 Store | DONE, UNVERIFIED | `tests/test_core.lua` |
| T6 Api adapter | DONE; supports modern `C_TradeSkillUI` and legacy `GetTradeSkill*`, chosen at runtime | `/ts scan`, `/ts dump` with a profession open |
| T7 Scanner | DONE, UNVERIFIED | `/ts dump` shows recipe counts per profession |
| T8 Events | DONE, UNVERIFIED | `/ts debug` shows `scan changed/same` entries |
| T9 Codec | DONE, UNVERIFIED | `tests/test_core.lua` |
| T10 Sync | DONE, UNVERIFIED | `tests/test_sync.lua` |
| T11 Comm | DONE, UNVERIFIED | two guild characters; `/ts comm`, `/ts chars` |
| T12 Orders | DONE, UNVERIFIED | `tests/test_orders.lua` |
| T13 Orders sync | DONE (in Sync) | two characters, create/claim an order |
| T14-T17 UI | DONE, UNVERIFIED | open `/ts` in game; checklist in `eval/plan.md` |
| T18 packaging | `tools/package.ps1`, `.pkgmeta`, workflow written; CurseForge project/token not created | `powershell tools/package.ps1`, install zip |
| T19 soak | offline half DONE and passing (`tests/test_soak.lua`: 3000-case fuzz, 30 peers x 20 min at 10% loss converge); real-guild half not started | needs a real guild evening |

## Publishing

* CurseForge project (slug `guild-talentshare`), files uploaded **manually** from `dist/TalentShare-<version>.zip`
  (built by `tools/package.ps1`): https://legacy.curseforge.com/wow/addons/guild-talentshare
* Screenshots page: https://legacy.curseforge.com/wow/addons/guild-talentshare/screenshots
* GitHub: https://github.com/rubertsmann/talentshare-ordering-system
* Automated release (`.github/workflows/release.yml`) is NOT active: it needs `## X-Curse-Project-ID` in the TOC and the
  repo secret `CF_API_TOKEN`.

## Differences from the plan

* No AceComm / LibSerialize / ChatThrottleLib (no network access used). Messages are chunked at 225 bytes with header
  `id|idx|total|`; sends are paced at ~0.9/s with a burst of 5.
* Sync is pull-based: HELLO carries my record revision; peers `WANT` my snapshot when theirs is older. Offline members'
  records are NOT gossiped by third parties (a new install only learns members who come online while it is running, or
  who were online when it logged in and answered the login HELLO). This is the main functional gap.
* Professions are keyed by localized profession name (mixed-language guilds would show duplicates).

## First things to do when you wake up

1. `luajit tests/run.lua` -> 26 passed (LuaJIT is installed under `%LOCALAPPDATA%\Programs\LuaJIT\bin`; open a new shell for PATH).
2. `powershell tools/deploy.ps1 -WithProbe`; log in; open a profession; `/tsp`; `/reload`; check `/ts scan`, `/ts dump`.
3. Watch for Lua errors (`/console scriptErrors 1`).


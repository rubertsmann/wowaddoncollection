# Implementation status (updated 2026-11-16, after features 001 and 002)

**Current:** `luajit tests/run.lua` -> **53 passed, 0 failed**. Per-feature state lives in `features/INDEX.md` (001 dev/live coexistence, 002 localization, 004 clean command, 005 profession scan buttons: `verifying` (003 auto profession scan was abandoned: the game blocks addons from opening professions), waiting for the in-game checklists in their `verify.md`).
**Verified in game (user, 0.1.0 dev build):** profession scan (23 recipes, reagents), `/ts scan` and `/ts dump`, window opens, API probe (see `docs/api-findings.md`). **Not verified in game:** two-player sync, the 0.2.0 changes (localized UI, dev/live side by side), CurseForge auto-release.

Table below is the original plan status from the first night (T1-T19), kept for history.

Legend: DONE = written; UNVERIFIED = needs the check in the last column.

| Plan task | State | What proves it |
|---|---|---|
| T1 scaffold, deploy | DONE, UNVERIFIED | `powershell tools/deploy.ps1`, start game, `/ts version` |
| T2 test harness | DONE, UNVERIFIED | `luajit tests/run.lua` (needs `winget install DEVCOM.LuaJIT`) |
| T3 API probe | DONE (addon), findings pending | `tools/deploy.ps1 -WithProbe`, `/tsp` with a profession window open, `/reload`, read `TalentShareProbeDB.lua` |
| T4 libs | LibStub + LibDeflate vendored (copied from the installed Spoken addon, zlib licence). **AceComm / ChatThrottleLib / LibSerialize are NOT used**; replaced by `Core/Codec.lua` (own safe serializer) and `Core/Comm.lua` (own chunking + token-bucket pacing) | tests + in-game `/ts comm` |
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


# Implementation status (2026-11-16, written at ~01:45)

Legend: DONE = written; UNVERIFIED = needs the check in the last column. **Verified so far:** LuaJIT was installed with your approval; `luajit tests/run.lua` -> **24 passed, 0 failed** (Store, Codec, Model, Orders merge, Sync incl. 40-peer login storm); every Core/UI/probe file compiles. **Not verified:** anything that needs the game client (Api, Scanner, Events, Comm transport, UI) - the game was never started.

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


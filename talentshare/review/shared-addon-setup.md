# Review: identity and diagnostics from LibGuildSync MINOR 2

Date: 2026-11-20 · Scope: commit 5fe0338 on branch `refactor/guildgames-structure` (GuildGames feature 019 T8):
`Core/Base/Init.lua` and `Core/Net/Communication.lua` now call `LibGuildSync-1.0` `Addon.Setup` /
`Addon.AddDiagnosticCommands`; the library goes from MINOR 1 to MINOR 2 (new module `Addon`). Focus: build isolation,
compatibility with the released 0.7.3 (MINOR 1 copy), load order.
Verified: offline suites (TalentShare 231 passed, libguildsync 33 passed, GuildGames 121 passed) and reading the code.
GuildGames' dev build was started in game by the user ("ggd seems to run fine", 2026-11-20). **TalentShare with this
change has NOT been started in game.**

## Result
No blocking finding. Two low items and one note.

| ID | Severity | Finding | Fix |
|---|---|---|---|
| S1 | Low (docs), **fixed** 2026-11-21 | The "identity is defined ONLY in Core/Base/Init.lua" rule (`.claude/skills/review-talentshare/SKILL.md` "Build flag", `tests/test_build_flag.lua:90` comment) is now half true: Init.lua holds the three words (`TalentShare`, `TShare`, `ts`), the derivation lives in `Libs/LibGuildSync/Addon.lua`, which the hard-coded-identity scan excludes (it skips `Libs/`). | Update both texts to "Init.lua passes the words; LibGuildSync Addon.Setup derives the names". The derived names themselves stay pinned exactly by `tests/test_build_flag.lua:46,58,73` and `tests/test_identity.lua`, so a library change that alters them fails here. |
| S2 | Low | `Addon.Setup` does not check that `prefix .. "Dev"` fits the 16-byte addon-message prefix limit. `TShareDev` is 9 bytes, so no effect today. | Optional: `assert(#options.prefix <= 13)` in `LibGuildSync/Addon.lua`. |
| N1 | Note | First real MINOR upgrade (1 -> 2). | Analysed below; no change needed. |

## Build isolation (checked)
- Live/dev names are unchanged: prefix `TShare`/`TShareDev`, `TalentShareDB`/`TalentShareDevDB`, frames
  `TalentShare`/`TalentShareDev`, `/ts /talentshare` / `/tsd /talentsharedev`, slash key `TALENTSHARE`/`TALENTSHAREDEV`,
  title colour `33ccff`. Same two signals (TOC `X-Build: dev` or folder name with "dev"), same "-dev" once rule, same
  SavedVariables mismatch warning. Pinned by the TalentShare tests above and libguildsync `tests/test_addon.lua`.
- The TOC fallback version `0.7.3` is still a literal in Init.lua (`tests/test_hardening.lua` compares it to the TOC).

## Compatibility with a MINOR 1 copy (released TalentShare 0.7.3, GuildGames 0.1.0)
LibStub keeps the highest MINOR active; every file of the newer copy re-runs on the same module tables.
- **Old copy loads first, this build second:** TalentShare's own `Libs/LibGuildSync` (MINOR 2) loads before its
  `Init.lua` (TOC order), upgrades every module in place and adds `Addon`, so `Addon.Setup` exists when Init runs.
  Pinned by libguildsync "addon: a MINOR 1 copy without Addon.lua is upgraded by a MINOR 2 copy that brings it".
- **This build loads first, old copy second:** the old files are skipped; the old addon's own Init does not use `Addon`.
- **State across the upgrade:** shared state lives in fields kept with `x = x or {}` (`Channel.shared` with the driver
  frame and ticker, `Utility.names`, `Utility.realmAliasVersion`, `Sync.instanceMetatable`, `Sync.RETRY_SECONDS`); the
  driver calls `Channel.Drive` / `Channel.EveryMinute` through the module table, so it runs the active code. No module
  creates a frame or timer at file load. Channel instances made by an older copy keep their closures; MINOR 2 changes
  no Channel behaviour, so that is harmless.
- Wire protocol (2.3) and schema (5): unchanged.

## Diagnostics commands
`comm`, `hello`, `debug [count]`, `trace [count] [problems]` print the same text as before (same format string,
including "incompatible peers"); they read `addon.Communication`, `addon.Trace`, `addon.db` at use time. `/ts chars` and
`/ts version` stay in TalentShare.

## Load order
Unchanged TOC. Init.lua's only new dependency is the library, which the TOC loads first.

## Packaging
`tools/package.ps1` ships every file listed in `LibGuildSync.xml` and fails when one is missing, so `Addon.lua` is in
the zip. The GitHub release workflow is not active (docs/status.md); no change there.

## Still needed before a TalentShare release
- In game: TalentShare dev build (`tools/deploy.ps1`, restart): `/tsd` opens, `/tsd comm` and `/tsd version` answer, no
  "the TOC saves ..." line, no Lua error. Ideally also with the live 0.7.3 folder installed next to it (MINOR 1 copy).

# 019 Code structure like TalentShare: spec

- Status: verifying
- Created: 2026-11-20
- Target version: next GuildGames release (no behaviour change; not a release on its own)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
GuildGames follows TalentShare's folder layout and coding conventions (no needless module guards, full names, `ID`
suffix), and helper logic that was copied between files lives in one place.

## Requirements
- R1: `Core/` is grouped by role like TalentShare: `Base/` (Init, Utility, Log, Locale), `Debug/` (Trace), `Net/`
  (Codec, Guard, Sync, Communication), `Data/` (Store, Games, Wallet), `Game/` (Api, Catcher, Events: the WoW client
  side), `Minigames/` (CoinFlip, Slots, Survivor, AzeCaught: pure game rules), `View/` (Model). `Core/Library.lua` is
  split into one file per module. The internal event bus is made in `Core/Game/Events.lua`, as in TalentShare.
- R2: The TOC, the offline harness (`tests/run.lua` PURE_FILES), the TOC-completeness test, the localization lint and
  `tools/coinflip.lua` work with nested folders: a file in a subfolder that is missing from the TOC fails a test, and the
  lint reads every nested file.
- R3: No guard on another module that the TOC already guarantees (`addon.X and ...`, `if addon.X then`), except the
  cases `docs/coding-conventions.md` allows. Pinned by a lint test.
- R4: Each helper exists once: sound by name, frame level, texture-with-fallback, duration text, refusal texts, UI
  settings, clamp. The copy-paste duplicate `might`/`haste` in `Core/Minigames/Survivor.lua` is gone.
- R5: Local names follow the conventions: `npcID`/`typeID`/`displayID`/`animationID` (not `...Id`), no `dt`/`t`/`info`
  parameter names. Saved-data and wire field names do not change.
- R6: `docs/coding-conventions.md` exists for GuildGames.
- R7: No behaviour change other than the duration text (Decision 2): the offline suite stays green (116 before).
- R8: The identity/build flag, slash dispatcher and diagnostic commands (`comm`, `hello`, `debug`, `trace`) exist once, in
  LibGuildSync (MINOR 2, module `Addon`), used by GuildGames and TalentShare with unchanged names and output (GuildGames
  `/gg comm` gains "incompatible peers=N", as TalentShare had).

## Non-goals
- No protocol, schema or saved-data change.
- No new player-facing feature, no release/version bump.

## Design
- Files touched: every `Core/*.lua` (moved), `Core/Library.lua` -> `Core/Base/{Utility,Log,Locale}.lua`,
  `Core/Debug/Trace.lua`, `Core/Net/{Codec,Guard}.lua`; `GuildGames.toc`; `tests/run.lua`, `tests/test_load.lua`,
  `tests/test_store_and_locale.lua`; `tools/coinflip.lua`; comments and `docs/protocol.md` paths; UI files for helpers.
- New shared helpers: `Utility.Clamp` (Core/Base/Utility.lua), `Api.PlaySoundNamed` (Core/Game/Api.lua),
  `Model.RefusalText` (Core/View/Model.lua), UI helpers in the first UI file (T4).
- Data shape change: none. Message shape change: none.

## Tasks
- [x] T1 (M): move files, split Library.lua, event bus to Events.lua, TOC + harness + tests + tools + path comments. Verify: luajit tests/run.lua; tools/coinflip.lua runs.
- [x] T2 (S): remove needless module guards; lint test for them. Verify: new test in tests/test_store_and_locale.lua.
- [x] T3 (S): Survivor duplicate might/haste; Utility.Clamp. Verify: test_survivor, test_azecaught.
- [x] T4 (M): shared UI helpers (sound by name, frame level, texture fallback, settings), money/me wrappers. Verify: test_load, test_games_ui.
- [x] T5 (S): one Model.Duration; one Model.RefusalText. Verify: new Model tests; locale lint.
- [x] T6 (M): renames (`...Id` -> `...ID`, `dt`, `t`, `info`). Verify: full suite.
- [x] T7 (S): docs/coding-conventions.md, CHANGELOG, doc.md. Verify: read.
- [x] T8 (M): shared Init/diagnostic slash commands in LibGuildSync MINOR 2 for both addons. Verify: libguildsync tests/test_addon.lua; TalentShare and GuildGames suites.

## Review Focus (failure modes a happy-path test would miss)
1. RF1: a module that a load-time line uses now loads later (event bus moved to Events.lua) -> nil index at load. Pinned by: test_load (both identities run every TOC file).
2. RF2: the lint / TOC tests silently skip nested files (old `[%w_]+` patterns) -> a missing file or an untranslated key is not reported. Pinned by: T1 pattern change.
3. RF3: removing a guard where the module really can be absent (offline harness without Api/UI) -> tests or tools crash. Pinned by: full suite + tools/coinflip.lua.
4. RF4: a merged refusal text loses a literal `Text["..."]` key -> the locale lint no longer sees it, German falls back to English. Pinned by: locale lint test.
5. RF5: a rename touches a saved/wire field (`npc`, `disp`, ...) -> saved data or peers break. Pinned by: renames limited to locals/params; sanitize tests.

## Cross-cutting checklist (answer every line; "n/a: reason" is fine)
- [x] Protocol: unchanged (1.1); no message change.
- [x] Stored data: `Store.SCHEMA` unchanged (2); no stored-shape change.
- [x] Trust model: unchanged; escaping stays in Model.
- [x] Localization: helpers keep literal `Text[...]` keys; lint now reads nested folders.
- [x] Load order: TOC regrouped, same relative order of dependencies; Codec/Guard now load before Store (they only define tables); event bus in Events.lua (no load-time On/Fire before it: checked by grep, pinned by test_load).
- [x] Packaging: tools/package.ps1 walks folders recursively; nothing to change. Dev TOC regenerated by tools/deploy.ps1.
- [x] Tests: lints for module guards (T2) and the ID spelling (T6), Clamp (T3), Model duration/refusal tests (T5).
- [x] Docs: docs/coding-conventions.md, CHANGELOG, doc.md (T7).

## Decisions (user answers and design choices, newest last)
- 2026-11-20: user: "implement everything and then continue with this work" -> the analysis plan is approved as a whole; the open questions are decided by Claude's recommendation (below) and logged.
- 2026-11-20: Decision 1: pure game rules go to `Core/Minigames/` (not `Core/Games/`, too close to `Core/Game/`, which is the WoW client side as in TalentShare).
- 2026-11-20: Decision 2: one duration text, `Model.Duration` (rounds to the nearest minute, whole hours as "2h"). The companion panel and the minimap tooltip used to floor and always show minutes ("2h 0m"); they now match the NPC info overlay.
- 2026-11-20: Decision 3: work on branch `refactor/guildgames-structure`, one commit per task.
- 2026-11-20: Decision 4: T8 done (part of "implement everything"): LibGuildSync MINOR 1 -> 2, additive module `Addon`. A MINOR 1 copy (released TalentShare 0.7.3) loaded first is upgraded in place (pinned by a library test). TalentShare's next release ships it.

## Open questions
- none

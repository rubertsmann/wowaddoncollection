# 013 Naming types and logging overhaul: spec

- Status: verifying
- Created: 2026-11-17
- Target version: next release (internal; no player-visible change except more log lines)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
Every code name in full words with one shared vocabulary, LuaLS type annotations on every module function and shared
table shape, and one logging helper used for every diagnostic, because the log is the only debugging tool in the client.

## Requirements
- R1: No single-letter or abbreviated identifiers in Core/, UI/, Locales/ and tests/ (exceptions in docs/coding-conventions.md).
- R2: Wire-protocol fields, SavedVariables keys and slash command words are unchanged (compatibility).
- R3: Every module function and every table shape passed between modules has LuaLS annotations.
- R4: One logging helper (Core/Base/Log.lua): Error/Warning/Information/Debug/Exception/Protected, one line format,
  bounded, escaped, repeat-folded; ns.Debug.Log and Util.ReportError are gone.
- R5: Every pcall whose failure means a feature did not do its job logs through Log (Exception/Protected or Error/Warning).
- R6: Behaviour unchanged: the existing offline suite passes (adjusted only for renamed names).

## Non-goals
- Renaming wire fields, saved keys or slash commands (R2).
- Running a LuaLS type check (not installed on this machine).

## Design
- New `Core/Base/Log.lua` (TOC after Utility; tests/run.lua loads it).
- Files renamed: `Core/Base/Util.lua` -> `Utility.lua`, `Core/Net/Comm.lua` -> `Communication.lua`,
  `Core/Debug/Diag.lua` -> `Diagnostics.lua`.
- Public renames (full list in log.md): ns -> addon, Util -> Utility, Comm -> Communication, Diag -> Diagnostics,
  L -> Text, Esc -> Escape, Canon -> CanonicalName, SafeInt -> SafeInteger, Fmt -> Format, Sys -> System,
  PROTO_MAJOR/MINOR -> PROTOCOL_MAJOR/MINOR, SVNAME -> SAVED_VARIABLES_NAME, IS_DEV -> IS_DEVELOPMENT_BUILD, ...
- Internal object fields renamed (never saved or sent): Sync state and pull/pending entries, Communication queue and
  buffer entries, Codec header fields, Model category groups, offer filter, Api.scanStatistics, spellCount.
- Renames were made with a token-level renamer (strings, comments, `.field` and table keys untouched unless listed) and
  by rewriting each file; the offline suite ran after every step.

## Tasks
- [x] T1 (M): global public renames + file renames, tests adjusted. Verify: suite
- [x] T2 (M): Core/Base/Log.lua + tests/test_log.lua (6 tests). Verify: test_log
- [x] T3 (L): per-file rewrite of Core/ (names, annotations, logging). Verify: suite after each file
- [x] T4 (L): per-file rewrite of UI/ (Alerts, DevProbe, Window). Verify: test_load builds the window
- [x] T5 (M): tests: harness names (harness/addon/equal/character), run.lua rewritten. Verify: suite
- [x] T6 (S): docs/coding-conventions.md, README, protocol.md, api-findings.md, review skill, CHANGELOG

## Review Focus
1. RF1: a renamed field that is also a wire or saved key -> must not happen. Pinned by: R2 + test_sync/test_offers/test_hardening (wire), test_version_reset/test_core (saved).
2. RF2: peer text in log lines printed by /ts debug -> escaped, no bare "|" (separator " :: "). Pinned by: test_log.
3. RF3: a hot loop flooding the log -> repeats folded, ring bounded. Pinned by: test_log.
4. RF4: client-only files (Api, Events, UI) -> test_load loads every TOC file and builds the window with stubs; the rest is IN-GAME.

## Cross-cutting checklist
- [x] Protocol: unchanged (no wire field renamed).
- [x] Stored data: Store.SCHEMA unchanged; no saved key renamed (debug log lines get a new text format only).
- [x] Trust model: unchanged; log values escaped.
- [x] Localization: no new UI strings (log text is developer-facing English, as before).
- [x] Load order: Log.lua added after Utility in both TOCs; the dev TOC must be regenerated and the game restarted.
- [x] Packaging: package.ps1 ships Core/ recursively; no change needed.
- [x] Tests: tests/test_log.lua; harness renamed.
- [x] Docs: coding-conventions.md, README, CHANGELOG.

## Decisions
- 2026-11-17: user asked for "a complete overwork" with full-word names, typing where possible and one explicit logging pattern.
- 2026-11-17: Lua has no static types; LuaLS annotations are used (checked by the VS Code Lua extension); no runtime type checks added.
- 2026-11-17: wire/saved/slash names stay (compatibility with installed clients and saved files); documented per module.
- 2026-11-17: acronyms UI/ID/API/UTF8 and the words ok/me stay; `_` for ignored values.
- 2026-11-17: log separator " :: " instead of " | " ("|" starts escape codes in the chat frame).

## Open questions
- none

# 002 Localization layer: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-16 10:05 | PLAN | Feature created
- Did: scaffolded `features/002-localization-layer/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-16 10:08 | DECISION | additive wire format, English-text keys, named placeholders
- Did: wrote spec.md. Kept storage keys as sender name strings and added optional `id`/`loc` fields (0.1.0 clients reject number keys in `ValidateChar`), kept MAX_NOTE = 80 bytes, chose `{name}` placeholders (real Lua `string.format` has no `%1$s`)
- Result: `PROTOCOL` and `Store.SCHEMA` unchanged
- Evidence: spec.md "Decisions"
- Next: T1-T4 pure logic with tests

## 2026-11-16 10:11 | BUILD | T1-T4 Util UTF-8, Locale, Locales, Names, Store, Scanner, Model, Orders, Api
- Did: `Core/Util.lua` (IsValidUtf8, TruncateUtf8, Fold, SearchKey); new `Core/Locale.lua`, `Core/Names.lua`, `Locales/enUS.lua`, `Locales/deDE.lua`; `Core/Store.lua` (ValidateProfessionMeta, catalog loc, profNames, Crafters.pentry); `Core/Scanner.lua` (id/loc, re-key by id, Names.Learn); `Core/Model.lua` (canonical professions, SearchKey search/sort, viewer-first reagent names); `Core/Orders.lua` (UTF-8 safe note); `Core/Api.lua` (GetLocale, SpellName, profession ids, `/ts i18n`)
- Result: found and fixed a real bug on the way: `Orders:Create` returned nil for a note over 80 BYTES, so a 30-character CJK note made the Request button do nothing (the UI limited characters, the order limited bytes)
- Evidence: `luajit tests/run.lua` -> 51 passed, 0 failed (30 before). New: tests/test_localization.lua (15), test_locale_files.lua (4), test_load.lua (2)
- Next: localize UI/Window.lua

## 2026-11-16 10:13 | BUILD | T5 Window localized
- Did: `UI/Window.lua` rewritten to use L/F/P, auto-width buttons (`SetLabel`), `SetMaxBytes(80)` on the note box, profession filter holds {key,name}; `Core/Events.lua` applies `db.ui.locale`; TOC and `tools/package.ps1` list Locales; deploy regenerated the dev TOC
- Result: lint test "no hardcoded user-facing text in UI/" passes (it failed with 21 hits before the rewrite)
- Evidence: mutation check: removing Names from the TOC makes test_load fail ("exists but is not in TalentShare.toc", "namespace incomplete"); package zip contains `Locales/` and `Names.lua`
- Next: user checks the UI in game (German and English), see verify.md in-game checklist

## 2026-11-16 10:14 | BLOCKED | in-game verification needs the user
- Did: nothing; waiting
- Result: layout (button widths, text overflow), `/tsd i18n` answers (are skill line ids and spell names what we assume) and real client behaviour are NOT verified
- Evidence: n/a
- Next: user runs the checklist in verify.md and pastes the `/tsd i18n` output (open a profession window first)

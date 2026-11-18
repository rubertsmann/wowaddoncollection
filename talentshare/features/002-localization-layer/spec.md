# 002 Localization layer: spec

- Status: verifying
- Created: 2026-11-16
- Target version: 0.2.0
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
Every game name is resolved on the viewer's client from an ID, every addon text comes from a locale table, and user text is UTF-8 safe, so a mixed-language guild sees one consistent list in each player's own language.

## Requirements
- R1: Professions are identified by skill line ID (`entry.id`); a German "Kochkunst" and an English "Cooking" are one profession in filter, list and crafter views; records from 0.1.0 peers (name keys, no id) merge in via a name->id reverse lookup.
- R2: Profession display name resolution order: names learned from the viewer's own client -> sender snapshot when it is in the viewer's language -> static table for the viewer's language -> English table -> sender snapshot -> `Profession #id`.
- R3: Recipe display name: sender snapshot if recorded in the viewer's language, else the viewer's client spell name (`C_Spell.GetSpellInfo`), else sender snapshot, else `Recipe #id`. Reagent names come from the viewer's client first.
- R4: All UI text goes through `ns.L[...]` (English text is the key, `Locales/<code>.lua` translates; missing = English). German (deDE) ships complete. Named placeholders `{name}` (no positional printf args). Plural via `Locale.Plural`.
- R5: UI language can be forced for testing (`/ts locale <code>|auto`, takes effect after `/reload`).
- R6: Search and sort are case- and accent-insensitive for Latin and Cyrillic (`kürsch` finds `Kürschnerei`, `KÜRSCH` too; `ä` sorts with `a`).
- R7: Order notes are limited in bytes and truncated on a UTF-8 character boundary on create; receivers reject invalid UTF-8; the note box counts bytes (`SetMaxBytes`).
- R8: Buttons size to their text so longer translations are not clipped.
- R9: Wire format stays compatible with 0.1.0 (`PROTOCOL` unchanged): only optional fields `id` and `loc` are added to profession entries, `loc` to catalog entries.

## Non-goals
- No translation files besides enUS (implicit) and deDE; other languages fall back to English text but still get game names from their own client.
- No right-to-left layout, no CJK-aware sorting (CJK sorts by byte value).
- Debug slash command output (`/ts comm`, `/ts dump`, ...) stays English.
- Peer text escaping (`|` codes) is a separate security finding (see `review/`).

## Design
- `Core/Util.lua`: `IsValidUtf8`, `TruncateUtf8`, `Fold`, `SearchKey` (case + accent folding).
- `Core/Locale.lua` (new): `ns.Locale` (`clientCode`, `code`, `Register`, `SetUI`, `Fmt`, `Plural`), `ns.L` (metatable, key fallback), `/ts locale`.
- `Locales/enUS.lua`, `Locales/deDE.lua` (new): strings + profession-name tables (skill line id -> name).
- `Core/Names.lua` (new, pure): `ProfKey`, `Profession`, `Recipe`, `Learn`, `env.spellName`.
- `Core/Api.lua`: `GetLocale`, `SpellName`, profession ids (`GetProfessionInfo` 7th return; open window id resolved by name), `/ts i18n` probe command.
- `Core/Store.lua`: validate optional `id`/`loc`/`name`; `profNames` in SV; `Crafters` returns `pentry`.
- `Core/Scanner.lua`: writes `id`/`loc`, re-keys by id when the client language changes, learns names, signature includes id.
- `Core/Model.lua`: canonical profession keys, Names for display, SearchKey for search/sort.
- `Core/Orders.lua`: note truncation/validation.
- `UI/Window.lua`: `L`, auto-width buttons, byte-limited note box, profession filter holds `{key,name}`.
- TOC load order: Init, Util, Locale, Locales/enUS, Locales/deDE, Store, Names, Api, Scanner, ...

## Tasks
- [x] T1 (S): Util UTF-8 helpers + tests
- [x] T2 (S): Locale + Locales + tests (key completeness, placeholders)
- [x] T3 (M): Names + Store/Scanner/Model/Api changes + tests (mixed locale peers, legacy name keys)
- [x] T4 (S): Orders note limit + tests
- [x] T5 (M): Window localized, auto-width buttons, `/ts locale`, `/ts i18n`
- [x] T6 (S): docs, CHANGELOG, in-game checklist for the user

## Review Focus
1. RF1: Mixed-language peers (deDE + enUS + 0.1.0 name-key record) show ONE Cooking entry, each in the viewer's language -> test_localization.
2. RF2: Notes of 80 bytes of multi-byte characters never produce a half character and are accepted by peers the same way as by the sender -> test.
3. RF3: Missing translation or unknown locale never errors or shows nil -> test (`L[key]` falls back to the key).
4. RF4: Placeholder mismatch between a translation and its key (would show `{n}` raw) -> lint test.
5. RF5: Client language switch must not lose recipes (re-key by id) -> scanner test.
6. RF6: Hostile profession `id`/`loc`/`name` from a peer (strings, huge, NaN) is rejected by `ValidateChar` -> test.

## Cross-cutting checklist
- [x] Protocol: unchanged; additive optional fields only (0.1.0 peers ignore them, we accept their records).
- [x] Stored data: `Store.SCHEMA` unchanged; new optional fields and `profNames` table; no migration needed, name-keyed entries are canonicalized at read time and gain `id` on the next own scan.
- [x] Trust model: new fields allow-listed in `ValidateChar` / `ValidateCatalogEntry`; peers can still only author their own record.
- [x] Localization: this feature.
- [x] Load order: TOC lists Locale + Locales before Store; tests load the same order.
- [x] Packaging: `Locales/` must be added to `tools/package.ps1` whitelist.
- [x] Tests: tests/test_localization.lua, tests/test_locale_files.lua.
- [ ] Docs: README, CHANGELOG, doc.md.

## Decisions
- 2026-11-16: keep storage keys as the sender's name string and add `id` inside the entry (instead of re-keying by number), because 0.1.0 clients reject number keys in `ValidateChar`; identity is computed by `Names.ProfKey`.
- 2026-11-16: English text is the translation key (no separate key names); named placeholders `{x}` because real Lua `string.format` does not support `%1$s`.
- 2026-11-16: keep `MAX_NOTE = 80` bytes (no protocol change) and truncate on a UTF-8 boundary instead of raising the limit.
- 2026-11-16: static profession ids other than Leatherworking 165, Skinning 393, Cooking 185 are from memory of the classic skill line ids (not verified on Forever); they are only used as fallback names after the viewer's own client.

## Open questions
- Does `C_Spell.GetSpellInfo(recipeID).name` equal the profession-window recipe name on Forever? (needs game: `/tsd i18n` with a profession window open)
- Does the open profession window report the same skill line id as `GetProfessionInfo`? (same check; id is resolved by name, so this only matters for the fallback path)

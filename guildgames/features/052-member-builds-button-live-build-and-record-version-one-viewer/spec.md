# 052 Member builds button (live build and record version, one viewer): spec

- Status: verifying
- Created: 2026-11-27
- Target version: 0.14.0
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
A small info button at the bottom left of the GuildGames window, shown only to the maintainer character, whose tooltip
lists every guild member with the build they announced live (HELLO) next to the version their synced record carries
(`arena.ver`, which the fight rules use), so stale record versions can be found.

## Requirements
- R1: The button is shown only when my name matches the maintainer name hash (same hash and djb2 rule as
  ProfessionShare's `Model.BUILD_VIEWER_HASHES`); for everybody else it stays hidden. No real name in the repo.
- R2: The tooltip lists my build, then one row per member known from the records or from a HELLO this session: name,
  live build (HELLO `ver`, "-" when none seen), record version (`arena.ver`, "-" when the record has none), and when
  their record last changed (`rev`).
- R3: A row whose live build (the part before "/") differs from the record version is marked (orange), so a stale
  record stands out; mismatching rows sort first, then by most recent.
- R4: Peer strings (names, versions) are escaped / sanitized before display; garbage records or rows are skipped.
- R5: Simulated (dev) records are not listed.

## Non-goals
- No new message, no change to the fight version rule.

## Added during the build
- R6: 5 s after login my arena section is written again when my record has none or it carries another version
  (`Arena.SectionStale`, `Catcher.Start`). Found in the live data: the stale or missing section blocked every fight.

## Design
- `Core/View/Model.lua` (changed): `Model.BUILD_VIEWER_HASHES`, `Model.NameHash`, `Model.IsBuildViewer`,
  `Model.MemberBuilds(records, versionRows, myName)` (pure).
- `UI/Window.lua` (changed): the button at the main window's bottom left, shown on every `OnShow`.
- `Locales/deDE.lua` (changed): the tooltip texts (enUS keys are the source text).
- `tests/test_member_builds.lua` (new).
- Data shape change: none. Message shape change: none.

## Tasks
- [x] T1 (S): `Model.IsBuildViewer` + `Model.NameHash`. Verify: test "member builds: viewer".
- [x] T2 (M): `Model.MemberBuilds`. Verify: test "member builds: rows".
- [x] T3 (S): button + tooltip in `UI/Window.lua`, locale strings. Verify: `test_load`, in-game hover.

## Review Focus
1. RF1: record without arena section / non-string `ver` -> record column "-", no error. Pinned by: T2
2. RF2: HELLO from a member without a record -> row with record "-". Pinned by: T2
3. RF3: name with `|` codes -> escaped. Pinned by: T2
4. RF4: dev build `0.13.0-dev/3` vs record `0.13.0-dev` -> no mismatch (only the "/minor" suffix is cut). Pinned by: T2

## Cross-cutting checklist
- [x] Protocol: unchanged (reads data already received).
- [x] Stored data: unchanged.
- [x] Trust model: names escaped (`addon.Utility.Escape`), versions through `Arena.SanitizeVersion` / `Channel.SanitizeVersionTag` rules.
- [x] Localization: tooltip strings through `Text`, deDE added.
- [x] Load order: no new file.
- [x] Packaging: no change (features/ already ignored).
- [x] Tests: `tests/test_member_builds.lua`.
- [x] Docs: CHANGELOG line, doc.md.

## Decisions
- 2026-11-27: Same maintainer hash as ProfessionShare (the user asked for "only visible to me", like ProfessionShare).
- 2026-11-27: Show the record version next to the live build: the fight rules read the record, the live build alone
  would hide the stale-entry problem the user is chasing.

## Open questions
- none

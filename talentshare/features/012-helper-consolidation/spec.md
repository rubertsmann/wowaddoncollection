# 012 Helper consolidation: spec

- Status: verifying
- Created: 2026-11-17
- Target version: next release (internal refactor, no player-visible change)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
One shared copy of every helper that had been re-implemented per module, keeping the safest behaviour of the copies.

## Requirements
- R1: Counting table keys goes through `U.Count` only, and `U.Count` returns 0 for a non-table.
- R2: Sorted key lists go through `U.SortedKeys` (numbers natural, then strings, mixed key types never error).
- R3: Emptying / refilling a table in place goes through `U.Wipe` / `U.Refill` (references stay valid).
- R4: "Who am I" goes through `U.Me`, which works before `Store.Init` (no `db` yet).
- R5: Item id from a link: one `itemIDOf` in `Core/Game/Api.lua` that returns nil for non-strings.
- R6: "Does this character know recipe X" goes through `Store.Knows`, which is false (never an error) for malformed records.
- R7: Recipe totals per character go through `Store.RecipeCount`.
- R8: Persisted-map sanitizing loops (Store chars/catalog/orders, Offers offers) go through `U.SanitizeMap` with unchanged drop rules.
- R9: Chat-safe peer text goes through `U.ChatSafe`; `Model.ChatText` output is unchanged.
- R10: No behaviour change otherwise: the existing offline suite passes unchanged.
- R11: `Core/` files are grouped by layer (`Base`, `Debug`, `Data`, `Net`, `Game`, `View`) with an unchanged TOC load order; the tests that check file coverage see files at any folder depth.

## Non-goals
- Merging functions that only share a name (`signature`, `Counts`, `Recanon`, `Get`/`List`, `isSel`): different jobs.
- Protocol, stored data or UI changes.

## Design
- `Core/Base/Utility.lua` (changed): new section "table helpers" (`Count`, `SortedKeys`, `Wipe`, `Refill`, `SanitizeMap`), "identity" (`Me`), `ChatSafe` next to `Esc`.
- `Core/Data/Store.lua` (changed): new `S.Knows`, `S.RecipeCount`; `Counts`, `Clean`, `ResetPeerData`, `Recanon`, `SanitizePersisted` use the helpers.
- Call sites switched: `Core/Game/Api.lua`, `Comm.lua`, `Diag.lua`, `Events.lua`, `Init.lua`, `Model.lua`, `Notify.lua`, `Offers.lua`, `Scanner.lua`, `Trace.lua`, `UI/Alerts.lua`, `UI/Window.lua`, `UI/DevProbe.lua`.
- Data shape change: none. Message shape change: none.
- Load order: Util loads before every user. `Store.Knows/RecipeCount` are only called at run time; Trace (loaded before Store) calls `ns.Store.RecipeCount` lazily inside `Summarize`.

## Tasks
- [x] T1 (S): Util table helpers + `U.Me` + `U.ChatSafe`. Verify: tests/test_helpers.lua
- [x] T2 (S): `Store.Knows`, `Store.RecipeCount`; Store internals on helpers. Verify: test_helpers "Store.*"
- [x] T3 (M): switch every call site (list above). Verify: full suite unchanged
- [x] T4 (S): one `itemIDOf` in Api.lua. Verify: READ-ONLY (client-only file)
- [x] T5 (S): tests/test_helpers.lua (10 tests incl. malformed input)
- [x] T6 (M): move Core files into layer folders, update TOC, path references, recursive file listing in test_load / test_locale_files, README layout table. Verify: test_load "the TOC lists every addon file", full suite

## Review Focus (failure modes a happy-path test would miss)
1. RF1: `U.Me()` before `Store.Init` -> client name, no error (old UI copies indexed `ns.Store.db.me` unguarded). Pinned by: test "Me: ..."
2. RF2: character record without `recipes` -> `Knows` false (old Model copy threw). Pinned by: test "Store.Knows ..."
3. RF3: `SortedKeys` on numeric keys keeps numeric order, so Offers content signatures and the MAX_ITEMS cap pick the same items as before. Pinned by: test "SortedKeys ..."
4. RF4: `SanitizeMap` still drops entries whose sanitizer throws, and keeps the old key checks. Pinned by: test "SanitizeMap ..." + test_hardening

## Cross-cutting checklist
- [x] Protocol: unchanged, no message shape touched.
- [x] Stored data: `Store.SCHEMA` unchanged; sanitize rules identical (same predicates, moved into `SanitizeMap`).
- [x] Trust model: unchanged; `Knows` and `Count` became stricter on malformed input; `ChatSafe` = the old `ChatText` pattern.
- [x] Localization: n/a, no strings added.
- [x] Load order: no new file; TOC paths changed by T6 (folders), order unchanged; the dev TOC must be regenerated (`tools/deploy.ps1`) and the game restarted.
- [x] Packaging: n/a, tests/ and features/ stay excluded.
- [x] Tests: new tests/test_helpers.lua.
- [x] Docs: CHANGELOG (Unreleased), doc.md.

## Decisions
- 2026-11-17: user asked for the full implementation without a plan review ("go ahead do the full implementation change"); spec written alongside.
- 2026-11-17: `SortedKeys` sorts numbers before strings, natural order within each type (keeps the order Scanner/Offers had; Diag's report order changes only for numeric keys, which is cosmetic).
- 2026-11-17: `U.Me` lives in Util (resolves `ns.Store` / `ns.Api` at call time) instead of `Comm.Me`, so UI and Events do not depend on Comm. `Comm.Me` stays as an alias.

- 2026-11-17: user asked for the files to be grouped into folders like the layers. Folders = layers of the code overview; load order stays defined by the TOC only. Feature history (features/001-011, 0.x CHANGELOG entries, older log entries) keeps the old paths as written.

## Open questions
- none

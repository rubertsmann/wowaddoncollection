# 004 Clean command: spec

- Status: verifying
- Created: 2026-11-16
- Target version: 0.2.0
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
`/ts clean` (dev: `/tsd clean`) removes everything from the local store so a player can start from a clean state.

## Requirements
- R1: `clean` removes cached guild characters, recipe catalog, orders, learned profession names and the debug log. Preferences (minimap position, UI language, autoscan) and `schema`/`me` stay.
- R2: Two steps: `clean` alone only shows what would be deleted; `clean confirm` deletes (it cannot be undone).
- R3: Tables are emptied in place: the order board (`ns.orders`) and the sync object keep working without a reload.
- R4: Afterwards the window refreshes, the next window open scans the player's professions again, and online guild members are asked to introduce themselves so their data is pulled again.

## Non-goals
- Does not touch other characters' SavedVariables, the live addon's data, or the guild (nothing is sent that deletes data elsewhere).

## Design
- `Core/Store.lua`: `Store.Counts()`, `Store.Clean()` (in place).
- `Core/Events.lua`: `ns.Slash.clean` (confirmation, refresh, `Comm.RequestHello(true, true)`).
- Tests: `store: Clean empties everything in place ...` (tests/test_core.lua), slash presence in tests/test_load.lua.

## Tasks
- [x] T1 (S): Store.Counts/Clean + test
- [x] T2 (S): slash command with confirmation, docs

## Review Focus
1. RF1: Holders of the cleaned tables (orders, sync) must not keep stale copies -> test (orders object keeps working).
2. RF2: A typo must not delete data -> confirmation word required.
3. RF3: After a clean the own record must not be published empty over the guild's good copy of it.

## Cross-cutting checklist
- [x] Protocol: unchanged (a login `HELLO` is sent, as at login).
- [x] Stored data: schema unchanged; only emptied.
- [x] Trust model: local only.
- [x] Localization: debug-style slash output stays English (like the other slash commands).
- [x] Load order, packaging: no new file.
- [x] Tests: see above.
- [ ] Docs: README, CHANGELOG.

## Decisions
- 2026-11-16: confirmation step added although the request did not ask for one (destructive and irreversible).
- 2026-11-16: UI preferences are kept ("local store" = synced/cached data, not settings).
- 2026-11-16: the own record is not rebuilt immediately; if a scan trigger fires before the professions are re-read, a record with empty recipes can be published (same as for a brand new install). Mitigation: reopen the window (auto-scan) right after cleaning.

## Open questions
- Should `clean` also reset preferences (`/ts clean all`)? Not requested.

# 025 Reputation list with faction hints: spec

- Status: verifying
- Created: 2026-11-24
- Target version: 1.4.0 (protocol 2.6, schema 8)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
Guild members see each other's standing with the factions that matter in Classic (recipe vendors, raid factions, city
mounts, battlegrounds) in a sortable, searchable Misc Items list, with a hover hint saying what each standing unlocks.

## Requirements
- R1: Each client reads its own standing (level 1-8 and progress inside the level) for every faction in the static
  faction list and shares it with the guild as its own record (only the author may write it, newer revision wins).
- R2: Factions the character has never met are not reported (no "Neutral 0/3000" noise for unmet factions).
- R3: A standing change is shared at once; a progress-only change at most every 30 minutes (no traffic per mob kill).
- R4: Misc Items gets a fourth mode "Reputation": one row per member and faction, columns Faction (name column),
  Player, Standing, Progress, Updated (hidden by default). Every column sorts; Standing sorts by level, then progress.
- R5: A faction dropdown filters the list ("All factions" or one faction); it is shown only in this mode.
- R6: The search box matches every word anywhere in faction, player and standing (same multi-word rule as the Recipes
  search; the matcher is shared code, not a copy).
- R7: Hovering a row shows the faction's hints per standing (static data), the row player's standing highlighted.
- R8: Hint data is a static, clearly marked data file (source + last-checked date) with English and German text; a
  project skill updates it from the wiki after a Forever patch.
- R9: Older peers keep working (additive protocol change); peer data is validated by allow-list and escaped for display.

## Non-goals
- No link from hints to the Recipes tab (which recipes a standing unlocks there).
- No item ids in the shipped hints (the field exists; the update skill adds ids once they are checked in game).
- No reputation of factions outside the static list; no history or graphs.

## Design
- `Core/Data/FactionHints.lua` (new, STATIC DATA): faction list (id, English name, group, icon) + hints per standing
  `{ standing, en, de, items? }`, `SOURCE`, `CHECKED`. Pure.
- `Core/Data/Reputation.lua` (new, pure): record `{ name, rev, f = { [factionID] = { s, v, m } } }` (s = standing 1-8,
  v = progress inside the level, m = size of the level), Sanitize / Put / Get / Update / SanitizePersisted / Counts.
  Unknown faction ids from a newer peer are skipped (not a reason to drop the record).
- `Core/Game/Api.lua`: `Api.ScanReputation()` (GetFactionInfoByID; list iteration for "met"), `Api.FactionName(id)`,
  `Api.StandingLabel(s)` (FACTION_STANDING_LABELn).
- `Core/Game/Events.lua`: UPDATE_FACTION (debounced 5 s) + login scan, `REPUTATION_CHANGED` -> HELLO soon, `/ps rep [scan]` probe.
- `Core/Net/Sync.lua`: record kind `rep`: HELLO.rrev, WANTR, REP {rep}.
- `Core/Data/Store.lua`: `rep` table (schema 8), Clean, ResetPeerData, SanitizePersisted, canonical names, Prune.
- `Core/View/Model.lua`: `Model.SearchWords`, `Model.MatchesWords` (shared with the recipe search), `BuildReputationRows`.
- `Core/View/MiscTables.lua`: mode `reputation` + column table.
- `UI/Window.lua`: mode wiring, faction filter dropdown, row fill, hint tooltip, detail text.
- `Locales/enUS.lua`, `Locales/deDE.lua`: UI strings.
- `professionshare/.claude/skills/update-faction-hints/SKILL.md` (project skill, not packaged): the update procedure.
- Pure logic in Reputation, FactionHints, Model, MiscTables; WoW calls only in Api.

## Tasks
- [x] T1 (S): shared search matcher in Model, recipe search uses it. Verify: existing recipe search tests + new matcher test
- [x] T2 (M): FactionHints data file. Verify: test_reputation "hint data well formed"
- [x] T3 (M): Reputation record module + Store schema 8. Verify: test_reputation sanitize/update/persist/migrate tests
- [x] T4 (M): Sync kind rep, protocol 2.6. Verify: test_reputation two-peer sync over the codec; old-peer test
- [x] T5 (M): Api scan + Events wiring + /ps rep. Verify: test_items_api-style fake client test; test_load
- [x] T6 (M): Model rows + MiscTables mode. Verify: test_reputation_model
- [x] T7 (L): Window: mode, filter dropdown, row fill, tooltip. Verify: test_load (window builds), in game
- [x] T8 (S): update skill. Verify: read-through
- [x] T9 (S): docs (README, CHANGELOG, protocol.md, status.md, doc.md)

## Review Focus (failure modes a happy-path test would miss)
1. RF1: peer record with 10 000 factions, standing 99, v > m, NaN, `|` in a name -> rejected whole / escaped. Pinned by: T3, T6
2. RF2: newer peer sends a faction id this build does not know -> record kept, id skipped. Pinned by: T3
3. RF3: farming reputation (progress changes every few seconds) -> no rev bump within 30 min unless the level changed. Pinned by: T3
4. RF4: client without GetFactionInfoByID / erroring API -> scan returns nothing, no error, record unchanged. Pinned by: T5
5. RF5: 1.3.0 peer receives HELLO with rrev and a WANTR -> ignored, other records still sync. Pinned by: T4

## Cross-cutting checklist (answer every line; "n/a: reason" is fine)
- [x] Protocol: minor 2.5 -> 2.6, additive (new HELLO field rrev, new types WANTR/REP; older peers ignore both).
- [x] Stored data: schema 7 -> 8, additive migration (new `rep` table); version reset drops peers' rep records like access.
- [x] Trust model: Reputation.Sanitize is an allow-list copy, a peer can only send its own record (engine rule), names escaped in Model.
- [x] Localization: only ids and numbers are sent; faction names and standing labels come from the viewer's client, with the English
  data name as fallback; hint text en/de in the data file (English fallback for other languages).
- [x] Load order: FactionHints and Reputation after Access, before Feedback/Sync (TOC + tests/run.lua + test_load list).
- [x] Packaging: new files are under Core/ (packaged); the skill is under the monorepo `.claude/` (not packaged).
- [x] Tests: tests/test_reputation.lua, tests/test_reputation_model.lua; adversarial cases RF1-RF5.
- [x] Docs: README, CHANGELOG, docs/status.md, docs/protocol.md, doc.md.

## Decisions (user answers and design choices, newest last)
- 2026-11-24: Reputation is a fourth Misc Items mode, not its own tab (user).
- 2026-11-24: One row per member and faction, full list with a "Faction" column, filtered by a dropdown (user).
- 2026-11-24: Free-text search like the Recipes page, reusing its code (user).
- 2026-11-24: Hover hints per standing; the game has no such data, so a static data file marked as static plus a skill to
  update it after a Forever patch (user).
- 2026-11-24: Own record kind (not part of the access record): reputation changes far more often than keys, and the access
  record would then be re-pulled for every standing change (claude).
- 2026-11-24: Hints ship as English + German text, items field optional and empty: the item ids found online could not be
  verified against Forever, and a wrong id would show a wrong item; the update skill fills them after an in-game check (claude).
- 2026-11-24: Progress-only changes are shared at most every 30 minutes; level changes at once (claude).

## Open questions
- Does GetFactionInfoByID exist on Forever and return the 14-value classic signature? (needs: game, `/ps rep`)
- Are all faction ids in FactionHints right on Forever? (needs: game, `/ps rep`)

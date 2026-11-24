# 025 Reputation list with faction hints: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> 269 passed, 0 failed
Result after work:    `luajit tests/run.lua` -> 295 passed, 0 failed

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence (output line, file, screenshot) | Result | Date |
|---|---|---|---|---|---|---|
| R1 | own standings read and shared as own record | test_reputation_api "standings of met factions..."; test_reputation "two peers exchange..." | OFFLINE | 294 passed | pass | 2026-11-24 |
| R1 | the same on the Forever client | user /reload, then the stored record read from WTF ProfessionShare-Dev.lua | IN-GAME | 12 factions with plausible standings (Horde cities Honored, goblin towns Friendly, Argent Dawn Neutral 400/3000); found: Alliance BG factions 730/509 reported as Hated 0/36000 (fixed, re-check) | partial | 2026-11-24 |
| R2 | unmet factions not reported | test_reputation_api "standings of met factions (listed or not untouched)" | OFFLINE | 294 passed | pass | 2026-11-24 |
| R3 | level at once, progress every 30 min | test_reputation "(RF3) level changes are shared at once..." | OFFLINE | 294 passed | pass | 2026-11-24 |
| R4 | list, columns, sort | test_reputation_model "standing sorts by level...", "misc tables: reputation mode..." | OFFLINE | 294 passed | pass | 2026-11-24 |
| R4 | list look in game | in-game checklist | IN-GAME | user: "everything works fine in that feature" | pass | 2026-11-24 |
| R5 | faction filter | test_reputation_model "the faction filter keeps one faction", "the dropdown lists factions..." | OFFLINE | 294 passed | pass | 2026-11-24 |
| R6 | shared multi-word search | test_reputation_model "search needs every word..."; recipe search tests unchanged (test_categories) | OFFLINE | 294 passed | pass | 2026-11-24 |
| R7 | hover hints marked against standing | test_reputation_model "hint lines: reached, next and later..." (logic); tooltip in game | OFFLINE + IN-GAME | 295 passed; user: "everything works fine in that feature" | pass | 2026-11-24 |
| R8 | static data file + update skill | test_reputation "faction hints: every faction well formed..."; skill read-through | OFFLINE / READ-ONLY | 294 passed | pass | 2026-11-24 |
| R9 | older peers keep working; validation; escaping | test_reputation "(RF5)...", "a peer cannot write...", "(RF1) sanitize..."; test_reputation_model "(RF1) peer names are escaped" | OFFLINE | 294 passed | pass | 2026-11-24 |
| RF1 | hostile record | test_reputation "(RF1) sanitize rejects..." | OFFLINE | 294 passed | pass | 2026-11-24 |
| RF2 | unknown faction id from a newer peer | test_reputation "(RF2)..." | OFFLINE | 294 passed | pass | 2026-11-24 |
| RF3 | farming does not flood | test_reputation "(RF3)..." | OFFLINE | 294 passed | pass | 2026-11-24 |
| RF4 | missing / erroring API | test_reputation_api "(RF4)..." | OFFLINE | 294 passed | pass | 2026-11-24 |
| RF5 | 1.3.0 peer | test_reputation "(RF5)..." | OFFLINE | 294 passed | pass | 2026-11-24 |
| - | window builds and fills reputation rows; `/ps rep` runs | test_load (mode loop incl. reputation; row fill confirmed reached) | OFFLINE | 294 passed | pass | 2026-11-24 |
| - | two members see each other's standings | two guild members on 1.4.0 | NOT-VERIFIED | needs user + second player | | |

## In-game checklist (things only the user can do)
- [x] `powershell tools/deploy.ps1`, restart the game, `/console scriptErrors 1`.
- [x] `/psd rep`: first line says `GetFactionInfoByID yes` and `faction API answers yes`; every faction you have met
      shows its client name (no `?`) and your standing. Send the output (character names removed).
- [x] Misc Items -> dropdown "Reputation": your own rows appear (name marked `*`), Standing coloured, Progress `x/y`.
- [x] Click the Standing and Progress titles: order changes; Columns menu shows "Updated".
- [x] Faction dropdown: "All factions" + the factions in the list; choosing one filters, the label follows.
- [x] Search "thorium" (also in a German client), "honored"/"wohlwollend", a member name.
- [x] Hover a row: hint lines, reached standings green, next one white with ">", grey footer with the date.
- [x] Click another member's name in the Player column: the chat opens a whisper to them; clicking beside the name or on
      your own name selects the row instead.
- [ ] Gain reputation (kill a mob of a tracked faction): after ~5 s a level change is shared; progress after 30 min.
- [ ] Second member on 1.4.0: their rows appear after they log in; a 1.3.0 member still syncs recipes/orders.

## Accepted gaps
- none yet

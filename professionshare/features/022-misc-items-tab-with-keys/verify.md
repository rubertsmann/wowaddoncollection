# 022 Misc items tab with keys: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> 235 passed, 0 failed
Result after work:    `luajit tests/run.lua` -> 257 passed, 0 failed (three runs)

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence (output line, file, screenshot) | Result | Date |
|---|---|---|---|---|---|---|
| R1 | Tab "Misc Items", mode dropdown, mode kept, recipe items unchanged | `test_load` (window builds, all three modes refresh), `test_access_model` "misc tables: mode setting validated...", existing `test_offers_model` | OFFLINE (logic, stubbed frames) | 257 passed | pass; look and dropdown NOT verified in game | 2026-11-23 |
| R2 | Keys mode rows, search, holders, whisper | `test_access_model` "key rows: ..." (2 tests) | OFFLINE | 257 passed | pass (row content); click/whisper NOT verified in game | 2026-11-23 |
| R3 | Key = class 13 or listed, deny-list | `test_access` "deny-listed one-run keys...", `test_items_api` "access api: keys from bags and key ring..." | OFFLINE | 257 passed | pass | 2026-11-23 |
| R3 | the listed ids on Forever | dev key probe, devChecks.keyProbe from WTF; live access records of six members | IN-GAME | all 10 listed ids resolve (names match, class 13, Seal/Amulet class 4); 277507 "Kanalisationsschlüssel von Dalaran", 267089 "Lagerschlüssel von Krol'Dok" class 13; key ring yes, quest API yes | pass | 2026-11-24 |
| R4 | key ring on Forever | live access records | IN-GAME | members' keys stored under "keyring" and "bank" | pass | 2026-11-24 |
| R2b | listed keys nobody holds get a row (user request) | `test_access_model` "key rows: ..." | OFFLINE | 332 passed | pass; look NOT verified in game | 2026-11-24 |
| R4 | Bags, key ring, bank while open; bank kept | `test_items_api` "access api: keys...", `test_access` "(RF2) ..." | OFFLINE | 257 passed | pass; key ring on Forever unknown | 2026-11-23 |
| R5 | Attunements from quests/items | `test_items_api` "access api (RF3) ...", `test_access_model` "attunement rows ..." | OFFLINE | 257 passed | pass; quest ids NOT verified in game | 2026-11-23 |
| R6 | Own record, arev, pulled on change, last | `test_access` "access sync: a changed record reaches a peer once; afterwards only arev travels" | OFFLINE | 257 passed | pass | 2026-11-23 |
| R7 | Only ids/keys/booleans sent; names local | `test_access` sanitize test, `test_locale_files` | OFFLINE | 257 passed | pass | 2026-11-23 |
| R8 | Party/raid portrait icon | not built; moved to 054 | - | - | moved | 2026-11-28 |
| ALL | the tab in game | user | IN-GAME | user: "ps 22 seems to working" | pass | 2026-11-28 |
| T-col | Per-mode columns, sort, column menu (user request "rework the table view") | `test_access_model` "misc tables: ..." (2 tests), "recipe table keeps its API on top of ColumnTable", existing `test_recipe_table` | OFFLINE | 257 passed | pass; header/columns menu look NOT verified in game | 2026-11-23 |
| RF1 | Forged author, oversized, bad values -> dropped | `test_access` "(RF1) sanitize ...", "access sync (RF1) ..." | OFFLINE | 257 passed | pass | 2026-11-23 |
| RF2 | Bank closed keeps bank keys; no key ring still scans bags | `test_access` "(RF2) ...", `test_items_api` "access api: keys ..." | OFFLINE | 257 passed | pass | 2026-11-23 |
| RF3 | No quest API / errors -> unknown, no rev churn | `test_access` "(RF3) ...", "nothing held and nothing known creates no record", `test_items_api` "(RF3)" | OFFLINE | 257 passed | pass | 2026-11-23 |
| RF4 | 2.3 peer keeps syncing, ignores access | `test_access` "access sync (RF4) ..." (simulated by removing the record kind) | OFFLINE | 257 passed | pass; real 2.3 client NOT verified | 2026-11-23 |
| RF5 | Recipe items mode unchanged after rename | `test_offers_model`, `test_offers`, `test_load` | OFFLINE | 257 passed | pass | 2026-11-23 |

## In-game checklist (things only the user can do)
- [ ] Deploy (`powershell tools/deploy.ps1`), restart the game (new files: `/reload` is not enough), `/console scriptErrors 1`.
- [ ] `/ps access scan` on a character with a dungeon key and one without: expected a "key ring yes/NO" and "quest API yes/NO" line, the keys per location with names, one line per raid with quest results. Send the output (screenshot).
- [ ] Dev build: Debug tab "Test-Schlüssel" and "Test-Naxxramas" fill Keys and Attunements with "Fake Keyholder" (buttons absent in the live build).
- [ ] Open the window, tab "Sonstiges": dropdown shows Rezept-Gegenstände / Schlüssel / Zugänge; each mode shows its own columns; "Spalten" menu toggles columns; clicking a column title sorts.
- [ ] Keys mode: your key is listed with `*`; selecting it shows holders and locations; icon click opens a whisper with the item link.
- [ ] Two members: a key looted by member A shows up for member B within about a minute, and `/ps export` shows "access records held".
- [ ] Tell which raids exist on Forever (rows for missing content can be hidden).

## Accepted gaps
- The detailed in-game checklist items and two-member sync: closed at the user's status review (2026-11-28) ("seems to working"). R8 continues as 054.

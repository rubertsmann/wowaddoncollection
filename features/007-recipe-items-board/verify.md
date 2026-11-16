# 007 Recipe items board: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> 99 passed, 0 failed
Result after work:    `luajit tests/run.lua` -> 127 passed, 0 failed

Mutation check (2026-11-16): removing the own-item dib rule, the OFFERS sender check, the "only scanned locations are replaced" rule, hide expiry, or the monotonic dib timestamp each made at least one test fail.

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence | Result | Date |
|---|---|---|---|---|---|---|
| R1 scan logic | bound / non-recipe / unknown skipped, counts add up, per-location replace | tests/test_items_api.lua (stubbed globals), test_offers.lua "update keeps locations..." | OFFLINE | 127 passed, 0 failed | pass | 2026-11-16 |
| R1 real client APIs | bags, bank, reagent bank, mail, guild bank tab, own auctions return data on Forever | `/tsd offers` in game (checklist) | NOT-VERIFIED | needs the user | - | - |
| R2 | record shared over HELLO(orev) -> WANTO -> OFFERS | test_offers.lua "sync: offers travel..." (codec round trip) | OFFLINE | 127 passed, 0 failed | pass | 2026-11-16 |
| R2 two clients | two real guild members see each other's offers | checklist | NOT-VERIFIED | needs a second member | - | - |
| R3 | tab lists offers, search, only-my-professions, locations | test_offers_model.lua; test_load.lua builds and refreshes the tab on stubs | OFFLINE | 127 passed, 0 failed | pass (layout not checked) | 2026-11-16 |
| R3 layout | tab looks right, rows readable, tooltip works | checklist | NOT-VERIFIED | needs the user (screenshot) | - | - |
| R4 | several dibs, listed oldest first, toggle off by pressing again, only the author changes a dib | test_offers.lua "dib toggles...", "several players...", "only the author..." | OFFLINE | 127 passed, 0 failed | pass | 2026-11-16 |
| R5 | local hide, returns when the owner's rev changes, dib kept | test_offers.lua "hiding is local..." | OFFLINE | 127 passed, 0 failed | pass | 2026-11-16 |
| R6 | vanished item drops my stale dib; unknown owner keeps it | test_offers.lua "Maintain..." | OFFLINE | 127 passed, 0 failed | pass | 2026-11-16 |
| R7 | hostile records rejected, persisted data re-validated, clean empties in place | test_offers.lua "Sanitize...", "persisted data...", "/ts clean...", "sync: hostile OFFERS..." | OFFLINE | 127 passed, 0 failed | pass | 2026-11-16 |
| RF1 | location not readable keeps its old state | test_offers.lua "update keeps locations...", test_items_api.lua "bank ... only while open" | OFFLINE | 127 passed, 0 failed | pass | 2026-11-16 |
| RF2 | unknown / other-class item ids not listed, missing APIs do not error | test_offers_model.lua, test_items_api.lua "no container API" | OFFLINE | 127 passed, 0 failed | pass | 2026-11-16 |
| RF3 | forged / oversized OFFERS dropped | test_offers.lua "Sanitize...", "sync: hostile...", "only the author..." | OFFLINE | 127 passed, 0 failed | pass | 2026-11-16 |
| RF4 | dib toggled twice, two dibbers | test_offers.lua | OFFLINE | 127 passed, 0 failed | pass | 2026-11-16 |
| RF5 | hide then sync; clean | test_offers.lua | OFFLINE | 127 passed, 0 failed | pass | 2026-11-16 |
| Compat 0.3.x | 0.3.x ignores the new HELLO field and messages | receiver side of 2.1 tested ("hello without orev"); 0.3.x behaviour reasoned from `Sync` dropping unknown types | READ-ONLY | - | not run against a real 0.3.x | 2026-11-16 |

## In-game checklist (things only the user can do)
- [ ] Run `powershell tools/deploy.ps1` (regenerates the dev TOC, a new file was added), restart the game, then `/tsd offers`: note which "APIs:" entries say NO.
- [ ] Put a tradeable recipe item (e.g. Recipe: Savory Deviate Delight) in your bags, `/tsd offers scan`: it appears under `bag:`; a soulbound recipe does NOT.
- [ ] Open the bank, move the recipe there: `bank:` lists it; close the bank and run `/tsd offers`: it is still listed (last state kept).
- [ ] Open the mailbox with a recipe attached, the guild bank tab with one, list one at the auction house: `mail:`, `gbankN:`, `auction:` show up (or tell me which do not).
- [ ] Open `/tsd`, tab "Available" (Verfügbar): your item is listed with icon, location text, tooltip on hover.
- [ ] Second guild member on this build: you see each other's items; dibs appear on the other side within a few seconds; pressing the button again removes it.
- [ ] "Remove from my list" hides an offer; it comes back after the owner's list changes.
- [ ] `/tsd version` shows `protocol 2.1, schema 3`; a 0.3.x client in the guild keeps working (it just ignores offers).

## Accepted gaps
- none yet

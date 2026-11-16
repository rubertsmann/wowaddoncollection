# 011 Item categories and text search: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> 187 passed, 0 failed
Result after work:    `luajit tests/run.lua` -> 194 passed, 0 failed
UI smoke (stubbed client, scratchpad harness clicks11.lua): profession menu radios, category menu groups with counts,
tick -> "Kategorie (1)", profession pick clears categories, search "beweg" finds the buff food after the text pump; same
without menu templates (fallback cycle buttons, InputBoxTemplate) without errors.

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence | Result | Date |
|---|---|---|---|---|---|---|
| R1 | category selector | `categories: key from class, subclass and slot...`, `categories: filter by checked categories...`, `categories: list per profession...`; checklist 2 | OFFLINE + IN-GAME | test run; user: "checked ... the category" | pass | 2026-11-16 |
| R2 | profession dropdown | checklist 1 | IN-GAME | user: "checked ... also dropdown" | pass | 2026-11-16 |
| R3 | free-text search | `search: free text, words in any order...`; checklist 4 | OFFLINE + IN-GAME (simple words); effect-text match in game NOT-VERIFIED | test run; user: "checked searching for simple words" | pass | 2026-11-16 |
| R4 | text local only | `Core/ItemText.lua` writes only `db.itemText`; no Comm/Sync call | READ-ONLY | | | 2026-11-16 |
| R5 | dev probe | probe run in game, SavedVariables read | IN-GAME | devProbe.at 2026-11-16 22:54:29 (dev SavedVariables, not copied) | pass | 2026-11-16 |
| RF1 | item not cached | `search: item text cache reads once, retries uncached items...` | OFFLINE | test run | pass | 2026-11-16 |
| RF2 | no `produces` | `categories: filter by checked categories...` ("none") | OFFLINE | test run | pass | 2026-11-16 |
| RF3 | many items | pump 8 per 0.2 s while the tab is open (`UI/Window.lua`) | READ-ONLY | | | 2026-11-16 |
| RF4 | language change | `search: item text cache ... starts over with a new language` | OFFLINE | test run | pass | 2026-11-16 |
| - | escape sequences in tooltip text | `search: tooltip text drops the name line and every escape sequence...` | OFFLINE | test run | pass | 2026-11-16 |
| - | /ts clean | `search: Clean also drops the item text cache` | OFFLINE | test run | pass | 2026-11-16 |

## In-game checklist (`/console scriptErrors 1` first; restart the game once: new file in the TOC)
- [x] 1. Recipes tab: the profession control is a dropdown listing "All" and every profession; picking one filters the list.
- [x] 2. "Kategorie" opens a menu with headings (Rüstung, Verbrauchbar, ...) and checkboxes with counts; ticking "Füße" shows only boots, the button reads "Kategorie (1)"; ticking a second category adds those; "Alle anzeigen" clears.
- [ ] 3. Picking another profession clears the categories and the menu shows only that profession's categories.
- [ ] 4. (simple words checked in game; effect words such as `beweglichkeit` not confirmed) Search box (magnifier, clear button): `beweglichkeit` finds agility food/gear after a second or two; `leder brust` finds leather chest pieces; the clear button empties it.
- [ ] 5. `/tsd clean` then search again: texts are read again without errors.

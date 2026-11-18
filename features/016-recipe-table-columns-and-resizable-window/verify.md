# 016 Recipe table columns and resizable window: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> `211 passed, 1 failed` (pre-existing: `Core/Play/Slots.lua exists but is not in TalentShare.toc`; the file is staged as deleted by feature 015 but present on disk)
Result after work:    `luajit tests/run.lua` -> `223 passed, 0 failed` (the stray `Core/Play/Slots.lua` was removed with feature 015)

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence (output line, file, screenshot) | Result | Date |
|---|---|---|---|---|---|---|
| R1 | Name in item-quality colour; default colour without item / uncached | `recipe table: quality colours, unknown quality gives no colour`, `recipe rows: item details and skill are filled...`; colour on screen: in game | IN-GAME | suite 222 passed; user report 2026-11-18: "works as expected" (dev build /tsd) | pass | 2026-11-18 |
| R2 | Table with header and the six columns | `recipe table: defaults are all columns on...`; look: in game | IN-GAME | suite; user report 2026-11-18: "works as expected" (dev build /tsd) | pass | 2026-11-18 |
| R3 | Column checkboxes in options, several on, saved | `recipe table: switching columns off hides them, name always stays`; panel: in game | IN-GAME | suite; user report 2026-11-18: "works as expected" (dev build /tsd) | pass | 2026-11-18 |
| R4 | Default item level desc; missing last; header click; option | `recipe sort: item level highest first, missing values last, ties by name`, `recipe table: header click picks a column...` | IN-GAME | suite; user report 2026-11-18: "works as expected" (dev build /tsd) | pass | 2026-11-18 |
| R5 | Name takes the rest, no gaps | `recipe table: layout gives name the rest...` | OFFLINE | suite; user report 2026-11-18: "works as expected" (dev build /tsd) | pass | 2026-11-18 |
| R6 | Resize grip, min/max, size saved | `recipe table: window size is clamped...`; grip: in game | IN-GAME | suite; user report 2026-11-18: "works as expected" (dev build /tsd) | pass | 2026-11-18 |
| R7 | All tabs scale | `load: all TOC files run in order...` (builds the window against stubs) | IN-GAME | test_load passes; user report 2026-11-18: "works as expected" (dev build /tsd) | pass | 2026-11-18 |
| R8 | Invalid saved values -> defaults | `recipe table: corrupted or unknown saved settings fall back to defaults (RF2)` | OFFLINE | suite; user report 2026-11-18: "works as expected" (dev build /tsd) | pass | 2026-11-18 |
| RF1 | Uncached items: blank + last, redraw debounced | sort test (nil last both directions); debounce: READ-ONLY (`UI/Window.lua` recipes OnUpdate, 1 s) | IN-GAME | suite; user report 2026-11-18: "works as expected" (dev build /tsd) | pass | 2026-11-18 |
| RF2 | Corrupted settings | see R8 | OFFLINE | suite; user report 2026-11-18: "works as expected" (dev build /tsd) | pass | 2026-11-18 |
| RF3 | All columns off / narrow | layout test | OFFLINE | suite; user report 2026-11-18: "works as expected" (dev build /tsd) | pass | 2026-11-18 |
| RF4 | Resize while scrolled to bottom | `UI/Table.lua` clampOffset in UpdateLayout / SetData | IN-GAME | -; user report 2026-11-18: "works as expected" (dev build /tsd) | pass | 2026-11-18 |
| RF5 | Escaped names inside colour | `recipe rows: a peer's recipe name with markup stays escaped...` | OFFLINE | suite; user report 2026-11-18: "works as expected" (dev build /tsd) | pass | 2026-11-18 |

## In-game checklist (things only the user can do)
Setup: `powershell tools/deploy.ps1` (done 2026-11-18, dev TOC regenerated), restart the game, `/console scriptErrors 1`, open `/tsd`.
- [x] Recipes tab: header row Name / Item level / Req. level / Profession / Skill / Category; names coloured (green/blue/purple items); enchant-type recipes white with empty level cells at the bottom.
- [x] Default order: highest item level first. Click "Req. level": sorted by it, arrow shown; click again: direction flips.
- [x] `/tsd options` -> "Recipe list": untick Skill and Category -> columns vanish at once, Name widens. Sort by / Descending buttons change the window's order. `/reload`: choices kept.
- [x] Drag the grip at the bottom right: window grows; Recipes table gets more rows and a wider Name column, detail panel stays at the right; Orders, Available, Debug lists grow; buttons stay at the bottom. Cannot shrink below the original size. `/reload`, reopen: size kept.
- [x] Scroll the Recipes list to the bottom, then make the window taller: no empty rows at the top, slider still works.
- [x] The sort arrow texture shows (not a green box). If it does not, report it: `Interface\Buttons\UI-SortArrow` is assumed to exist on Forever.

## Accepted gaps
- none yet

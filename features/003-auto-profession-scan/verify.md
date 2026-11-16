# 003 Auto profession scan: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` | `MULTI-CLIENT` | `READ-ONLY` | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> 51 passed, 0 failed
Result after work:    `luajit tests/run.lua` -> 59 passed, 0 failed

| ID | Requirement / Review Focus | How verified | Level | Evidence | Result | Date |
|---|---|---|---|---|---|---|
| R1 | One click / `/ts autoscan` scans every profession in turn | `autoscan: opens every profession in turn, ...` (state machine with a fake client) | OFFLINE (logic) / NOT-VERIFIED (real client: does OpenTradeSkill exist and take 165/185/393?) | tests/test_autoscan.lua | logic pass | 2026-11-16 |
| R2 | Automatic first-open run when data is missing | `autoscan: onlyMissing ...`; UI hook read, never run | OFFLINE (filter) / READ-ONLY (UI hook) | tests/test_autoscan.lua | partly | 2026-11-16 |
| R3 | Safe: combat, busy window, stuck list, window closed at end | `autoscan: refuses to start ...`, `... combat during the run ...`, `... waits for lists that load late ...` | OFFLINE | tests/test_autoscan.lua | pass | 2026-11-16 |
| R4 | Client without the API: message, no error | `load: all TOC files run ...` (OpenTradeSkill missing -> Start returns false) | OFFLINE | tests/test_load.lua | pass | 2026-11-16 |
| R5 | `NEW_RECIPE_LEARNED` rescans | code read (registered via pcall, so an unknown event is harmless) | READ-ONLY | Core/Events.lua | not run | 2026-11-16 |
| R6 | Localized strings + hint | `locale files: ...`, `ui lint: ...` | OFFLINE | tests/test_locale_files.lua | pass | 2026-11-16 |
| RF1 | Combat mid-run stops and closes | `autoscan: combat during the run ...` | OFFLINE | tests | pass | 2026-11-16 |
| RF2 | Player's own window is never hijacked | `autoscan: refuses to start ...` (window open) | OFFLINE | tests | pass; `IsProfessionWindowShown` frame names (ProfessionsFrame, TradeSkillFrame, CraftFrame) unverified on Forever | 2026-11-16 |
| RF3 | Stuck profession does not stall | `autoscan: waits for lists ...` (bounded retries) | OFFLINE | tests | pass | 2026-11-16 |
| RF4 | Stale timers do nothing | `autoscan: Cancel invalidates pending timers ...` | OFFLINE | tests | pass | 2026-11-16 |
| RF5 | Unsupported client | see R4 | OFFLINE | tests | pass | 2026-11-16 |

## In-game checklist (things only the user can do)
- [ ] `/reload`, then `/tsd i18n`: paste the line "auto scan: OpenTradeSkill true|false, CloseTradeSkill true|false".
- [ ] No profession window open, `/tsd autoscan`: chat shows "Scanning your professions ..." then "Gescannt: Kochkunst 10, Lederverarbeitung 12, Kürschnerei 1" (numbers will differ); windows open and close by themselves.
- [ ] `/tsd`: the recipe list is filled and the "Berufe scannen" button is at the top right of the Recipes tab.
- [ ] Fresh state (delete nothing: use `/tsd autoscan` once, or log in with an empty database): opening `/tsd` for the first time starts the scan by itself.
- [ ] With a profession window open, the button says "Schließe zuerst dein Berufsfenster ...".
- [ ] Start a scan and enter combat (or just verify it does not start in combat).
- [ ] If nothing opens: paste what chat says; fallback is the manual hint.

## Accepted gaps
- none yet

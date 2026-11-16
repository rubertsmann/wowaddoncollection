# 003 Auto profession scan: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-16 10:27 | PLAN | Feature created
- Did: scaffolded `features/003-auto-profession-scan/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-16 10:28 | DECISION | trigger and API
- Did: user report: "K is for professions and it shows 0 recipes known ... after manually cycling through all pages it showed 11 recipes ... can this somehow be automated". Decided: `C_TradeSkillUI.OpenTradeSkill(skillLineID)` opens each profession in turn (feature-detected, since it is not in the probe's API list); button + automatic first-open run + `/ts autoscan`; window flashing accepted
- Result: spec.md written
- Evidence: features/003-auto-profession-scan/spec.md
- Next: T1 state machine with tests

## 2026-11-16 10:29 | BUILD | T1-T3 AutoScan, Api wrappers, UI button, auto-run, locale strings
- Did: new `Core/AutoScan.lua` (pure state machine + wiring + `/ts autoscan [on|off]`); `Core/Api.lua` (CanOpenProfession, OpenProfession, CloseProfession, InCombat, IsProfessionWindowShown; `/ts i18n` now reports whether OpenTradeSkill exists); `Core/Events.lua` (NEW_RECIPE_LEARNED); `UI/Window.lua` ("Scan professions" button, auto-run on first open, new empty hint); `Locales/deDE.lua` (9 strings); TOC; `Core/Scanner.lua` (`/ts scan` now says whether a profession recipe list is open); `tests/test_autoscan.lua` (8 tests), `tests/test_load.lua` extended
- Result: found one test-ordering mistake of mine (combat flag set after the first timer had already opened the next profession), fixed in the test, not the code
- Evidence: `luajit tests/run.lua` -> 59 passed, 0 failed (51 before)
- Next: user checks in game (verify.md checklist): the whole feature depends on `OpenTradeSkill` existing and accepting ids 165/185/393

## 2026-11-16 10:30 | BLOCKED | in-game verification needs the user
- Did: nothing; waiting
- Result: NOT-VERIFIED: that OpenTradeSkill exists on Forever, that a second open switches the list, how the window looks while scanning
- Evidence: n/a
- Next: user runs `/reload`, `/tsd i18n` (look at the "auto scan:" line), then `/tsd autoscan` and pastes the chat output

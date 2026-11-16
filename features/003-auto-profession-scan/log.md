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

## 2026-11-16 10:34 | DEVIATION | automatic scan on every window open, default on
- Did: user asked "auto scan should default be on - so opening the window auto scans". Old behaviour: once per session, only if recipes were missing (and `autoScan` was merely "not false"). New: `Store.Init` sets `ui.autoScan = true`; `UI/Window.lua` OnShow calls `AutoScan.Auto()` on every open; Auto scans everything if the last automatic scan is 10+ minutes old, else only missing professions; "unsupported" is reported once per session; `/ts clean` resets `lastAutoScan`; `AutoScan.Run(manual, onlyMissing)`; spec R2, doc.md and verify.md updated
- Result: window flashing is bounded to once per 10 minutes (kept deliberately: the user did not ask for a scan on every single open)
- Evidence: `luajit tests/run.lua` -> 61 passed, 0 failed (60 before; new test "autoscan: opening the window scans by default ...")
- Next: in-game check (verify.md): open `/tsd` twice within 10 minutes (second time only scans if something is missing), and after 10 minutes (scans everything again)

## 2026-11-16 10:38 | DEVIATION | scan button became a small reload symbol
- Did: user asked "replace the button 'berufe scan' with a small reload symbol". `UI/Window.lua`: 20x20 icon button (texture `Interface\Buttons\UI-RefreshButton`, highlight, pressed offset) with tooltip "Scan professions" + one explanatory line; hint text now says "reload symbol at the top right"; `Locales/deDE.lua` updated; README, doc.md, verify.md adjusted
- Result: the texture path is the stock retail refresh icon; whether it exists on Forever is NOT-VERIFIED (a missing texture would show as a blank/green square)
- Evidence: `luajit tests/run.lua` -> 61 passed, 0 failed (lint tests confirm the new strings exist in deDE)
- Next: user opens `/tsd` and looks at the top right of the Recipes tab

## 2026-11-16 10:44 | VERIFY | first in-game run: partly works, "Interface-Aktion ... Addon fehlgeschlagen"
- Did: user reported "I still need to open the talent window once and need to cycle through the views" and the red message "Interface-Aktion auf Grund eines Addons fehlgeschlagen" (Blizzard's generic INTERFACE_ACTION_BLOCKED, no addon name). Read `TalentShare-Dev.lua`: `ui.autoScan = true`, `ui.lastAutoScan` set (so the automatic run started, i.e. OpenTradeSkill exists and nothing blocked the start), Kochkunst 11 recipes and Kürschnerei 1 stored, **Lederverarbeitung 0**; debug log has no autoscan steps (the run was not logged)
- Result: OpenTradeSkill exists on Forever (R4/R1 partly confirmed); the run did not complete for all professions; cause of the blocked-action message unknown (suspect: opening/closing the Blizzard profession window from tainted code)
- Evidence: `TalentShare-Dev.lua` (SavedVariables, read 2026-11-16)
- Next: added step logging (`ns.Debug.Log("autoscan", ...)`: start/open/check/finish incl. the pcall error), 6 retries (list gets ~7.5 s), deferred start (0.5 s after our window shows, not inside OnShow); tests 62 passed. User: `/console taintLog 1`, `/reload`, open `/tsd`, wait 15 s, `/reload`; I read `_forever_\Logs\taint.log` and the SavedVariables debug log

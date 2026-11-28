# 005 Profession scan buttons: log

Append only. Newest entry at the bottom. The last entry must say what to do next.

## 2026-11-16 10:47 | DECISION | replace the blocked auto scan with secure profession buttons
- Did: user (German): "Deine Berufe werden gescannt ... -> 'öffne das Berufsfenster selbst' - kein Berufsfenster wurde jemals geöffnet. Es gibt also keine passive Möglichkeit ... Scheint so als wäre das tabbed Talent-Menü das Problem. Man muss jeden Tab einzeln anwählen. Gibt es vielleicht Makros mit denen man direkt die entsprechende Seite öffnen kann." Conclusion: `OpenTradeSkill` from addon code is blocked on Forever (nothing opened + "Interface-Aktion auf Grund eines Addons fehlgeschlagen"). The macro idea is the standard way: `/cast <profession>` run by a real click on a secure button
- Result: feature 003 abandoned (superseded by this one); the pcall in the old code reported success because a blocked call raises no Lua error, so the run looked fine and found 0 recipes
- Evidence: user report; `TalentShare-Dev.lua` (lastAutoScan set, Lederverarbeitung 0 recipes); `Logs\Professions.log` empty, `Logs\*.log` contain no addon error
- Next: implement

## 2026-11-16 10:50 | BUILD | secure button bar, removal of AutoScan
- Did: removed `Core/AutoScan.lua`, `tests/test_autoscan.lua`, `/ts autoscan`, the reload symbol, `Api.OpenProfession/CloseProfession/CanOpenProfession/IsProfessionWindowShown`; added `Model.OwnProfessions`, the profession bar in `UI/Window.lua` (SecureActionButtonTemplate, `type=macro`, `/cast <name>`, counters, tooltip, combat deferral), 3 deDE strings (obsolete ones removed), a build/refresh smoke test with stubbed widgets in `tests/test_load.lua`
- Result: tests 53 passed, 0 failed; mutation check (typo in a Window call) made the build test fail as intended
- Evidence: `luajit tests/run.lua` -> 53 passed, 0 failed. Caught on the way: `sed` with a backslash pattern silently failed to remove `Core\AutoScan.lua` from the TOC, the load test failed correctly
- Next: user checks in game (verify.md): first `/cast Kochkunst` in chat, then the icons in `/tsd`

## 2026-11-16 10:51 | BLOCKED | in-game verification needs the user
- Did: nothing; waiting
- Result: NOT-VERIFIED: that `/cast <profession>` opens the window on Forever, that the secure button works the same, the layout of the icons
- Evidence: n/a
- Next: user runs the checklist in verify.md and reports

## 2026-11-16 10:56 | VERIFY | first in-game result: 2 of 3 buttons work
- Did: user: "the 3 talents button appear and open the correct menu besides Kürschnerei that doesn't open the menu". Kochkunst and Lederverarbeitung open their window via `/cast <name>` on the secure button: the approach works on Forever (R1 partly IN-GAME confirmed). Kürschnerei (Skinning) casts only the skinning spell. From the earlier probe: Skinning has `numSpells = 2` (spellOffset 67), the other professions 1; and a Skinning recipe list exists (recipe 1229517 Lagerstuhl was stored under Kürschnerei by the 0.1.0 scan), so some spellbook entry of Skinning opens that page
- Result: unknown which spell; implemented a data-driven attempt: `Api.GetPlayerProfessions` now returns `spells` (names of the profession's spellbook entries via `Api.SpellBookEntry`, trying C_SpellBook.GetSpellBookItemInfo/Name, GetSpellBookItemName, GetSpellName); `Model.CastMacro` builds `/cast <profession>` + up to 2 more lines for the other entries; `/ts i18n` prints offset, numSpells, spell names, ids, passive flags and the final macro per profession
- Evidence: `luajit tests/run.lua` -> 54 passed, 0 failed (new test for CastMacro incl. line-break and duplicate handling)
- Next: user runs `/reload`, `/tsd i18n` and pastes the lines starting with "profession", "spellOffset", "book[" and "spellbook APIs"; then clicks the Kürschnerei icon again. If it still does nothing, the i18n output tells which spell to target

## 2026-11-16 11:03 | BUILD | everything needed to diagnose Skinning is written to the persistent debug log
- Did: user: "logge diese Informationen einfach - ich werde dann die entsprechenden Befehle ausführen". Now logged to `db.debug` (SavedVariables, readable after /reload): `professions` (once per change: name#skillLineID, spellOffset, numSpells, spellbook entries name#spellID(passive)), `click` (profession button clicked + the macro it ran), `event TRADE_SKILL_SHOW` (a profession window really opened), `scan changed|same <window profession>#<id> recipes=<n>` (what the scan saw), `uierror` (the game's red error text within 6 s after a button click), and every `/ts i18n` line (`i18n`). `DATA_CHANGED` now fires after every scan so the button counters stay current
- Result: no need to copy chat output; the next step is reading `TalentShare-Dev.lua`
- Evidence: `luajit tests/run.lua` -> 54 passed, 0 failed
- Next: user: `/reload`, open `/tsd`, click the Kürschnerei icon, wait ~5 s, run `/tsd i18n`, then `/reload` (or log out) so the file is written. Claude reads `WTF\Account\<ACCOUNT>\SavedVariables\TalentShare-Dev.lua`

## 2026-11-16 11:08 | BUILD | pulsing "CLICK HERE ->" next to the profession buttons
- Did: user: "add a visual highlight to the ui e.g. 'CLICK HERE ->' next to the button as long as all talents are at 0". `Model.NeedsScanHint(rows)` (pure: professions exist and every count is 0); `UI/Window.lua`: a gold, pulsing label (alpha 0.55-1.0, 3 rad/s) anchored to the left of the leftmost profession button, shown/hidden by `refreshBar`; `Locales/deDE.lua`: "HIER KLICKEN ->"; test `model: the CLICK HERE hint shows only while ...`
- Result: the label disappears as soon as one profession has a stored recipe (the counters refresh after every scan)
- Evidence: `luajit tests/run.lua` -> 55 passed, 0 failed; the label's look and position are NOT-VERIFIED in game
- Next: user checks the label in game; Skinning diagnosis still waits for the debug log (previous entry)

## 2026-11-26 16:36 | BUILD | profession buttons cast the window spell by id; dev spell probe to check it per profession
- Did: bug report (guild feedback + user): the Skinning button does not open the Skinning recipe window. Debug log: Skinning has 2 spellbook entries, `Sonnen#1278068` (Forever) and `Kürschnerei#8618` (classic Skinning, the gathering spell, same name as the profession); the button ran `/cast Kürschnerei` + `/cast Sonnen` by name. New static table `Core/Data/ProfessionSpells.lua` (skill line -> window spell ids of every rank, plus gathering ids that never open a window); `Model.OpenAction` picks the spell by id (static, else first non-gathering non-passive entry, else the old name macro); profession buttons and the Craft button use `type=spell, spell=<id>`; `/ps i18n` prints what each button casts. Temporary dev probe `/psd spellprobe` (Dev tools -> Probes): a secure button that casts every spellbook spell of every own profession by id, plus `/cast <profession>` by name, one per click, reads the open window 1.5 s later and compares it with the static table; result in `devChecks.spellProbe`
- Result: language-independent selection; Skinning -> 1278068 is an ASSUMPTION (first spellbook entry) until the probe confirms it
- Evidence: `luajit tests/run.lua` -> 336 passed, 0 failed (tests/test_profession_spells.lua; spell probe candidates in tests/test_load.lua)
- Next: user restarts the game (new file in the TOC, /reload is not enough), runs `/psd spellprobe`, clicks through every test (Esc between clicks), then `/reload`; Claude reads `devChecks.spellProbe` from ProfessionShare-Dev.lua, fixes the static table where it differs, then removes the probe

## 2026-11-26 16:55 | VERIFY | spell probe run 1: every click casts twice; Sonnen is a camp spell; the window spells are hidden spells
- Did: read `devChecks.spellProbe` (2026-11-26 16:52, 1.4.2-dev) from ProfessionShare-Dev.lua
- Result: (1) secure buttons registered for AnyUp+AnyDown cast TWICE per click (2x UNIT_SPELLCAST_SUCCEEDED; the second cast toggles the window closed: Cooking ended with no window). (2) `Sonnen` 1278068 is "adds functions to a wilderness camp", not the Skinning window; the old macro opened Skinning with line 1 and closed it with line 2. (3) `/cast <profession name>` resolves to hidden spells not in the spellbook: Leatherworking 1240961, Skinning 1240974 (opened Kürschnerei, 2 recipes), Cooking 1240956. Spellbook spell 8618 cast nothing
- Evidence: devChecks.spellProbe results 1-7 (events per click)
- Next: static table = these hidden ids, one cast per click (next entry)

## 2026-11-26 16:55 | BUILD | static window spells by id, one cast per click, probe run 2
- Did: `Core/Data/ProfessionSpells.lua` now maps skill line -> window spell (165 1240961, 185 1240956, 393 1240974); spellbook guessing removed; other professions fall back to a ONE-line `/cast <profession name>` (`Model.CastMacro`). Profession, Craft and probe buttons `RegisterForClicks("AnyUp")` only. Probe now tests per profession the static id and the name macro, and records which spell id each click cast (`castSpellIDs`) so new professions can be added to the table
- Result: offline green; in game NOT-VERIFIED
- Evidence: `luajit tests/run.lua` -> 334 passed, 0 failed
- Next: user `/reload`, `/psd spellprobe` (6 clicks, Esc between), click the real Skinning button, `/reload`; Claude reads devChecks.spellProbe; then remove the probe

## 2026-11-26 17:06 | VERIFY | spell probe run 2: an "AnyUp"-only secure button casts nothing
- Did: read devChecks.spellProbe (2026-11-26 17:05): 6 clicks recorded (PreClick ran), 0 UNIT_SPELLCAST events, no window, also for the name macro that worked in run 1
- Result: on Forever the secure action runs on the press; with only "AnyUp" registered nothing is cast. Run 1 (AnyUp+AnyDown) cast twice. Switched profession, Craft and probe buttons to RegisterForClicks("AnyDown")
- Evidence: `luajit tests/run.lua` -> 334 passed, 0 failed; user: "long pressed each time no window was shown"
- Next: user `/reload`, `/psd spellprobe` again (6 clicks, normal click, Esc between), click the real Skinning button, `/reload`

## 2026-11-26 17:08 | VERIFY | spell probe run 3: every profession opens by its static id, one cast per click; probe removed
- Did: read devChecks.spellProbe (2026-11-26 17:07, AnyDown only): Leatherworking 1240961, Skinning 1240974 (window Kürschnerei, 2 recipes), Cooking 1240956 (12 recipes) each cast exactly once by id; the name macro resolved to the same ids. Leatherworking by id: cast and TRADE_SKILL_SHOW, then closed within 1.5 s (user's Esc before the read); the name cast of the same id kept it open (42 recipes). Removed the temporary probe (DevProbe section, menu entry, /psd spellprobe, its load test); `ProfessionSpells` keeps only the static WINDOW table
- Result: R1 for Skinning IN-GAME via the probe's secure button (same attributes and click registration as the profession buttons); the real profession buttons themselves were not clicked after the change
- Evidence: devChecks.spellProbe in ProfessionShare-Dev.lua; `luajit tests/run.lua` -> 334 passed, 0 failed
- Next: user clicks the real Skinning, Leatherworking and Cooking buttons and the Craft button's "Open profession" once (one window each, stays open); then release

## 2026-11-26 17:16 | BUILD | members report their window spells in the HELLO; prod data and web have no ids
- Did: user asked for the other professions' ids from the web, the prod data, or a report like the build tag. Web: Wowhead has no page for 1240956/1240961/1240974 (404, Forever-only spells). Prod data (ProfessionShare.lua): 14 members, skill lines 129 164 165 171 182 185 186 197 202 333 356 393, recipes stored for all but Herbalism (Fishing has 1, Mining 14), but no spell ids anywhere. Built: `Events.lua` notes (skill line, spell) when a profession window opens within 2 s after my own cast (`db.windowSpells`, any way of opening counts); `Sync.lua` HELLO hook sends it as `wsp` (protocol stays 2.8, docs/protocol.md section 17); `Communication.lua` keeps peers' pairs only on the developer's client (`db.windowSpellReports`); `/ps spellids` lists them against `ProfessionSpells.WINDOW`
- Result: the table is filled by hand from the reports; the buttons never use reported ids
- Evidence: `luajit tests/run.lua` -> 338 passed, 0 failed (tests/test_profession_spells.lua: note/encode/decode bounds, collection, HELLO round trip)
- Next: release with this; after members opened their profession windows, user runs `/ps spellids` (or Claude reads windowSpellReports from ProfessionShare.lua) and the new ids go into WINDOW

## 2026-11-26 17:17 | NOTE | released in ProfessionShare 1.4.3
- Did: version 1.4.3 (protocol 2.8, schema 9), CHANGELOG + RELEASE_NOTES (EN/DE), tag professionshare/v1.4.3
- Result: shipped; the real profession buttons were not clicked in game after the AnyDown change (the probe's secure button with the same setup was)
- Evidence: `luajit tests/run.lua` -> 338 passed, 0 failed
- Next: user clicks Skinning/Leatherworking/Cooking and the Craft button once; after members played a few days, read windowSpellReports (`/ps spellids`) and add the new ids to ProfessionSpells.WINDOW

## 2026-11-28 10:37 | DONE | closed at the status review
- Did: user reviewed the feature's state
- Result: status done (obsolete)
- Evidence: user: "obsolete but worked" (2026-11-28)
- Next: none

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

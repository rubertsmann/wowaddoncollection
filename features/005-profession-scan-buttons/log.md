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

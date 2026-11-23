# 024 Feedback tab and hidden debug tab: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> 259 passed, 0 failed (release 1.2.2)
Result after work:    `luajit tests/run.lua` -> 268 passed, 0 failed

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence (output line, file, screenshot) | Result | Date |
|---|---|---|---|---|---|---|
| R1 | Feedback tab: type dropdown, template, Send, refusals | test_feedback "Add cleans the text, refuses ..."; test_load (tab builds, empty send refused) | OFFLINE (logic) / NOT-VERIFIED (look, dropdown, multi-line box) | suite 268 passed | logic pass | 2026-11-23 |
| R1b | sender: My messages menu, sent/delivered/waiting counters | test_feedback (delivered after the developer pulled, a new message waits, persisted marks re-validated); test_load (tab refresh) | OFFLINE (logic) / NOT-VERIFIED (look, menu) | suite 268 passed | logic pass | 2026-11-23 |
| R1c | Feedback tab only when the developer is in the roster | test_load (hidden, shown after the developer joins the roster, closes when they leave); test_feedback "the developer is found in a roster ..." | OFFLINE | suite 269 passed | pass | 2026-11-23 |
| R2 | own record, limits, developer-only pull and store | test_feedback "a member's record reaches the developer only ...", "a non-reader keeps only its own record" | OFFLINE | suite 268 passed | pass | 2026-11-23 |
| R3 | developer by name hash, no name in the repo | test_feedback uses a made-up hash; test_member_builds | OFFLINE | suite 268 passed | pass | 2026-11-23 |
| R4 | developer list, whisper, status buttons, status local | test_feedback "statuses toggle, survive a reload ..."; test_load refresh with a peer message | OFFLINE (logic) / NOT-VERIFIED (look, icons) | suite 268 passed | logic pass | 2026-11-23 |
| R5 | escaping, hostile records dropped | test_feedback "hostile records are dropped whole"; Window escapes every peer string (READ-ONLY) | OFFLINE + READ-ONLY | suite 268 passed | pass | 2026-11-23 |
| R6 | Debug tab hidden in live until /ps debug | test_load (live: debug -> recipes; /ps debug -> debug; dev: always) | OFFLINE | suite 268 passed | pass | 2026-11-23 |
| R7 | dev "Fake feedback" | test_load (dev build: valid record, /ps fakefeedback only in dev) | OFFLINE | suite 268 passed | pass | 2026-11-23 |
| R8 | bug snapshot | test_feedback "snapshot keeps versions, the newest problems and recent lines within 1200 bytes", "only the 3 newest messages keep a snapshot" | OFFLINE | suite 268 passed | pass | 2026-11-23 |
| RF1 | GUILD broadcast to a non-developer not stored | test_feedback (bystander OnMessage FEEDBACK) | OFFLINE | suite 268 passed | pass | 2026-11-23 |
| RF2 | hostile record | test_feedback hostile cases | OFFLINE | suite 268 passed | pass | 2026-11-23 |
| RF3 | 2.4 peer and frev/WANTF | library drops unknown types, unknown HELLO fields are not read | READ-ONLY | LibGuildSync Sync._onHello / _handlerFor | reasoned | 2026-11-23 |
| RF4 | 11th message drops the oldest, rev grows | test_feedback "Add ... keeps the newest 10, rev grows" | OFFLINE | suite 268 passed | pass | 2026-11-23 |
| RF5 | hidden Debug tab selected -> Recipes | test_load | OFFLINE | suite 268 passed | pass | 2026-11-23 |

## In-game checklist (things only the user can do)
- [ ] Live build, any character: the tab row shows Recipes, Orders, Misc Items, Feedback; no Debug. `/ps debug` prints log lines and opens the window on a now visible Debug tab; after `/reload` it is hidden again.
- [ ] Feedback tab: choosing each type fills the box with its template (only while the box is empty or unchanged); Bug ticks "Attach diagnostic info". Send with the template only -> "Write something first."; with text -> "Sent. Thank you!", the sent and waiting counters go up; "My messages" lists it with the waiting icon. Once the developer is online it turns into the delivered icon (counter delivered +1).
- [ ] Developer character with a second member online: the member sends a bug report; within ~30 s it appears in the developer's list (icon, name, text, "+" for the snapshot). Select it: detail text, Whisper opens a whisper to the member, "Diagnostic info" opens the copy window with the snapshot, the three icons set / clear the status.
- [ ] A non-developer member: `/ps export` shows "feedback records held: 1 (... messages), reader: false" (only their own).
- [ ] Dev build: Debug tab -> "Fake feedback" adds 3 messages from "Fake Tester" to the Feedback list.

## Accepted gaps
- none yet

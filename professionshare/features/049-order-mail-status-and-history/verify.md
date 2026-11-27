# 049 Order mail status and history: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> `402 passed, 0 failed`
Result after work:    `luajit tests/run.lua` -> `415 passed, 0 failed`

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence (output line, file, screenshot) | Result | Date |
|---|---|---|---|---|---|---|
| R1 | Detected send records an entry (items, complete/partly) | `test_mail_sender` "a send writes the mail into the order..." | OFFLINE | suite 415/0 | pass | 2026-11-27 |
| R1 | ... with the real mailbox | in-game checklist below, one client | IN-GAME | user: "seems to be working as expected" | pass | 2026-11-27 |
| R2 | Done in the mailbox panel = by hand | `test_mail_sender` "Done writes a mail marked by hand..." | OFFLINE | suite 415/0 | pass | 2026-11-27 |
| R3 | Mark by hand in the order window | `test_order_mail` "history rows, items text, who may mark by hand"; `test_load` MarkMailed | OFFLINE | suite 415/0 | pass | 2026-11-27 |
| R4 | Status Mailed, stays live | `test_order_mail` "a complete item mail makes the order mailed...", "mailed sorts between..." | OFFLINE | suite 415/0 | pass | 2026-11-27 |
| R5 | History rows with items, partly, by hand | `test_order_mail` history test; `test_load` history tab with a mail | OFFLINE | suite 415/0 | pass (look: IN-GAME, user) | 2026-11-27 |
| R6 | Sync live + after login, 2.9 untouched | `test_sync` "order mails travel with ORDER and after login only to peers that send mdig" | OFFLINE | suite 415/0 | pass | 2026-11-27 |
| R7 | Mail news for the recipient | `test_order_mail` "a mail to me by someone else is news until seen"; `test_load` | OFFLINE | suite 415/0 | pass (alert: IN-GAME, user) | 2026-11-27 |
| R8 | Orders tab status, icon, filter | `test_load` Mailed filter + refresh | OFFLINE | suite 415/0 | pass (look: IN-GAME, user) | 2026-11-27 |
| R9 | Validation, bounds | `test_order_mail` "bad entries are dropped...", "newest 30" | OFFLINE | suite 415/0 | pass | 2026-11-27 |
| RF1 | 2.9 peer not pushed for mails | `test_order_mail` digest test; `test_sync` | OFFLINE | suite 415/0 | pass | 2026-11-27 |
| RF2 | Mail to someone else records nothing | `test_mail_sender` "a mail to someone else writes nothing" | OFFLINE | suite 415/0 | pass | 2026-11-27 |
| RF3 | Garbage entries dropped, order kept | `test_order_mail` "bad entries are dropped" | OFFLINE | suite 415/0 | pass | 2026-11-27 |
| RF4 | Gone order: job works, nothing recorded | `test_mail_sender` "Done writes ... a gone order is left alone" | OFFLINE | suite 415/0 | pass | 2026-11-27 |
| RF5 | Mailed stays actionable | `test_order_mail` history test (canWithdraw, canDone, canCancel); `test_load` canDone | OFFLINE | suite 415/0 | pass | 2026-11-27 |

## In-game checklist (things only the user can do)
- [x] `/reload`, `/console scriptErrors 1`. Queue an item mail from an order row, open a mailbox, click the queued
  mail, send it -> the order shows **Mailed** with a mail icon; order window History shows "You mailed the item to ...:
  1x ...".
- [x] Mailbox panel **Done** on a queued mail -> History row with "(marked by hand)".
- [x] Order window Overview on an order you claimed -> "Mark item as mailed / handed over" -> Mailed.
- [x] `/psd fake mailed` (or with a delay: `/psd fake mailed 10`, then close the window) -> alert "X mailed you ...",
  badge; opening the Orders tab or the order clears it.
- [x] Orders tab filter **Mailed** lists only mailed orders.

## Accepted gaps
- Two real members (MULTI-CLIENT): not tested; the offline sync test covers it. Accepted by the user with the release request (2026-11-27, "clean up commit push release").

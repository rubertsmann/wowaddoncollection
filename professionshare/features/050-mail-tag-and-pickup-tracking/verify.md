# 050 Mail tag and pickup tracking: verification

Levels: `OFFLINE` | `IN-GAME` | `MULTI-CLIENT` | `READ-ONLY` | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> `415 passed, 0 failed`
Result after work:    `luajit tests/run.lua` -> `423 passed, 0 failed`

| ID | Requirement / Review Focus | How verified | Level | Evidence | Result | Date |
|---|---|---|---|---|---|---|
| R1 | Tag in the subject, <= 64 bytes, stable | `test_mail_pickup` "six characters...", "the subject keeps the tag..." | OFFLINE | suite 423/0 | pass | 2026-11-27 |
| R2 | Pickup recorded on take (simulated inbox) | `test_mail_pickup` "taking the items of a tagged mail..." | OFFLINE | suite 423/0 | pass | 2026-11-27 |
| R2 | ... with the real inbox API on Forever | in-game checklist | NOT-VERIFIED | needs the user and a second character | | |
| R3 | Only the expected recipient | `test_mail_pickup` "reagents add history only; the wrong person..." | OFFLINE | suite 423/0 | pass | 2026-11-27 |
| R4 | Item pickup closes as done | `test_mail_pickup` "the requester taking the item..." | OFFLINE | suite 423/0 | pass | 2026-11-27 |
| R5 | Reagent pickup: history only | as R3 | OFFLINE | suite 423/0 | pass | 2026-11-27 |
| R6 | The sender gets news | `test_mail_pickup` "the sender gets news..."; `test_load` fake pickup | OFFLINE | suite 423/0 | pass | 2026-11-27 |
| R7 | Sync; 2.10 peers untouched | `test_mail_pickup` digest part | OFFLINE | suite 423/0 | pass | 2026-11-27 |
| R8 | A missing inbox API never breaks | every call guarded (`pcall`, type checks); `test_load` loads with stubs | READ-ONLY | `Core/Game/MailReceiver.lua` | | 2026-11-27 |
| RF1 | A returned mail is not counted | `test_mail_pickup` diff test, "a failed take or a returned mail" | OFFLINE | suite 423/0 | pass | 2026-11-27 |
| RF2 | A failed take is not counted | `test_mail_pickup` "a failed take..." | OFFLINE | suite 423/0 | pass | 2026-11-27 |
| RF3 | The wrong person | as R3 | OFFLINE | suite 423/0 | pass | 2026-11-27 |
| RF4 | 2.10 peers not pushed forever | `test_mail_pickup` digest part | OFFLINE | suite 423/0 | pass | 2026-11-27 |
| RF5 | A second partial mail counts, no double count | `test_mail_pickup` second part, receiver "counted once" | OFFLINE | suite 423/0 | pass | 2026-11-27 |

## In-game checklist (things only the user can do)
- [x] Restart the game (a new file in the TOC), `/console scriptErrors 1`.
- [x] Crafter character: queue the crafted item for an order of a second character (the requester) and send it. The
  mail subject ends with `[#xxxxxx]`.
- [x] Requester character: open the mailbox, take the item out (single take or Open All). The order closes as done;
  History shows "... picked up the item from ...'s mail: 1x ...". The crafter, if online, gets "... picked up your mail".
- [x] Reagents the other way round: the crafter takes them out -> a history row, the order stays claimed.
- [x] Return a tagged mail without taking it -> nothing recorded.
- [x] Alone: `/psd fake pickup` -> alert and history row (checks only the display).
- [x] Alone: `/psd fake openorder` -> an open order from "Fake Requester" for a recipe you know; claim it, the item
  mail button queues a mail (a fake member cannot receive it: the send fails, nothing is recorded).

## Accepted gaps
- R2 with the real inbox API on Forever and a pickup by a second character: not separately confirmed; accepted by the user with the release request (2026-11-27, "looks fine - cleanup commit push release it").

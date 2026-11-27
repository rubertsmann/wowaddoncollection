# 045 Mail order items: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.

Baseline before the queue: `luajit tests/run.lua` -> `362 passed, 0 failed`
Result after work:          `luajit tests/run.lua` -> `382 passed, 0 failed`

| ID | Requirement / Review Focus | How verified | Level | Evidence | Result | Date |
|---|---|---|---|---|---|---|
| R1 | Mode switch + "Add to mail queue (n)", ticks always shown | `test_load` renders the Orders tab; handler READ-ONLY | READ-ONLY | suite 382 | pending in game | 2026-11-27 |
| R2 | Recipient/items per mode, claimer menu, no self/duplicate/no-data jobs | `mail queue: mats job ...`, `item job ...`, `no recipient, myself, or no data ...`, `add, no duplicates ...`; menu NOT-VERIFIED | OFFLINE (logic) / NOT-VERIFIED (menu) | suite 382 | pass offline | 2026-11-27 |
| R3 | Mail tab list, missing per job, Remove / Move up, status | `mail queue: Mail tab rows share the bag contents ...`; `test_load` renders the tab | OFFLINE (rows) / NOT-VERIFIED (look) | suite 382 | pass offline | 2026-11-27 |
| R4 | Saved per character | `mail queue: add ... saved per character`, sanitizer test | OFFLINE | suite 382 | pass | 2026-11-27 |
| R5 | Mailbox opens -> first job filled (tab, recipient, subject, attachments) | `mail sender: opening the mailbox fills the first job ...` (simulated) | OFFLINE (sim) / NOT-VERIFIED (Forever: `SendMailNameEditBox`, tab click) | suite 382 | pass offline | 2026-11-27 |
| R6 | Exact amounts via split into a free slot | plan tests; sender fill test | OFFLINE (sim) / NOT-VERIFIED (does the split land on Forever?) | suite 382 | pass offline | 2026-11-27 |
| R7 | Missing items left out, rest stays in the job | `mail sender: what the bags lack stays in the job ...` | OFFLINE (sim) | suite 382 | pass offline | 2026-11-27 |
| R8 | More than 12 attachments -> rest in the next mail | `mail queue: plan stops at the attachment limit ...` | OFFLINE | suite 382 | pass | 2026-11-27 |
| R9 | After the send: job updated, next filled; Fill next / Skip / Remove | `mail sender: a send to the job's recipient ...`, `skip empties the form ...` | OFFLINE (sim) / NOT-VERIFIED (`MAIL_SEND_SUCCESS`, the SendMail hook on Forever) | suite 382 | pass offline | 2026-11-27 |
| R10 | Cursor never left with an item, never sends, not in combat | sender tests (`state.sent` stays empty, cursor nil) | OFFLINE (sim) | suite 382 | pass offline | 2026-11-27 |
| RF1 | Changed recipient -> not counted | `mail sender: a mail to someone else does not count for the job` | OFFLINE | suite 382 | pass | 2026-11-27 |
| RF2 | Split does not land -> missing, cursor empty | `mail sender: a split that never lands and a refused item ...` | OFFLINE | suite 382 | pass | 2026-11-27 |
| RF3 | Soulbound refused -> cursor cleared | same test (`refuseItem`); plan skips stacks reported as bound | OFFLINE | suite 382 | pass | 2026-11-27 |
| RF4 | Order gone -> job still works | `mail queue: the job keeps working after its order is gone` | OFFLINE | suite 382 | pass | 2026-11-27 |
| RF5 | Corrupt `mailQueue` dropped | `mail queue: the load sanitizer ...` | OFFLINE | suite 382 | pass | 2026-11-27 |
| RF6 | Mailbox closed mid-fill -> stops | `mail sender: closing the mailbox stops ...` | OFFLINE | suite 382 | pass | 2026-11-27 |

## In-game checklist (user)
Dev build: restart the game (new files in the TOC), `/console scriptErrors 1`. Have tradeable reagents in your bags
(a stack bigger than needed, so a split is needed) and at least one free bag slot.
- [ ] Orders tab: tick boxes on every row; bottom right **Mail: mats to crafter** (click -> **Mail: item to requester**) and **Add to mail queue (n)**.
- [ ] Tick an order someone claimed, mode mats -> **Add to mail queue** -> chat "1 mails added..."; the **Mail** tab (next to Orders) lists it with its reagents and what is missing.
- [ ] An order with two claimers -> a menu asks who gets the mats.
- [ ] Open a mailbox -> the Send Mail tab opens, recipient + subject + body filled, the exact reagent amounts attached (a split stack shows the exact number); the panel right of the mailbox shows the job. Nothing is sent.
- [ ] Press **Send** -> the next queued mail is filled; the sent job is gone from the Mail tab (or keeps only what was missing).
- [ ] Panel **Skip**: the attachments go back to the bags, the next job is filled. **Remove** drops the job.
- [ ] Change the recipient by hand and send -> the job stays in the queue.
- [ ] `/reload` with jobs queued -> still there; another character has its own queue.
- [ ] If anything fails: `/psd mailprobe report` is no help here; send a screenshot and `/ps export`.

## Accepted gaps
- none yet

## In-game result (2026-11-27)
The user ran the in-game checklist on the dev build after feature 046 (Orders tab rework, row icons, buy-list dialog,
mailbox panel, Mail tab icons) and reported: "looks fine and works as expected". On that report the rows marked
READ-ONLY or NOT-VERIFIED above count as IN-GAME (user report, no screenshot or SavedVariables evidence on disk).
Accepted by the user on 2026-11-27. MULTI-CLIENT (a second real guild member receiving mails) was not part of the check.

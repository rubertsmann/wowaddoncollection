# 045 Mail order items: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-27 11:05 | PLAN | Feature created
- Did: scaffolded `features/045-mail-order-items/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-27 11:05 | BUILD | T1a mail probe
- Did: `UI/MailProbe.lua` (new, dev build only: `/psd mailprobe` api check, `fill <name>`, `attach`/`burst <itemID> [count] ...`, `report`; never calls SendMail, puts back anything left on the cursor, records to `devChecks.mail`), TOC entry after `UI/DevProbe.lua`, Debug tab dev-tools entry "Mail API check", `tests/test_mail_probe.lua` (6 tests, simulated mailbox)
- Result: the test caught a missed-event bug (event fired during the click, counted before the wait began); fixed by counting before the click
- Evidence: `luajit tests/run.lua` -> `360 passed, 0 failed`
- Next: user runs the probe in game (steps in verify.md) and sends `/psd mailprobe report` output; then answer the open questions in spec.md

## 2026-11-27 11:10 | TEST | Probe run 1 (partial) and probe fixes
- Did: user ran the probe (api without mailbox, then the mailbox steps, /reload after each); saved the surviving report to `evidence/probe-run-1.md`. Fixed the probe: every run is kept (`devChecks.mailRuns`, last 12, survives /reload) and `report` shows all; `bags` lists bag items with ids; `clear`; stacks per item are logged before attaching; empty attachment slots no longer listed as "(nothing)"
- Result: attaching works on Forever (`GetSendMailItem` reads name, id, texture, count, quality); a draft attachment survived /reload; split behaviour unknown (report lost)
- Evidence: `evidence/probe-run-1.md`; `luajit tests/run.lua` -> `361 passed, 0 failed`
- Next: user reruns the series (verify.md steps, starting with `/psd mailprobe clear` and `bags`) and sends one `report`

## 2026-11-27 11:13 | BUILD | Probe shortcuts /psd mailfill and /psd mailtest
- Did: `UI/MailProbe.lua`: `mailfill [name]` (fill; the recipient is remembered in the dev saved variables `devChecks.mailRecipient`, never in code), `mailtest` (picks a stack of more than 3 and a second item from the bags, attaches 3 + the whole stack one after the other, then opens the report); test in `tests/test_mail_probe.lua`
- Result: all offline tests pass
- Evidence: `luajit tests/run.lua` -> `362 passed, 0 failed`
- Next: user: `/reload`, `/psd mailprobe clear`, at a mailbox `/psd mailfill <recipient>` and `/psd mailtest`, paste the report

## 2026-11-27 11:18 | TEST | Probe run 2: split attaches the whole stack, soulbound refused on the client
- Did: saved the user's `/psd mailtest` report as `evidence/probe-run-2.md` (F1-F4). Probe changes: `mailtest` skips items the client reports as bound (`isBound`), splits the biggest stack two ways (2 via an empty bag slot = new method `attachslot`, then 3 straight into the mail) and attaches one other item; attachments are read again 2 s after the run; `bags` and the stack lines show `bound=`
- Result: F1 means exact amounts need the empty-slot route (to be confirmed); F2 sequencing is cheap; F3 the cursor guard is required; F4 open
- Evidence: `evidence/probe-run-2.md`; `luajit tests/run.lua` -> `362 passed, 0 failed`
- Next: user at a mailbox with a tradeable stack of at least 6 (cloth, herbs, ore): `/reload`, `/psd mailprobe clear`, `/psd mailfill <recipient>`, `/psd mailtest`, paste the report

## 2026-11-27 11:22 | PLAN | Mail queue spec
- Did: user asked for a mail queue from the Orders tab (filled one after another at the mailbox, sent by hand, next one after the send, mode switch mats->crafter / item->requester) and a Mail tab next to Orders; answers: exact amounts via free bag slot, attach what I have and keep the rest, queue saved per character, menu for several claimers. spec.md rewritten (R1-R10, T2-T7, RF1-RF6)
- Result: plan ready; T1b (probe of the empty-slot split, fill, MAIL_SEND_SUCCESS) still open and is checked by the real feature in game too
- Evidence: spec.md "Decisions"
- Next: T2 `Core/Data/MailQueue.lua` + `tests/test_mail_queue.lua`

## 2026-11-27 11:31 | BUILD | T2-T6 mail queue, sender, Orders tab, Mail tab, mailbox panel
- Did: `Core/Data/MailQueue.lua` (jobs, plan: whole stacks / exact split into a free slot / missing / bound / 12-attachment limit, apply sent, load sanitizer), `Core/Data/Store.lua` (`mailQueue` table, sanitized on load), `Core/Game/MailSender.lua` (fills the first job with something in the bags on MAIL_SHOW, never sends, cursor guard, SendMail post-hook snapshot, MAIL_SEND_SUCCESS only for the job's recipient, next job afterwards, Skip/Remove/ClearForm), `Core/Game/Events.lua` (MAIL_SHOW/MAIL_CLOSED hooks, MailSender.Register), `Core/View/Model.lua` (`BuildMailRows`), `UI/Window.lua` (tick boxes always shown, mode switch + "Add to mail queue (n)" with a claimer menu, Mail tab), `UI/MailPanel.lua` (panel at the mailbox), TOC, 39 deDE strings; tests `test_mail_queue.lua` (13), `test_mail_sender.lua` (8), `test_load.lua` (Mail tab + panel)
- Result: all offline tests pass; the comment audit caught a doc comment separated from its function (fixed)
- Evidence: `luajit tests/run.lua` -> `382 passed, 0 failed`
- Next: T7 docs, then the user's in-game checklist in verify.md

## 2026-11-27 11:32 | DOC | T7 docs and verify matrix
- Did: verify.md (R1-R10, RF1-RF6, in-game checklist), doc.md, README (feature list + code layout), CHANGELOG (Unreleased), docs/status.md, INDEX `verifying`; feature 044 log: deviation (tick boxes always shown)
- Result: every requirement OFFLINE at the logic level (simulated mailbox); the Forever-specific steps are NOT-VERIFIED
- Evidence: `luajit tests/run.lua` -> `382 passed, 0 failed`
- Next: user restarts the game (new TOC files) and runs the in-game checklist in verify.md; then the rows go to IN-GAME

## 2026-11-27 11:43 | BUILD | Dev tool: fake order for the mail queue test
- Did: `UI/DevProbe.lua`: `AddFakeOrder` (`/psd fake order [recipeID] [qty]`, Debug tab dev tools "Order from a fake member"): an order from "Fake Requester" for the catalog recipe whose reagents the bags cover best, claimed by "Fake Crafter" and, when remembered (`/psd mailfill <name>`), by that character; local only, not broadcast. "Remove all fake data" now also deletes fake orders and their mail jobs (`RemoveFakeOrders`); check in `test_load.lua`
- Result: all offline tests pass
- Evidence: `luajit tests/run.lua` -> `382 passed, 0 failed`
- Next: user: `/reload`, `/psd fake order`, then the in-game checklist in verify.md

## 2026-11-27 12:21 | BUILD | Dev tool: fake order needing Linen Cloth
- Did: `UI/DevProbe.lua`: `AddFakeLinenOrder` (`/psd fake linen [qty]`, dev tools "Order needing Linen Cloth"): a catalog recipe whose only reagent is Linen Cloth (2589), else Bolt of Linen Cloth (recipe 2963, 2 cloth each, added to the catalog); quantity 3 by default; same claimers as the fake order; check in `test_load.lua` (3 bolts -> 6 Linen Cloth)
- Result: all offline tests pass
- Evidence: `luajit tests/run.lua` -> `382 passed, 0 failed`
- Next: user: `/reload`, `/psd fake linen`, then the in-game checklist in verify.md

## 2026-11-27 12:46 | DEVIATION | Reworked by feature 046
- Did: feature 046 replaced the tick boxes and top/bottom controls: buy list per order via a row icon and dialog, collected until the next auction house visit; mail queue via row icons, filled on click from a list next to the inbox (no fill on open or after a send), Done/Delete per mail
- Result: this feature's UI requirements are superseded where 046 says so; the logic (Auctionator API use, mail filling) is unchanged
- Evidence: `features/046-order-row-actions-and-mailbox-queue-list/spec.md`
- Next: verify through 046's in-game checklist

## 2026-11-27 13:28 | VERIFY | In-game confirmation by the user
- Did: user ran the dev build after feature 046 and reported "looks fine and works as expected"; recorded in verify.md ("In-game result")
- Result: open rows count as IN-GAME on the user's report; status `done`
- Evidence: user report in the session (no file evidence)
- Next: release (see the release commit)

# 049 Order mail status and history: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-27 15:02 | PLAN | Feature created
- Did: scaffolded `features/049-order-mail-status-and-history/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-27 15:12 | DECISION | Ten design questions answered
- Did: asked the user 10 questions; all answered with the recommended option (spec.md "Decisions" 1-10)
- Result: both mail kinds, new status Mailed, entry per mail, items shown, alert, Done = by hand, mark button, no chat line, synced, own filter + icon
- Evidence: spec.md Decisions
- Next: build T1-T6

## 2026-11-27 15:12 | BUILD | T1-T6 order mails, protocol 2.10
- Did: `Core/Data/Orders.lua` (ml, RecordMail, MailVersion, MailDigest, Missing, status mailed), `Core/Data/MailQueue.lua` (Delivered, MailEntry), `Core/Game/MailSender.lua` (record on send and Done), `Core/Net/Sync.lua` (mdig), `Core/Base/Init.lua` (minor 10), `Core/View/Model.lua` (OrderIsLive, history mail rows, MailItemsText, MarkMailTargets, filter mailed), `Core/View/Notify.lua` (UnseenMail, MarkMailSeen), `UI/Alerts.lua`, `UI/OrderWindow.lua` (history text, mark buttons), `UI/Window.lua` (status, icon, filter), `UI/DevProbe.lua` (`/psd fake mailed`), deDE strings; tests `tests/test_order_mail.lua` (new), `test_mail_sender.lua`, `test_sync.lua`, `test_load.lua`
- Result: all requirements and review focus rows OFFLINE
- Evidence: `luajit tests/run.lua` -> 415 passed, 0 failed
- Next: docs done (protocol.md section 19, README, CHANGELOG Unreleased, status.md, review/order-mail.md); the user runs the in-game checklist in verify.md

## 2026-11-27 15:12 | BLOCKED | In-game check
- Did: wrote the in-game checklist (verify.md)
- Result: waiting for the user
- Evidence: n/a
- Next: user: /reload, send a queued mail, Done in the mailbox panel, mark button, `/psd fake mailed`, Mailed filter; then set the rows IN-GAME and the status done

## 2026-11-27 15:26 | VERIFY | In-game check by the user
- Did: the user ran the in-game checklist (verify.md) on one client
- Result: "seems to be working as expected"; rows set IN-GAME, status done
- Evidence: user message 2026-11-27
- Next: commit and release when the user asks (two-member check still open, noted under Accepted gaps)

## 2026-11-27 15:27 | DONE | Released in 1.7.0
- Did: user asked "clean up commit push release"; two-member check accepted with it (verify.md Accepted gaps)
- Result: version 1.7.0, CHANGELOG, RELEASE_NOTES, INDEX done
- Evidence: `luajit tests/run.lua` -> 415 passed, 0 failed
- Next: none

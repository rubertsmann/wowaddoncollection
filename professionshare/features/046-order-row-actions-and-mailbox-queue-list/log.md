# 046 Order row actions and mailbox queue list: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-27 12:36 | PLAN | Feature created
- Did: scaffolded `features/046-order-row-actions-and-mailbox-queue-list/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-27 12:36 | PLAN | Spec from the user's refactor request
- Did: spec.md R1-R9, T1-T6, RF1-RF4; answers recorded (bottom row removed, Craft to the top bar because a menu cannot cast, buy list collected until the AH, no auto fill after a send, Done subtracts what is attached)
- Result: plan ready
- Evidence: spec.md "Decisions"
- Next: T1 model flags + buy collection helpers

## 2026-11-27 12:46 | BUILD | T1-T5 Orders tab rework, buy collection, click-to-fill mailbox list
- Did: `Core/View/Model.lua` (row flags canMailMats/canMailItem/hasReagents), `Core/Data/BuyList.lua` (CollectionAdd/Prune), `Core/Game/Auctionator.lua` (searchedThisVisit), `Core/Game/Events.lua` (AUCTION_HOUSE_CLOSED clears the collection), `Core/Game/MailSender.lua` (FillJob, Done; no fill on MAIL_SHOW or after a send; Skip removed), `UI/Window.lua` (filter dropdown, Craft in the top bar, right-click menu, action icons, buy-list dialog, ticks/bottom row/old controls removed, Mail tab Fill/Done), `UI/MailPanel.lua` (list of every job with Fill/Done/Delete and status), deDE (+34, 26 stale removed); tests updated (sender: click-to-fill, Done; buy list: collection, row flags; load: buy flow, mail action)
- Result: two bugs caught by the tests: a multi-value `Get` inside a table constructor (planned the index as a job), and a test assumption about unnamed reagents (correctly left out)
- Evidence: `luajit tests/run.lua` -> `384 passed, 0 failed`
- Next: user: `/reload`, run the in-game checklist in verify.md

## 2026-11-27 13:21 | BUILD | Row icons for the order actions
- Did: `UI/Window.lua`: the action column also has I'll craft it, Withdraw, Mark done, Cancel order (same rules as the right-click menu, greyed out when not possible); icons packed to the right of the row; Craft stays in the top bar (an inline secure button per row would make the window protected in combat)
- Result: all offline tests pass
- Evidence: `luajit tests/run.lua` -> `384 passed, 0 failed`
- Next: user: `/reload`, in-game checklist in verify.md

## 2026-11-27 13:23 | BUILD | Mail tab: inline row icons
- Did: `UI/Window.lua`: shared helpers `addRowActionButtons` / `layoutRowActions` (icon column packed against the right text, tooltip, greyed out when not possible) used by the order rows and the Mail tab rows; Mail tab rows get Move up / Fill / Done / Delete, its bottom buttons are removed; deDE +2, 2 stale keys removed
- Result: all offline tests pass
- Evidence: `luajit tests/run.lua` -> `384 passed, 0 failed`
- Next: user: `/reload`, in-game checklist in verify.md

## 2026-11-27 13:28 | VERIFY | In-game confirmation by the user
- Did: user ran the dev build after feature 046 and reported "looks fine and works as expected"; recorded in verify.md ("In-game result")
- Result: open rows count as IN-GAME on the user's report; status `done`
- Evidence: user report in the session (no file evidence)
- Next: release (see the release commit)

## 2026-11-27 13:28 | BUILD | ID check and cleanup before the release
- Did: names vs ids reviewed: queue, plan, bags and buy list work on item ids; Auctionator needs item names (taken from the client by id); the mail job's recipe name is now looked up by recipe id (`Model.MailJobRecipeName`, the snapshot only as fallback) for the Mail tab, the panel and the subject/body; removed dead code (`MailQueue:Skip`, `MailSender.FillNext`, unused exports `BuyList.SearchName`, `MailQueue.SanitizeJob`); test for the id-based name
- Result: all offline tests pass
- Evidence: `luajit tests/run.lua` -> `385 passed, 0 failed`
- Next: release

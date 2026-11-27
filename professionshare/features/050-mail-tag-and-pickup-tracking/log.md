# 050 Mail tag and pickup tracking: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-27 15:31 | PLAN | Feature created
- Did: scaffolded `features/050-mail-tag-and-pickup-tracking/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-27 15:32 | DECISION | Four design questions answered
- Did: the user proposed an order id in the subject; asked 4 questions, all answered with the recommended option (spec.md Decisions)
- Result: item pickup closes as done; pickup only (no arrival); reagent pickups as history rows; the sender gets news
- Evidence: spec.md Decisions
- Next: build T1-T5

## 2026-11-27 15:37 | BUILD | T1-T5 tag, inbox diff, pickups, protocol 2.11
- Did: `Core/Data/MailQueue.lua` (Tag, ParseTag, TaggedSubject, InboxTotals, Pickups, FlatItems, ApplyPickup), `Core/Data/Orders.lua` (rcv, RecordPickup, PickupVersion, PickupDigest, FindByTag), `Core/Game/MailReceiver.lua` (new; TOC after MailSender), `Core/Game/MailSender.lua` (tagged subject), `Core/Game/Events.lua`, `Core/Net/Sync.lua` (rdig), `Core/Base/Init.lua` (minor 11), Model/Notify/Alerts/OrderWindow texts, DevProbe `/psd fake pickup`, deDE; tests `tests/test_mail_pickup.lua` (8), `test_load.lua`; dev TOC regenerated (deploy.ps1); docs protocol.md section 20, README, CHANGELOG Unreleased, status.md, review/mail-pickup.md
- Result: every row OFFLINE except the real inbox API (NOT-VERIFIED) and R8 (READ-ONLY)
- Evidence: `luajit tests/run.lua` -> 423 passed, 0 failed
- Next: the user runs the in-game checklist in verify.md

## 2026-11-27 15:40 | BLOCKED | In-game check
- Did: wrote the checklist in verify.md
- Result: waiting for the user (needs a second character for a real pickup)
- Evidence: n/a
- Next: user: restart the game, send a tagged item mail between two characters, take it out, check close / history / news

## 2026-11-27 15:44 | BUILD | Dev trigger: open order from someone else
- Did: `UI/DevProbe.lua` `DevProbe.AddFakeRequest` (`/psd fake openorder [recipeID] [qty]`): an open, unclaimed order from a fake member for a recipe I know, prints its mail tags; `tests/test_load.lua` checks it
- Result: works offline
- Evidence: `luajit tests/run.lua` -> 423 passed, 0 failed
- Next: the user runs the in-game checklist in verify.md

## 2026-11-27 15:45 | DONE | Released in 1.8.0
- Did: user: "looks fine - cleanup commit push release it"; the real-inbox / second-character pickup accepted with it (verify.md Accepted gaps)
- Result: version 1.8.0
- Evidence: `luajit tests/run.lua` -> 423 passed, 0 failed
- Next: none (record the inbox API facts in docs/api-findings.md once a real pickup is seen)

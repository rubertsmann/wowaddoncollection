# 024 Feedback tab and hidden debug tab: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-23 22:30 | PLAN | Feature created
- Did: scaffolded `features/024-feedback-tab-and-hidden-debug-tab/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-23 22:41 | DECISION | Plan and decisions
- Did: filled spec.md (R1-R7); reuse the existing name hash (Model.IsBuildViewer) for the developer; only the developer's client pulls feedback records; status local to the developer.
- Result: plan written; the user had described the feature in full and said "you can decide", so the build started without a review round
- Evidence: spec.md Decisions
- Next: T1

## 2026-11-23 22:41 | DECISION | Bug snapshot (user, during the build)
- Did: user asked to include debug logs with bug reports; added R8 (snapshot of version, sync state, newest error/warning and recent log lines, 1200-byte cap, opt-out checkbox)
- Result: spec.md updated
- Evidence: spec.md R8
- Next: T1

## 2026-11-23 22:41 | BUILD | T1-T4b data, sync, UI, debug tab, dev button, snapshot
- Did: new Core/Data/Feedback.lua (both TOCs, tests/run.lua); Store schema 7 + migration 6; Sync record kind feedback (frev, WANTF/FEEDBACK); PROTOCOL_MINOR 5; Communication: FEEDBACK replaceable, WANTF priority; Events FEEDBACK_CHANGED -> RequestHelloSoon; Diagnostics counts; UI/Window.lua Feedback tab, hidden Debug tab, /ps debug wrapper, Fake feedback button; UI/DevProbe.lua AddFakeFeedback + /ps fakefeedback; deDE strings. Tests: new tests/test_feedback.lua (9), test_load additions, pins in test_access/test_send_backlog/run.lua
- Result: all green
- Evidence: luajit tests/run.lua -> 268 passed, 0 failed
- Next: T5 docs

## 2026-11-23 22:41 | DOC | T5 docs
- Did: CHANGELOG (Unreleased), README, docs/protocol.md section 13, docs/status.md, doc.md, verify.md, INDEX (verifying)
- Result: docs match the code
- Evidence: this commit
- Next: user: in-game checklist in verify.md (needs the live/dev build and a second member for delivery); release when wanted

## 2026-11-23 22:47 | BUILD | Sender view: menu and delivery counters (user request)
- Did: replaced the long status line and the info text under the box with a "My messages (n)" menu (own messages, delivered/waiting icon), three icon counters (sent / delivered / waiting, tooltips) and a short coloured send result; the explanation moved into tooltips. Delivery: Sync feedback kind `answer` -> Feedback.MarkDelivered; new local table feedbackDelivered (schema 7, re-validated on load); Feedback.MySummary. Locale: 2 long strings removed, 10 added (deDE). Tests: test_feedback delivery + persistence checks
- Result: all green
- Evidence: luajit tests/run.lua -> 268 passed, 0 failed
- Next: user: in-game checklist in verify.md; release when wanted

## 2026-11-23 22:58 | BUILD | Feedback tab only in the developer's guild; identity exposure answered
- Did: Feedback.ReaderInRoster (roster names against the name hash); Window: tabAvailable / layoutTabButtons (hidden buttons leave no gap, re-laid out on every refresh), the open Feedback tab closes when the developer leaves the roster; ShowDebugTab uses the same layout. Tests: test_load (hidden / shown / closes), test_feedback roster test.
- Result: all green. Exposure analysis (answer to the user): inside the own guild, the developer's character name can be learned (32-bit djb2 hash vs. roster names; the only WANTF sender, visible in a sender's trace; GUILD retries visible to all; tab visibility). Nothing reaches other guilds; no real-world data is involved. Not fixable while the tab must know whether the developer is in the guild: any check the client runs, a curious member can run too.
- Evidence: luajit tests/run.lua -> 269 passed, 0 failed
- Next: user: in-game checklist in verify.md; release when wanted

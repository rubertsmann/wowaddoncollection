# 047 Notification scope dropdown and profession level scope: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-27 13:34 | PLAN | Feature created
- Did: scaffolded `features/047-notification-scope-dropdown-and-profession-level-scope/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-27 13:34 | PLAN | Spec from the user's request and answers
- Did: spec.md R1-R4, T1-T3, RF1-RF4; answers: no separate "can craft" option (= recipes I know); level = recipe rank <= my rank, estimated from the lowest knower rank (no recipe ranks are recorded)
- Result: plan ready
- Evidence: baseline `luajit tests/run.lua` -> `385 passed, 0 failed`
- Next: T1 Notify level scope + tests

## 2026-11-27 13:37 | BUILD | T1-T3 level scope, settings dropdown, docs
- Did: `Core/View/Notify.lua` (`RecipeRanks`, scope "level", SCOPES ordered narrow to broad), `UI/Alerts.lua` (dropdown with radio entries, cycling-button fallback, hint per scope), `Locales/deDE.lua` (+4), `tests/test_notify.lua` (+2); verify.md, doc.md
- Result: all offline tests pass
- Evidence: `luajit tests/run.lua` -> `387 passed, 0 failed`
- Next: user: `/reload`, settings check in verify.md

## 2026-11-27 14:46 | DONE | Released in 1.6.0
- Did: status done (spec, INDEX); remaining in-game rows accepted by the user's release request (verify.md)
- Result: part of release 1.6.0
- Evidence: verify.md "Accepted gaps"; review/order-chat.md (no blocking finding)
- Next: none

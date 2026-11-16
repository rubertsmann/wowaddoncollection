# 007 Recipe items board: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-16 13:12 | PLAN | Feature created
- Did: scaffolded `features/007-recipe-items-board/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-16 13:13 | PLAN | Draft spec written, questions Q1-Q10 sent
- Did: scaffolded feature 007 via new-feature.ps1; wrote draft features/007-recipe-items-board/spec.md (goal, interpretation, design sketch, review focus). No code changed.
- Result: waiting for the user's answers to Q1-Q10 (recipe ITEMS vs learned recipes, scope of scan, opt-in, dibs semantics, removal semantics, wire/schema, UI).
- Evidence: n/a (no code)
- Next: record the answers under "Decisions" in spec.md, finalize requirements/tasks, then T0 (in-game probe of C_Container / bank / item class APIs on Forever) before implementing.

## 2026-11-16 13:39 | DECISION | User answered Q1-Q10
- Did: recorded the answers in spec.md: recipe ITEMS (class Recipe) that are tradeable, all locations, automatic listing, several dibs, only the dibber removes their dib, local removal, fully manual hand-over, additive protocol 2.1, UI as proposed.
- Result: spec finalized (record per character with items + own dibs, HELLO.orev / WANTO / OFFERS, schema 3).
- Evidence: features/007-recipe-items-board/spec.md "Decisions"
- Next: implement T1-T5.

## 2026-11-16 13:39 | BUILD | T1-T5 implemented
- Did: Core/Offers.lua (new), Store schema 3 (offers, hidden, Clean/Counts/Prune/SanitizePersisted), Sync orev/WANTO/OFFERS, Comm queue priority, Init PROTO_MINOR 1, Api.ScanItems/ItemClass, Events glue + /ts offers, Model.BuildOfferRows, Window "Available" tab, deDE strings, TOC + test loader, docs (README, CHANGELOG, protocol.md, status.md, doc.md). New tests: tests/test_offers.lua, test_offers_model.lua, test_items_api.lua; test_hardening header test made minor-agnostic; test_load smoke covers the tab.
- Result: 127 passed, 0 failed (baseline 99 passed). Mutation check: 5 deliberate breakages each failed at least one test.
- Evidence: luajit tests/run.lua -> 127 passed, 0 failed
- Next: user runs the in-game checklist in verify.md (deploy.ps1, restart game, /tsd offers); then fix whatever the real client does differently. Nothing committed yet; TOC version still 0.3.1 (bump to 0.4.0 only when releasing).

## 2026-11-16 14:52 | NOTE | Committed and pushed with master (not released)
- Did: feature committed as 61eff86 and pushed; merged with the 0.3.2 whisper fix (c09e84d). TOC version is 0.3.2 (the released fix); 0.4.0 is the target for this feature and is NOT tagged.
- Result: `luajit tests/run.lua` -> 134 passed, 0 failed. Still NOT verified in game: bank/mail/guild bank/auction scans, tab layout, two-client sync.
- Next: user runs the in-game checklist in verify.md on the dev build (/tsd offers), then bump the version to 0.4.0 and tag when ready.

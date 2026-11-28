# 052 Member builds button (live build and record version, one viewer): log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-27 23:42 | PLAN | Feature created
- Did: scaffolded `features/052-member-builds-button-live-build-and-record-version-one-viewer/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-27 23:45 | BUILD | T1-T3 viewer hash, MemberBuilds model, button and tooltip
- Did: `Core/View/Model.lua` (BUILD_VIEWER_HASHES, NameHash, IsBuildViewer, MemberBuilds), `UI/Window.lua` (bottom-left (i) button, shown on OnShow for the viewer only), `Locales/deDE.lua` (7 strings), `tests/test_member_builds.lua` (new)
- Result: offline suite green, UI not yet seen in game
- Evidence: `luajit tests/run.lua` -> 220 passed, 0 failed (218 without the new file)
- Next: user deploys and hovers the (i) in game; read the rows for the two members who show 0.13.0 (orange = stale record)

## 2026-11-28 00:09 | DEVIATION | login republish of the arena version added
- Did: the live SavedVariables showed my own record at arena.ver 0.11.0 and three members without an arena section (version unknown = "another version" for everybody). Added `Arena.SectionStale` (Core/Minigames/Arena.lua) and a check 5 s after login in `Catcher.Start` (Core/Game/Catcher.lua) that calls `Catcher.PublishArena` when my section is missing or from another build; test in tests/test_member_builds.lua
- Result: offline suite green; released with 0.14.0
- Evidence: `luajit tests/run.lua` -> 233 passed, 0 failed
- Next: after the members update and log in, hover the (i): every row should show "Eintrag 0.14.0"; then set the UI row in verify.md

## 2026-11-28 10:30 | DONE | works in game
- Did: user hovered the member builds (i) in game
- Result: rows and record versions as expected; status done
- Evidence: user: "52 works as expected" (2026-11-28)
- Next: none

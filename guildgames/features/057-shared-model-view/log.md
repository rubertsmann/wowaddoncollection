# 057 Shared model view: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-28 13:37 | PLAN | Feature created
- Did: scaffolded `features/057-shared-model-view/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-28 13:40 | PLAN | Inventory and plan
- Did: grep for every model frame call and creator in `Core/` and `UI/`; inventory table + R1-R9, T1-T8 in spec.md
- Result: two model helpers (AzeCaughtPanel-local, `UI/CompanionModel.lua`) and a third animation copy (ArenaView); 10 displays
- Evidence: spec.md "Inventory"; baseline `luajit tests/run.lua` -> 241 passed, 0 failed
- Next: T2 the module

## 2026-11-28 13:46 | BUILD | T2-T6 ModelView and every display on it
- Did: new `UI/ModelView.lua` (New/options/presets/ANIMATION/Pick/poses/Die/companion mode/zoom/RefreshAll); Runner, Survivor,
  Catcher probes, AzeCaughtPanel (companion, preview, guild), PetView, ArenaView, TeamDialog, Window on it; deleted
  `UI/CompanionModel.lua`; TOC; tests: new `tests/test_model_view.lua` (11 tests incl. the lint), test_games_ui and
  test_load moved to the view API; deploy.ps1 re-run (dev TOC)
- Result: green; the lint fails on a planted `SetFacing` + `CreateFrame("DressUpModel")` in UI/TeamDialog.lua (reverted)
- Evidence: `luajit tests/run.lua` -> 252 passed, 0 failed; planted: "model frame calls outside UI/ModelView.lua: UI/TeamDialog.lua:487 SetFacing | UI/TeamDialog.lua:487 DressUpModel"
- Next: docs (T7), independent review (T8)

## 2026-11-28 13:49 | DOC | T7 conventions, changelog, skills
- Did: `docs/coding-conventions.md` (folder row, one-helper row, section "3D models"), CHANGELOG Unreleased,
  `.claude/skills/feature-workflow/SKILL.md` (GuildGames: models through ModelView), `.claude/skills/bug-workflow/SKILL.md`
  (journal filter `model`), doc.md
- Result: done
- Evidence: git diff
- Next: T8 subagent review, then fix its findings

## 2026-11-28 13:55 | VERIFY | T8 review round 1 (independent subagent)
- Did: read-only review of the split, reuse, behaviour vs HEAD, ModelView bugs, tests, docs
- Result: "SPLIT CLEAN: yes", "REUSE GUARANTEED: yes, with three small leftovers"; 17 findings, fixed: hidden-tab
  Reload loads into a hidden frame (now only forgets), arena journal noise (`quietPoses`), Show(nil) left timers live,
  Idle loop without SetAnimation, Survivor's second settle timer, Panel.ShowIdle unused, per-view zoom without memory,
  unknown preset silent, `/gg caught model` view per call + error vs unknown, lint holes (string args, more methods
  and frame types, exceptions scoped to the capture functions), tests for RF2 asleep / RF3 SetScript / RF4 re-watch,
  doc wording. Harmless changes kept and written in the CHANGELOG (late load keeps pose and facing, arena fallback
  animation, scale refresh covers the AZEcaught views)
- Evidence: `luajit tests/run.lua` -> 255 passed, 0 failed; planted violations in UI/TeamDialog.lua and a new Catcher
  function reported by the lint ("UI/TeamDialog.lua:488 SetCreature | ... SetAnimation | ... Model", "Core/Game/Catcher.lua:1743 SetCreature | ... PlayerModel")
- Next: review round 2 on the fixes, then verify.md, commit on the branch, in-game check by the user

## 2026-11-28 14:01 | VERIFY | T8 review round 2: split confirmed
- Did: the subagent re-checked every fix; its 3 nits fixed (probe hide timer counts calls, lint scope ends at a
  top-level line, lint catches `frame["Method"]`)
- Result: "SPLIT CLEAN: yes", "REUSE GUARANTEED: yes"; all offline rows pass, R9 (no visible change) needs the game
- Evidence: `luajit tests/run.lua` -> 255 passed, 0 failed; planted `frame["SetAnimation"](frame, 1)` reported
- Next: user: restart the game on branch feature/model-display and run the in-game checklist in verify.md; then done + merge to master

## 2026-11-28 14:06 | VERIFY | Final sweep by a second, simple subagent
- Did: grep of Core/ and UI/ for every model frame word (frame types, load, animation, camera, model file calls) outside UI/ModelView.lua
- Result: "LEFTOVER MODEL CODE: none"; the only hits are the allowed hidden look capture (Catcher.CreatureDisplay /
  CaptureDisplay and helpers, Api.IdentityProbe / GenderProbe), DevProbe, a "HasAnimation missing" text in /gg caught probe
  and a comment in Core/View/Model.lua; every creature display gets its view from addon.ModelView.New
- Evidence: the subagent's report (this entry)
- Next: user: in-game checklist in verify.md on branch feature/model-display; then done + merge to master

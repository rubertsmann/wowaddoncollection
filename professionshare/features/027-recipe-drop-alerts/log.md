# 027 Recipe drop alerts: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-24 11:22 | PLAN | Feature created
- Did: scaffolded `features/027-recipe-drop-alerts/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-24 12:20 | BUILD | T1-T6 built
- Did: `Core/Data/RecipeDrops.lua` (new, pure), `Core/Game/Drops.lua` (new), Sync DROP/DROPA handlers + BroadcastDrop/AnswerDrop, Communication wiring and priority types, PROTOCOL_MINOR 7, `UI.SetDropNotice` + minimap tooltip, deDE strings, Dev tools triggers "Recipe drop from a member" / "Answers to my recipe drop" (removed by Remove all fake data), docs (protocol.md 15, README, CHANGELOG, status.md)
- Result: two bugs caught by the tests and fixed: RecipeDrops.Get returned false with nothing stored; "/ps drops x off" parsed to nil (and/or with false)
- Evidence: `luajit tests/run.lua` -> 310 passed, 0 failed (baseline 302); tools/deploy.ps1 regenerated the dev TOC
- Next: user: in-game checklist in verify.md (restart the game: new files), then a real drop with a second member

## 2026-11-24 11:52 | NOTE | Correction: entry time
- Did: the BUILD entry stamped 12:20 was written without reading the clock; it happened shortly before 11:47
- Result: n/a
- Evidence: `date` -> 2026-11-24 11:49
- Next: VERIFY below

## 2026-11-24 11:52 | VERIFY | Dev triggers on Forever, review
- Did: read devChecks.dropIn / dropMine and the saved log after the user's reloads; ran review-professionshare
  (review/recipe-drops.md): D1 a DROP for a non-recipe item could alert -> fixed (Drops.OnDrop requires the Recipe class)
- Result: incoming drop learnable, answer g 144 captured, alert raised; tooltip rows Cook 300 / Alchemist 280 / Skinner 265 + 1 more
- Evidence: devChecks 11:48:16 / 11:48:18; `luajit tests/run.lua` -> 310 passed, 0 failed
- Next: DONE below

## 2026-11-24 11:52 | DONE | Accepted by the user
- Did: user: "check everything commit then finalize"
- Result: done; open: a real drop and two members (accepted gaps in verify.md)
- Evidence: verify.md
- Next: none

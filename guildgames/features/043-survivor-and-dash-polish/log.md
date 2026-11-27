# 043 Survivor and Companion Dash polish (models fit their box, target dropdown, icon start, framed stats): log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-27 09:02 | PLAN | Feature created
- Did: scaffolded `features/043-survivor-and-dash-polish/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-27 09:06 | BUILD | T1-T6 model fit, refresh on scale, target dropdown, icon start, framed runner stats
- Did: the dev journal shows `model.survivor ... topView=true`: the Survivor companion uses the custom top camera at a fixed 4 yards, so a big creature overflows its 64 px frame. `UI/CompanionModel.lua`: model registry, `Refresh`/`RefreshAll` (RefreshCamera + Frame, shown and loaded models only), re-frame on OnShow, `FitDistance` (client camera back to default, GetCameraDistance else |position - target|, once per creature, rejects 0/NaN/huge). `UI/SurvivorArena.lua`: `SurvivorArena.TopCamera` (fitted distance x1.15, clamped 1.5-80, 4 yd fallback), target from the fitted camera; target dropdown (`targetDropdown`, `targetMenu`, `targetRows`, click-away close, closed on run start and panel hide); Start is `CreateIconButton` with kinds start/giveup/cashout (`paintStart`). `UI/Window.lua`: `placeWindow` calls `CompanionModel.RefreshAll()` when the scale changed; icon kinds start/giveup/cashout and `SetKind`. `UI/RunnerView.lua`: monster camera 1.2; stats and result in a bordered box with a divider. `addBorder` moved from ArenaView to `UIHelpers.AddBorder` (one copy). Tests: new "models are framed by their size and framed again after the window scaled"; the survivor UI test uses the dropdown and the icon kinds.
- Result: pass
- Evidence: `luajit tests/run.lua` -> 218 passed, 0 failed. The wow-ui-sim tool used in 035 is no longer in the repo: no screenshot.
- Next: user checks in game (verify.md checklist): a big companion in Survivor at several window sizes, Companion Dash monsters, the dropdown, the icon, the stats box. Paste `/gg caught log 5 model` if the Survivor companion is still too big or too small (the line carries height and fitted).

## 2026-11-27 09:39 | DEVIATION | No cut-off: padded model frames and shimmering hitboxes (user feedback)
- Did: user ran `/gg caught log 5 model` and reloaded: Survivor companion "slightly too big", "dont cut off but show a shimmering hitbox". Journal: `fitted=true height=1.5 topView=true` on every frame (the 1.5 minimum clamp). `UI/CompanionModel.lua`: `options.pad` (frame x pad, camera x pad, fallback icon kept in place; callers place by centre). `UI/Helpers.lua`: `UIHelpers.CreateHitbox` (additive outline or ring over a faint fill) and `UIHelpers.Shimmer`. `UI/SurvivorArena.lua`: pet pad 2, top camera x1.25 further back, raw distance in the journal line, tower hit ring (Survivor.TOWER_RADIUS) pulsing above the companion, below the monsters. `UI/RunnerView.lua`: runner and monster frames pad 1.8 placed by centre (MONSTER_CAMERA margin removed), hitbox outlines from `Runner.RunnerBox` sizes and `Runner.ObstacleBox`, pulsing out of step. Spec R3 rewritten.
- Result: pass
- Evidence: `luajit tests/run.lua` -> 218 passed, 0 failed (model test now covers padding and the padded heights)
- Next: user: `/reload`, check Survivor and Companion Dash with a big creature (no cut-off, hitbox visible, size right); paste the "survivor companion was framed" line (now with `distance`) if the size is still off.

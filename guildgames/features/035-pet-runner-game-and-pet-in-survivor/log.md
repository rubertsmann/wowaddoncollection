# 035 Pet runner game and pet in Survivor: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-25 10:59 | PLAN | Feature created
- Did: scaffolded `features/035-pet-runner-game-and-pet-in-survivor/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-25 11:00 | DECISION | 10 design questions answered, spec filled
- Did: asked 10 questions (money, sharing, no pet, pool, size, duck, controls, difficulty, parallax, payout) plus the Survivor pet request; filled spec.md (R1-R13, T1-T10, RF1-RF5, checklist)
- Result: free play 1g/100 m capped 50g/day, guild leaderboard (protocol 1.4 additive), locked without companion, all seen+caught monsters at one box size, flyers at head height, hold-to-jump-higher / hold-to-duck, one hit ends, client textures for parallax; Survivor shows the companion with attack animations
- Evidence: spec.md Decisions
- Next: user reviews the spec (game name, top-view probe); then T1 probe + T2 Runner.lua tests first

## 2026-11-25 11:34 | BUILD | T2-T5 Runner.lua, payout, section, pool (tests first)
- Did: Core/Minigames/Runner.lua (fixed 1/120 s tick, frame cut 0.1 s, own seeded random, AABB with 4 px inset, gap never shorter than one jump, flyers from 150 m, pairs from 380 px/s; payout/daily cap; db.runner; section + sanitize; board/feed rows); Games.Sanitize/SetSection take "runner"; Store.SanitizePersisted repairs db.runner; PROTOCOL_MINOR 4 (Init, tests/run.lua, test_load); TOC; tests/test_runner.lua (11 tests incl. an autopilot surviving 1500 m on 6 seeds)
- Result: pass
- Evidence: luajit tests/run.lua -> 170 passed, 0 failed
- Next: UI

## 2026-11-25 11:34 | DEVIATION | No new collection field; model helper not retro-fitted
- Did: flying comes from entry.st.type / st.family (already stored by NoteFound), so no CollectionEntry.typ and no Api change. UI/CompanionModel.lua is used by the runner, Survivor and /gg caught model; PetView/ArenaView keep their own model code (they work and have their own camera/zoom/emote timers; moving them is risk without gain now). spec.md updated.
- Result: spec matches the code
- Evidence: spec.md Design / T5 / T6
- Next: UI

## 2026-11-25 11:34 | BUILD | T6-T9 model helper, RunnerView, Survivor pet, switch, locale, docs
- Did: UI/CompanionModel.lua (side-table state, Load display->creature, Play first available animation); UI/RunnerView.lua (sky gradient, clouds/mountains/hills as Disc shapes, ground + pebbles, 6 pooled obstacle models + shadows + icon fallback, runner model, mouse halves + Space/Up/W/Down/S with keyboard only during a run, HUD, result, lock); GamesTab (runner button last, IsBusy, distance board/feed, "Best" header, last week's longest run); SurvivorArena (companion model over the tower, custom camera from above when MakeCurrentCameraCustom/SetCameraPosition/SetCameraTarget work, faces the nearest monster, attack on shot/zap/cleave/nova/blast, ready afterwards; icon when no model); /gg caught model probe; deDE; README, CHANGELOG (Unreleased), docs/protocol.md 1.4; test_load runner block; test_games_ui file list
- Result: pass; simulator 0 Lua errors in all scenarios. Mountains were first rotated colour squares (the simulator ignores SetRotation): switched to tall Disc ellipses
- Evidence: luajit tests/run.lua -> 170 passed, 0 failed; evidence/sim-run.png, sim-locked.png, sim-survivor.png (sim-runner.lua; the simulator draws no 3D models and washes colours out)
- Next: user runs the in-game checklist in verify.md (models, input, look, /gg caught model for the top view)

## 2026-11-25 11:38 | BUILD | Survivor grass floor and clipped arena (user feedback)
- Did: user: runner "looks and works fine"; asked for a grass ground in Survivor with the same shape logic and for projectiles to stay inside the window. UI/SurvivorArena.lua: buildGrass (opaque grass base, 16 darker/lighter patches, 34 tufts, 10 flowers, 5 stones, trodden earth under the tower, dark edges; Disc texture, fixed seed) replaces the almost clear plate; the arena clips its children (SetClipsChildren), so projectiles, monsters and their effects end at the arena edge (rings/banners on the panel-level effects layer are unchanged)
- Result: pass; simulator 0 Lua errors, patches/stones/flowers drawn, a monster at the edge is cut off
- Evidence: luajit tests/run.lua -> 170 passed, 0 failed; evidence/sim-survivor.png
- Next: user checks the grass look and the clipping in game; then release when wanted

## 2026-11-25 11:41 | DONE | Confirmed in game, released as 0.9.0
- Did: user confirmed the whole in-game checklist ("yes to everything": top view and facing, runner animations, flyers/duck, keys not blocked when idle, payout and board, a second member sees the board, frame rate, the name) and asked to release; verify.md rows set to IN-GAME / MULTI-CLIENT; spec and doc final; version 0.9.0 (TOC, Dev TOC, Init), CHANGELOG, RELEASE_NOTES
- Result: done
- Evidence: verify.md; release commit and tag guildgames/v0.9.0
- Next: none

## 2026-11-25 12:08 | BUILD | Stand-in icons while a model is not drawn (after 0.9.0)
- Did: user: in game it works, but in the simulator nothing shows because no model is drawn. UI/CompanionModel.lua: optional fallback icon (child frame of the model) shown until OnModelLoaded fires or GetModelFileID reports a file; IsRendered, SetFallbackIcon. RunnerView: wolf for the runner, boar / bat (mirrored) for ground / flying monsters (replaces its own icon); Survivor pet: wolf icon. test_games_ui "a model's stand-in icon shows until the model is drawn"
- Result: pass; the simulator now shows the runner and the monsters as icons; in game the model hides the icon once drawn
- Evidence: luajit tests/run.lua -> 171 passed, 0 failed; evidence/sim-run.png
- Next: user checks in game that no icon stays visible behind a drawn model; commit/release when wanted (not released yet)

## 2026-11-25 12:15 | BUILD | AZEcaught tabs locked until a companion is chosen (after 0.9.0)
- Did: user: disable every tab except Companion and Collection until a pet is chosen; the first caught pet is chosen automatically (already true: a catch while none is active selects it, AzeCaught.lua recordCatch, test_azecaught "a catch becomes the companion when none is active"). UI/AzeCaughtPanel.lua: Panel.NEEDS_COMPANION (arena, guild, shop, inventory), ViewLocked, UpdateViewButtons (greyed, desaturated, tooltip "Catch a companion first: your next catch becomes it."), UpdateViewLocks on CAUGHT_CHANGED (a catch unlocks, losing the companion goes back to Companion); SelectView opens Companion instead of a locked tab and keeps the saved view; deDE; test_load asserts the locks and the unlock
- Result: pass; simulator: tabs greyed, a shop request opens Companion
- Evidence: luajit tests/run.lua -> 171 passed, 0 failed
- Next: commit/release when wanted (not released yet)

## 2026-11-25 13:37 | DONE | Follow-ups released as 0.9.1
- Did: user confirmed the tab locks and the stand-in icons work ("everything seems to be working fine") and asked to release; version 0.9.1, CHANGELOG, RELEASE_NOTES
- Result: done
- Evidence: release commit and tag guildgames/v0.9.1
- Next: none

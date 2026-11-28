# 057 Shared model view: spec

- Status: done
- Created: 2026-11-28
- Target version: next minor (no player-visible change intended)
- Owner: claude
- Branch: `feature/model-display` (merged to master only when done)
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
Every 3D creature model in GuildGames is created, loaded, framed and animated through ONE module, `UI/ModelView.lua`,
with one documented interface (an options class + an object whose functions are called with a dot, like
LibGuildSync's `Channel.New`), so no view keeps its own model code.

## Inventory (before the rework)

| # | Where | Frame | How it was made | Model code it carried |
|---|---|---|---|---|
| 1 | Companion view (max view), `UI/AzeCaughtPanel.lua` `widgets.model` | DressUpModel 300x150 | panel-local `createModel` | load (display, else creature), ClearModel, facing 0.4, camera fit, wheel zoom per NPC, right-drag turn, idle/asleep pose, action emote + timer back to idle, ambient idle emotes, reload on show + late refit, load journal |
| 2 | Pet view (mini view), `UI/PetView.lua` `widgets.model` | DressUpModel | raw `CreateFrame` + `Panel.PrepareModel` | its own reload on show, late refit, asleep-change check, ambient emotes through the panel |
| 3 | Collection preview, `AzeCaughtPanel` `widgets.previewModel` | DressUpModel 104x150 | `createModel` | stand pose |
| 4 | Guild preview, `AzeCaughtPanel` `widgets.guildModel` | DressUpModel 104x116 | `createModel` | stand pose |
| 5 | Arena replay, `UI/ArenaView.lua` two `part.model` | DressUpModel 132x170 | `Panel.CreateModel` | its own animation table, pick, timed return to ready, death once + lying, side state table, facing |
| 6 | Team dialog carousel, `UI/TeamDialog.lua` `card.model` | DressUpModel | `Panel.CreateModel` | facing per side |
| 7 | Companion Dash runner + obstacles, `UI/RunnerView.lua` | PlayerModel, padded | `CompanionModel.Create` | fallback icon, run/jump/hurt |
| 8 | Survivor tower pet, `UI/SurvivorArena.lua` | PlayerModel, padded | `CompanionModel.Create` | afterLoad top camera from FitDistance, attack/ready, facing to a target |
| 9 | `/gg caught model` capability probe, `Core/Game/Catcher.lua` | PlayerModel | `CompanionModel.Create` | methods / animations dump |
| 10 | `/gg caught probe`, `Core/Game/Catcher.lua` | (the companion view's model) | `AzeCaughtPanel.widgets.model` | HasAnimation dump |
| - | Hidden capture models (`Catcher.CaptureDisplay`, `Api.GenderProbe`) | PlayerModel, never shown | own | not displays: they read a unit's display/model file. Stay in Core/Game (WoW calls), out of scope |
| - | `UI/DevProbe.lua` lane probe (uncommitted feature 056 work) | PlayerModel | `CompanionModel` | ported in the working tree only (not part of this branch's commits) |

Two model helpers (panel-local and `UI/CompanionModel.lua`) and a third animation copy (ArenaView) did the same jobs
with different rules (animation pick, camera, reload).

## Requirements
- R1: One module `UI/ModelView.lua` (`addon.ModelView`) is the only code that calls model frame methods for displayed
  models (SetDisplayInfo, SetCreature, ClearModel, SetAnimation, HasAnimation, SetFacing, SetCamDistanceScale,
  SetPortraitZoom, SetPosition, OnModelLoaded). `UI/CompanionModel.lua` is deleted; AzeCaughtPanel no longer exports
  CreateModel / ShowModel / PrepareModel / FitCamera / ZoomModel. Pinned by a lint test over `UI/` and `Core/`.
- R2: Interface: `ModelView.New(parent, options)` returns a view; `view.frame` is the model frame (anchoring,
  Animate effects); every function is bound to the view and called with a dot: `Show`, `Forget`, `Frame`, `Refresh`,
  `Play`, `Emote`, `Idle`, `Die`, `Revive`, `Face`, `Zoom`, `Tick`, `IsRendered`, `FitDistance`, `SetFallbackIcon`.
  Options are one documented `---@class ModelViewOptions`.
- R3: Loading: a creature `{ npc, disp }` loads by display id when it has one, else by NPC id; the same creature again
  does nothing; nil clears. Load and failure are journaled when the view has an `area`.
- R4: One animation catalogue `ModelView.ANIMATION` (keys) and one pick rule: the first candidate the model has; the
  first when the client cannot tell; the last when it has none of them.
- R5: Poses: every view has an idle pose (default `stand`); after every (re)load the current loop plays again, else the
  idle pose. `Play(key, { back = s })` returns to the idle pose after s seconds; a newer Play/Idle voids the timer.
  `Emote` = Play with the emote time, and marks the view busy (no ambient emote meanwhile).
- R6: Death: `Die()` plays the death once, then the lying pose; a dead view ignores Play/Emote/Idle until `Revive()`
  or a different creature is shown.
- R7: Companion views (`companion = true`): show the active companion, idle pose = asleep while it sleeps else stand,
  switch pose when it falls asleep / wakes, ambient idle emotes while awake and visible (dev `/ggd caught emote` forces
  one on every companion view), reload + idle on show with one late re-frame. Max view and mini view share this code.
- R8: Interaction options: `turn` (right-drag turns), `zoom` (mouse wheel, remembered per NPC for the session,
  limited), the start camera distance and padding, facing, fallback icon until drawn, `afterLoad` hook. The window
  scale change re-frames every shown view (`ModelView.RefreshAll`).
- R9: No visible behaviour change: every view keeps its size, facing, camera distance, poses and interactions.

## Non-goals
- The hidden capture models that read a unit's look (`Catcher.CaptureDisplay`, `Api.GenderProbe`): no display.
- A library shared with ProfessionShare (it shows no models).
- New animations or new camera behaviour.

## Design
- `UI/ModelView.lua` (new, loaded after `UI/Animate.lua`, before `UI/Window.lua`): options class, view object, the
  catalogue, the pick rule, poses, death, zoom memory (`ModelView.zoomByNpc`), the registry for RefreshAll, companion
  mode. Every client call guarded with pcall (clients differ).
- `UI/CompanionModel.lua` (deleted), TOC + `tests/test_games_ui.lua` file list updated.
- `UI/AzeCaughtPanel.lua`: the four views through ModelView; care emotes via `view.Emote`; `Panel.ShowIdle` ->
  `view.Idle`; info-panel hover hooks on `view.frame`; widgets hold views (`widgets.companionModel`,
  `widgets.previewModel`, `widgets.guildModel`).
- `UI/PetView.lua`: `ModelView.New(pet, { companion = true, ... })`; refresh = `view.Show()` + `view.Tick()`.
- `UI/ArenaView.lua`: animation table, pick, state table and timers removed; `react` uses `view.Play/Die`.
- `UI/TeamDialog.lua`, `UI/RunnerView.lua`, `UI/SurvivorArena.lua`, `Core/Game/Catcher.lua` (probe commands), `UI/Window.lua`
  (RefreshAll): through views.
- Data shape change: none. Message shape change: none.
- Pure logic: the pick rule and the zoom clamp are plain functions on ModelView, tested with fake frames (the module
  needs CreateFrame only in `New`).

## Tasks
- [x] T1 (S): inventory of every model display (table above). Verify: grep in log.
- [x] T2 (L): `UI/ModelView.lua` + `tests/test_model_view.lua` (load, same creature, clear, pick rule, back timer, newer
  call voids timer, death/revive, companion idle/asleep, ambient emote + forced, zoom limits + memory, fallback,
  FitDistance, RefreshAll). Verify: suite.
- [x] T3 (M): Runner, Survivor, Catcher `/gg caught model` onto ModelView; delete `UI/CompanionModel.lua`. Verify: test_games_ui.
- [x] T4 (L): AzeCaughtPanel (companion, preview, guild) + PetView onto companion/preview views. Verify: test_load, test_pet_view.
- [x] T5 (M): ArenaView + TeamDialog onto views. Verify: test_load arena replay.
- [x] T6 (S): lint test: no model frame method outside `UI/ModelView.lua` (allow-list: the hidden capture models in
  Core/Game). Verify: suite.
- [x] T7 (S): docs: `docs/coding-conventions.md` "One helper per job" row + folder note, README if needed, CHANGELOG,
  `guildgames-new-item` / feature skill note if they mention models, doc.md. Verify: read.
- [x] T8 (S): independent review by a subagent: split clean, reuse guaranteed. Verify: its report in log.md.

## Review Focus (failure modes a happy-path test would miss)
1. RF1: an async load (OnModelLoaded after Show) resets the animation -> the loop/idle is set again. Pinned by: T2.
2. RF2: an emote's back-to-idle timer fires after a newer emote or after the companion fell asleep -> the newer wins,
   asleep pose stays. Pinned by: T2.
3. RF3: a client without HasAnimation / SetCamDistanceScale / OnModelLoaded -> no error, first candidate. Pinned by: T2.
4. RF4: a dead arena fighter shown again for a re-watch -> it stands again (Revive on Show of the fight). Pinned by: T5.
5. RF5: a hidden view during a window scale change -> left alone until its OnShow. Pinned by: T2.

## Cross-cutting checklist
- [x] Protocol: unchanged (UI only).
- [x] Stored data: unchanged, no migration.
- [x] Trust model: n/a, no peer data parsed; peer creature ids already validated by Sync/Arena before they reach a view.
- [x] Localization: no new player text.
- [x] Load order: `UI/ModelView.lua` after `UI/Animate.lua`, before `UI/Window.lua` (Window calls RefreshAll; the panels
  create views at Build time). CompanionModel.lua removed from the TOC.
- [x] Packaging: `tools/package.ps1` reads the TOC file list (checked in T3).
- [x] Tests: `tests/test_model_view.lua` new; test_games_ui / test_load updated.
- [x] Docs: coding-conventions, CHANGELOG, doc.md, feature-workflow + bug-workflow skills (T7).

## Decisions (newest last)
- 2026-11-28: work on branch `feature/model-display`, merge to master only when the feature is done (user).
- 2026-11-28: the interface follows LibGuildSync's Channel: `New(options)`, functions bound to the object and called
  with a dot, state in plain fields (user: "clean structure interface similar to the messaging lib").
- 2026-11-28: the companion views keep DressUpModel and reload on show (their old behaviour); the game actors keep
  PlayerModel (`frameType` option) so nothing changes visibly.
- 2026-11-28: one pick rule (first it has, else the last; first when the client cannot tell). The arena lists used to
  play nothing when the model had none; the last candidate is harmless (the client ignores an animation a model lacks).
- 2026-11-28: review round 1 (subagent): Reload in a hidden frame only forgets; `quietPoses` for the arena; Survivor's
  own settle timer replaced by `back`; lint scoped to the capture functions and string arguments; views are made once
  per place (they live for the session).
- 2026-11-28: the uncommitted feature 056 DevProbe code is ported in the working tree so it keeps loading, but is not
  committed on this branch (it belongs to 056).

## Open questions
- none

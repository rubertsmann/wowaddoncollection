# 043 Survivor and Companion Dash polish (models fit their box, target dropdown, icon start, framed stats): spec

- Status: done
- Created: 2026-11-27
- Target version: GuildGames 0.13.0
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
Big creature models stay inside their box at every window size, and the Survivor and Companion Dash controls stop
overlapping and read clearly.

## Requirements
- R1: Survivor: the companion seen from above is framed by its own size. The camera height comes from the distance the
  client picked to fit the model (not a fixed 4 yards), so a big creature is as large as a small one in the tower spot.
- R2: Every game model (Survivor companion, Companion Dash runner and monsters) is framed again when the window's scale
  changes and when the model is shown again, so its drawn size follows the window size.
- R3: Models are never cut off: their frames are larger than the space the creature is drawn in (Companion Dash x1.8,
  Survivor x2) with the camera that much further out, so the drawn size stays and a big creature has room. Instead of
  shrinking creatures into their box, a shimmering hitbox (pulsing gold outline; a ring for the Survivor tower, boxes
  for the Companion Dash runner and monsters) shows what really collides.
- R4: Survivor: the row of target buttons is replaced by one dropdown ("1:00 x2", ..., "Endless"). It is locked during a
  run, closes on a pick, on a click elsewhere and when the panel hides; the choice is saved as before.
- R5: Survivor: Start is an icon button: a charge icon to start, a red X to give up, a coin to cash out (endless after
  the first minute). The word is in the tooltip.
- R6: Companion Dash: the stats and the result under Start sit in a framed box (dark shade and a 1 px gold border).

## Non-goals
- No change to rules, payouts, data or messages.
- Companion Dash keeps its text Start button (the icon request was for Survivor).
- No true per-creature bounding boxes (the client gives none to PlayerModel frames).

## Design
- `UI/CompanionModel.lua` (changed): a registry of created models; `CompanionModel.RefreshAll()` re-frames every shown
  loaded model (`RefreshCamera` when the client has it, then `Frame`); models re-frame on show;
  `CompanionModel.FitDistance(model)` reads the client's fitted camera distance (`GetCameraDistance`, else the distance
  between `GetCameraPosition` and `GetCameraTarget`), nil when unknown.
- `UI/Window.lua` (changed): `placeWindow` calls `CompanionModel.RefreshAll()` after a scale change; the icon button gets
  `SetKind(kind)` and three new looks (`start`, `giveup`, `cashout`).
- `UI/SurvivorArena.lua` (changed): `lookFromAbove` sets the camera straight above the fitted target at the fitted
  distance; the target dropdown and its menu; the icon start button.
- `UI/RunnerView.lua` (changed): monster camera scale 1.2; a framed stats box.
- Data shape change: none. Message shape change: none.

## Tasks
- [x] T1 (M): CompanionModel registry, RefreshAll, FitDistance, re-frame on show; Window calls it on scale. Verify: test_games_ui "models are framed again..." + in-game.
- [x] T2 (S): Survivor top camera by fitted distance. Verify: test_games_ui (fake camera) + in-game with a big companion.
- [x] T3 (M): Survivor target dropdown. Verify: test_games_ui survivor test (rows, lock, close).
- [x] T4 (S): Survivor icon start (start/giveup/cashout). Verify: test_games_ui survivor test (kinds).
- [x] T5 (S): Runner monster margin and framed stats box. Verify: test_load builds; in-game look.
- [x] T6 (S): deDE, CHANGELOG, doc.md, verify.md.

## Review Focus (failure modes a happy-path test would miss)
1. RF1: The client has no GetCameraDistance / GetCameraPosition, or returns nonsense -> the old fixed height is used. Pinned by: T2 test.
2. RF2: A window drag calls RefreshAll on every frame -> it only touches shown, loaded models; the Survivor top view is re-applied by `afterLoad`.
3. RF3: The dropdown menu stays open across a run start or a game switch -> closed by Start and by the panel hiding.
4. RF4: The cash-out icon must come back to give up / start in the right moments (milestone -> cashout, finish -> start). Pinned by: T4 test.

## Cross-cutting checklist (answer every line; "n/a: reason" is fine)
- [x] Protocol: unchanged (UI only).
- [x] Stored data: unchanged (`ui.survivorTarget` keeps its meaning).
- [x] Trust model: n/a, no peer data shown in the changed parts.
- [x] Localization: no new strings (tooltips reuse "Start", "Give up", "Cash out"; the dropdown reuses "{time} x{n}" and "Endless").
- [x] Load order: unchanged (no new files).
- [x] Packaging: unchanged.
- [x] Tests: test_games_ui survivor test updated; a model refresh test.
- [x] Docs: CHANGELOG, doc.md.

## Decisions (user answers and design choices, newest last)
- 2026-11-27 (user): big monsters scale out of their box depending on the window size; the Survivor timer buttons
  overlap: a dropdown instead; Start only an icon; Companion Dash stats need a clear border.
- 2026-11-27: "Start only an icon" applied to Survivor (said in its sentence); Companion Dash keeps its button.
- 2026-11-27: Cause found in the journal: the Survivor companion uses the custom top camera (`topView=true`) at a fixed
  4 yards, so a big creature fills more than its 64 px frame. The fitted default distance replaces it.

- 2026-11-27 (user, after testing): the Survivor companion was "slightly too big"; "dont cut off but show a shimmering
  hitbox". Journal: `fitted=true height=1.5` every time (the minimum clamp: the client reports a small distance), so the
  fit did not scale. Now: padded frames (no cut-off), the top camera 1.25x further back, the raw distance in the journal
  for tuning, and hitbox markers. The 1.2 monster camera margin is replaced by the padding.

## Open questions
- Whether this client's PlayerModel has `RefreshCamera` / `GetCameraDistance` (needs: game; both are guarded).

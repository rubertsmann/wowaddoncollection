# 043 Survivor and Companion Dash polish: documentation

## What it does
- Survivor: your companion seen from above is framed by its own size, so a big creature fits the tower spot.
- Every game model is framed again when the window is scaled (grip) or shown, so it keeps its size relative to the game.
- Models are never cut off: their frames have room around the creature. A pulsing outline shows what really collides:
  a gold ring for the Survivor tower, a blue box for the Companion Dash runner and gold boxes for the monsters.
- Survivor: the bet target is one dropdown instead of a row of buttons; Start is an icon (charge = start, red X = give up,
  coin = cash out in endless mode). Hover for the word.
- Companion Dash: the best distance, today's gold and the last result sit in a framed box.

## How it works
- `CompanionModel.FitDistance(model)`: once per creature, with the client's own camera, reads `GetCameraDistance` (else
  the distance between `GetCameraPosition` and `GetCameraTarget`). The client fits that distance to the creature's size.
  `SurvivorArena.TopCamera` puts the custom camera straight above the fitted target at 1.15x that distance (1.5-80 yd);
  without a usable number it keeps the old fixed 4 yd. The journal line "the survivor companion was framed" carries
  `height` and `fitted`.
- `CompanionModel.RefreshAll()` (from `placeWindow` when the scale changed) and each model's OnShow call `RefreshCamera`
  (when the client has it) and re-apply the framing.
- `CompanionModel.Create(..., { pad = p })`: the frame is p times larger and the camera p times further out, so the
  creature is drawn at the same size with room around it; callers place the frame by its centre. Survivor pad 2 (and
  the top camera 1.25x further back), Companion Dash pad 1.8.
- Hitbox markers: `UIHelpers.CreateHitbox` (additive outline or ring) placed from `Survivor.TOWER_RADIUS`,
  `Runner.ObstacleBox` and the runner box; `UIHelpers.Shimmer` pulses them from the panel's OnUpdate.
- No data or message changes.

## Limits and known issues
- Depends on the client reporting a camera distance; otherwise Survivor falls back to the fixed height (as before).
- Companion Dash keeps a text Start button.

## Verification
See [verify.md](verify.md): offline 218/0; the look and the model sizes need the game.

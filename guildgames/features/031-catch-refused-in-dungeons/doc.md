# Catch refused in dungeons

Status: verifying | Since version: 0.6.0 | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
Inside a dungeon or raid the game hides the enemy values AZEcaught needs, so a rope throw (`/gg catch`, the key
binding or the nameplate icon) is refused there with a red line at the top of the screen and the same line in chat:
"Catching does not work in dungeons and raids."

Two more limits: the rope is refused at an enemy someone else tagged ("Someone else tagged this one ...") and at
one farther than 28 yards ("Too far away ..."). When the client does not tell either, the throw is allowed.

## How to use
- Commands: `/gg catch` (as before). Nothing to set.

## How it works
- Data: no change. Messages: no change.
- Modules: `Api.InDungeon()` (instance kind "party" or "raid"), `Api.ShowOverlay(text)` (UIErrorsFrame), check at the
  start of `Catcher.Throw`; the refusal is journaled as `throw.refused` with reason `instance`.

## Localization
Three new strings (dungeon, tagged, range), translated in deDE.

## Limits and known issues
- Scenarios, battlegrounds and arenas are not refused.
- The range uses `CheckInteractDistance(unit, 4)` (28 yards). Retail restricts it for hostile units in combat; if this
  client does too, the range rule does nothing in combat (see verify.md RF3).

## Changelog line
- `/gg catch` (and the binding/icon) inside a dungeon or raid now says on screen and in chat that catching does not work there.

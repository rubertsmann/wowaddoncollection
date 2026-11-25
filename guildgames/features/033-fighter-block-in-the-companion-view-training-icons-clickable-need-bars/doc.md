# Fighter block in the Companion view (training icons, clickable need bars)

Status: verifying | Since version: 0.7.0 | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
- **Companion view (full window):** under the pet's name a line "Arena level N  xW yL" with a thin XP bar (hover: XP,
  the four stat values, the ability). The four need bars are the care buttons. Below them, where the care icons
  were, are the four stat icons (Attack, Defense, Speed, Vitality) with their trained points ("10/25").
- **Training:** a click on a stat icon starts that training at once (gold, 15 energy, 10 minutes of play time). The
  training icon darkens from the top as the time passes and shows the time left. The other icons are greyed out. A
  refusal (busy, tired, asleep, no gold, maximum) shows in the status line.
- **Care:** click the Food bar to feed, Water to water, Petting to pet, Energy to sleep (or wake). The tooltip shows
  the price, or why it cannot be done (icon dimmed). The 1.5 s click cooldown is shared with the minimal view.
- **Minimal view:** a small round button at 6 o'clock under the pet (tooltip "Training" and the running training; a
  gold ring while one runs). A click opens the four stat icons below it. A click on one trains, and the time shows on
  that icon. A click anywhere else closes the row. Refusals go to the red error line.
- **Arena view:** only Guild and Fights.

## How it works
- No new data, nothing sent. `ArenaView.FighterState()` (companion, fighter, arena entry, the training if it is this
  companion's), `ArenaView.CreateStatIcon` / `FillStatIcon` (shared by both views), `ArenaView.BuildFighterBlock` /
  `RefreshFighter`. `AzeCaughtPanel`: `createBar(..., careKey)`, `widgets.careBars`, `AddCareTooltip`, `ShowStatus`.
  `PetView.BuildTraining` / `ToggleTraining` / `CloseTraining` / `RefreshTraining`. `Model.PetViewLayout().train`.

## Localization
New: "Training", "Click: train.", "Click:", "{wins}W {losses}L" (deDE). Removed (unused): "Train", "free", the old
"You need a companion to fight..." text.

## Limits and known issues
- The outside click uses `GLOBAL_MOUSE_DOWN`. If this client does not know it, a screen-wide catcher closes the row
  and eats that one click.
- The progress shade follows play time (training counts play time), so it pauses when you are idle.

## Changelog line
- The fighter moved into the Companion view (stat icons train on click, level/XP under the name); need bars are the care buttons; the minimal view has a training button.

# 033 Fighter block in the Companion view (training icons, clickable need bars): spec

- Status: verifying
- Created: 2026-11-25
- Target version: GuildGames 0.7.0 (protocol 1.3, schema 2)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
The fighter (arena level, XP, W/L, the four stat trainings) lives in the Companion view below the pet; the care
actions move onto the need bars, and Arena > Fighter goes away.

## Requirements
- R1: The Companion view shows, under the pet's name, "Arena level N" with W/L and a thin XP bar; its tooltip has the
  XP numbers, the ability and the four stat values.
- R2: Where the four care icons were, four stat icons (Attack, Defense, Speed, Vitality) each show "points/maximum"
  (e.g. 10/25) below them.
- R3: A click on a stat icon starts that training at once (no confirm). Cost, energy, time and the bonus are in its
  tooltip; a refusal (energy, gold, busy, asleep, maximum) shows in the view's status line.
- R4: While a stat trains, its icon shows the progress (a shade that shrinks) and its label shows the time left in
  gold; the other icons are greyed out. A fully trained stat is greyed out.
- R5: Each need bar is clickable: Food = feed, Water = water, Petting = pet, Energy = sleep (wake while asleep).
  Tooltip: the need's timing plus the action and its price, or why it cannot be used. Greyed out (icon dimmed) when
  unusable or during the 1.5 s care cooldown; the click cooldown is shared with the compact pet view as before.
- R6: The Arena view has only Guild and Fights; a saved page "fighter" opens Guild.
- R7: No companion: none of the fighter block shows (the empty text stays).
- R8: New/changed texts localized (deDE).
- R9: The compact pet view has a small training button at the bottom (tooltip "Training", plus the running training).
  A click opens the four stat icons in a row; a click on one starts that training, the time shows on its icon, the
  others are greyed out. A click anywhere else (or on the button again) closes the row.

## Non-goals
- No change to training rules (cost, 25 points, 10 min play time, 15 energy) or to fights.
- No new stored data and nothing new sent.

## Design
- `UI/ArenaView.lua` (changed): the fighter page is replaced by `ArenaView.BuildFighterBlock(panel)` (level line +
  XP bar + tooltip holder, four stat icon buttons with label and progress shade) and `ArenaView.RefreshFighter()`
  refreshes it; `ArenaView.Train` reports refusals through `addon.AzeCaughtPanel.ShowStatus`. Pages: guild, fights.
- `UI/AzeCaughtPanel.lua` (changed): `createBar(parent, y, careKey)` makes the companion bars clickable (highlight,
  click -> `Panel.ClickCare`, care line in the tooltip); the care icon buttons are removed; `RefreshCareButtons`
  updates the bars (`widgets.careBars`), `careState` as before; `buildCompanionView` calls `BuildFighterBlock`;
  `RefreshCompanion` calls `ArenaView.RefreshFighter`.
- `UI/PetView.lua` (changed): `PetView.BuildTraining` (button at `layout.train`, menu of `ArenaView.CreateStatIcon`s,
  closes on `GLOBAL_MOUSE_DOWN` outside, else a screen-wide catcher), `ToggleTraining`, `CloseTraining`,
  `RefreshTraining`; `Core/View/Model.lua` (changed): `PetViewLayout` returns `train` (6 o'clock, the view grows to fit).
- `UI/Window.lua` (changed): comment of the train icon only.
- `Locales/deDE.lua` (changed), `tests/test_load.lua` (changed).
- Data shape change: none. Message shape change: none. Logic stays in `Core/Minigames/Arena.lua` / `AzeCaught.lua`.

## Tasks
- [x] T1 (M): fighter block in the Companion view, Fighter page removed. Verify: test_load (stat icons exist in the
  companion view, a click trains, SelectPage("fighter") -> guild).
- [x] T2 (M): clickable need bars replace the care icons. Verify: test_load (care via a bar click, cooldown, greyed).
- [x] T3 (S): simulator screenshots of the Companion view and the compact training menu (tools/wow-sim.ps1). Verify: evidence PNGs.
- [ ] T4 (S): in game: train by icon click, feed by bar click, compact menu open/close. Verify: user (dev build).
- [x] T5 (M): compact view training button + menu (R9). Verify: test_load (button, 4 icons, opens, time on the
  training icon, closes), test_pet_view (layout).

## Review Focus (failure modes a happy-path test would miss)
1. RF1: saved `ArenaView.state.page == "fighter"` / `caughtView` from an older version -> Guild page, no error. Pinned by: T1.
2. RF2: companion asleep -> the Energy bar wakes it; the stat icons refuse training ("asleep") with the text. Pinned by: T2/T1.
3. RF3: switching the companion while training -> icons show the new companion's points; the running training
   belongs to the old one (Arena.State().training.npc) and is shown only for it. Pinned by: T1.
4. RF4: the guide arrow still finds Arena > Guild (page buttons). Pinned by: T1 (existing guide test).
5. RF5: the 336 px stage: the block fits above the status line (no overlap at y -322). Pinned by: T3.

## Cross-cutting checklist (answer every line; "n/a: reason" is fine)
- [x] Protocol: unchanged, nothing sent.
- [x] Stored data: unchanged (an old saved page "fighter" falls back to guild).
- [x] Trust model: n/a, only my own data shown.
- [x] Localization: texts through `Text[...]`, deDE for new keys.
- [x] Load order: unchanged (ArenaView loads before AzeCaughtPanel builds; BuildFighterBlock is called at build time).
- [x] Packaging: n/a, no new file.
- [x] Tests: tests/test_load.lua.
- [x] Docs: README, CHANGELOG (Unreleased), doc.md.

## Decisions (user answers and design choices, newest last)
- 2026-11-25: user: move Arena > Fighter into a self-contained element below the pet, in place of the care buttons;
  training shown as points per stat, a click on the icon starts it; level/XP in the pet view; feed and water move onto
  the bars ("threshold lines") and are clicked there.
- 2026-11-25: user chose: full window Companion view only, drop the Fighter page; "10/75" = points/maximum (10/25,
  the maximum stays 25); the whole bar is clickable for all four needs (pet and sleep too); a click trains at once;
  level + W/L + XP bar as a line under the name.
- 2026-11-25: user added: the compact view gets a small training button at the bottom (hover "Training"); a click shows
  the four icons, a click on one trains and shows the timer on it, the others greyed out; a click anywhere else closes.
- 2026-11-25: user: implement fully, testing in the dev build by the user.
- 2026-11-25: the training button sits at 6 o'clock between the Water and Pet gauges; the menu opens below it (above
  when the screen ends). A refusal there goes to the red error line (the compact view has no text).
- 2026-11-25: progress is a shade on the icon, not a cooldown sweep: training counts play time, a sweep would use the
  wall clock.

## Open questions
- none

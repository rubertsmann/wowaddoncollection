# 030 Compact pet view: spec

- Status: verifying
- Created: 2026-11-24
- Target version: GuildGames 0.5.0 (protocol unchanged, schema unchanged)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
A minimal, text-free view of the AZEcaught companion that stands in for the whole GuildGames window. It shows the
round 3D pet, four round care gauges and a hearts icon. One icon switches between this view and the full window.

## Requirements
- R1: The GuildGames window has two modes, **full** (today's window) and **minimal** (the pet view). A switch icon sits
  at the same top-left spot in both modes and swaps between them. Both modes share the same screen position.
- R2: Opening GuildGames (`/gg`, minimap button) opens the start mode set in the options. The default is minimal.
  Switching to full shows the last used tab.
- R3: The minimal view shows the active companion's 3D model on a round dark disc with a ring outline (a model frame
  cannot be masked, so the model is not clipped; it has no background, so it reads as round). It plays the
  same idle, sleep and care emotes as the companion panel. With no companion it shows a dimmed placeholder icon, and
  a click on it opens the full view at AZEcaught.
- R4: Four round care buttons sit around the pet on the lower arc (left, bottom-left, bottom-right, right): feed
  (hunger), water (thirst), pet (affection), sleep (energy). Each button has a round outline whose **clockwise ring**
  fills with the need's value (50% = half the ring). The ring colour follows the zone: ok green, needy yellow,
  critical red.
- R5: Clicking a gauge runs the care action with the same rules as the panel: availability, price, the click
  cooldown, refusals, hearts, emote and burst effect. The sleep gauge shows the wake icon and wakes the pet while it
  sleeps. An unusable action is shown greyed out.
- R6: A round heart icon sits at the top right. It pulses on a heart gain and turns dark red below 0. The count shows
  only in its tooltip.
- R7: No text is drawn on the view. Names, values, prices and refusal reasons appear only in tooltips (hover) or in
  the existing chat or error line.
- R8: The minimal view is draggable, unless "lock position" is on. Its position is saved, and the full view opens
  with its top-left corner at the same spot.
- R9: Options (AZEcaught options page): start mode (minimal or full), opacity 20-100% (full opacity while hovered),
  size 50-200%, lock position, hide in combat (default on).
- R10: With "hide in combat" on, the minimal view fades out when combat starts and comes back when it ends, if it
  was open. A view that is open at logout or reload opens again at login.
- R11: The view updates live: needs decay, sleep starts or ends, a companion switch, care done from the panel. It
  only animates while it is shown.

## Non-goals
- No new game rules, needs, prices or hearts logic: everything goes through `AzeCaught.CareAvailability` and
  `AzeCaught.Care`.
- No minimal view for the other games (coin flip, slots, survivor, arena).
- No new messages and no changes to the synced record.

## Design
- Files touched:
  - `UI/PetView.lua` (new): the minimal frame, round model, gauges, heart, switch icon, drag/lock, opacity/scale,
    combat fade.
  - `Core/View/Model.lua` (changed): pure helpers.
    - `Model.GaugeShare(value)`, `Model.RingArc(share, cells)`, `Model.ArcTexCoord(cell, columns)`: the ring's share and its arc cell.
    - `Model.NeedZoneColor(zone)`.
    - `Model.GaugeLayout(radius, buttonSize)`: offsets for the 4 gauges, the heart and the switch icon.
    - `Model.PetViewSettings(raw)`: clamps the options and applies defaults (opacity 0.2-1, scale 0.5-2,
      start mode `minimal|full`).
  - `UI/AzeCaughtPanel.lua` (changed): the care click, the effects and the model loading become shared functions.
    - `Panel.ShowModel` is exported.
    - `Panel.Care(action, target)` takes the view whose model, heart and status get the effects.
    - The click cooldown is shared, so the panel and the pet view cannot double-click past it.
  - `UI/Window.lua` (changed): the switch icon in the header (top left). `UI.Toggle` opens the start mode. Mode
    swapping keeps the top-left corner. `UI.IsShown` counts either mode.
  - `UI/AzeCaughtOptions.lua` (changed): a "Pet view" section: start mode, opacity and size sliders, lock, hide in
    combat.
  - `Locales/enUS.lua`, `Locales/deDE.lua`: tooltip and option texts.
  - `GuildGames.toc`, `GuildGames-Dev.toc` source (`tools/deploy.ps1`): `UI\PetView.lua` after `UI\AzeCaughtPanel.lua`.
  - `tests/test_pet_view.lua` (new). `tests/test_load.lua`: the new file is loaded.
- The ring: shipped anti-aliased textures (`UI/Textures/Disc`, `Ring`, `RingThin`, `RingArcs`, white, tinted). A dark
  ring track, and on top one cell of `RingArcs` (8 x 8 grid, cell n = n/64 of the ring clockwise from 12 o'clock),
  picked with SetTexCoord (`Model.RingArc`, `Model.ArcTexCoord`). No rotation, clipping or cooldown API needed.
- Data shape change: new keys in `db.ui` only (`petView = { mode, open, left, top, opacity, scale, locked,
  hideInCombat, startMode }`). Missing keys are read as defaults, and bad values are clamped by `Model.PetViewSettings`.
- Message shape change: none.
- Pure logic lives in `Core/View/Model.lua`. WoW calls stay in UI files and `Core/Game/Api.lua`, as today.

## Tasks
- [x] T1 (S): `Model.GaugeShare`, `GaugeColor`, `PetViewLayout`, `PetViewSettings` plus `tests/test_pet_view.lua`.
  Verify: luajit suite.
- [x] T2 (M): `AzeCaughtPanel`: export `ShowModel`; make `Care` and the click cooldown shared with a target view.
  Verify: suite plus the panel still cares in game.
- [x] T3 (L): `UI/PetView.lua`: frame, round masked model, outline, 4 ring gauges, heart, switch icon, tooltips,
  live refresh. Verify: wow-sim screenshot (a fake companion via `-Lua`), then in game.
- [x] T4 (M): `Window.lua`: mode switch, start mode, shared top-left position, `UI.Toggle`/`IsShown`, reopen at
  login. Verify: in game.
- [x] T5 (M): drag/lock, opacity with hover boost, scale, combat fade (`PLAYER_REGEN_DISABLED/ENABLED`).
  Verify: in game.
- [x] T6 (S): options section plus locales (enUS, deDE). Verify: options page screenshot.
- [x] T7 (S): dev command `/ggd caught hearts <n>` (with the existing `/ggd caught add`, `need`, `time`). Verify: dev build.
- [x] T8 (S): docs: README, CHANGELOG, docs/status.md, doc.md, verify.md.

## Review Focus (failure modes a happy-path test would miss)
1. RF1: need values outside 0-100, NaN or nil (old or garbage saved data) -> the ring is clamped to 0..segments with
   no error. Pinned by: T1.
2. RF2: saved options garbage (opacity 5, scale "x", unknown mode) -> clamped defaults. A position off screen ->
   the view is put back on screen. Pinned by: T1, T4.
3. RF3: clicks on the panel and the pet view in the same second -> one care action (shared cooldown), never two
   payments. Pinned by: T2.
4. RF4: combat starts while the view is being dragged, or the window is switched in combat -> no stuck drag and no
   protected-frame error (the view is not secure, but the fade must not fight the drag). Pinned by: T5.
5. RF5: no companion, the companion runs away, or the model fails to load -> the placeholder shows, the gauges are
   empty and disabled, and there is no Lua error. Pinned by: T3, T7.

## Cross-cutting checklist (answer every line; "n/a: reason" is fine)
- [x] Protocol: `addon.PROTOCOL_MINOR` unchanged. The view reads local data only.
- [x] Stored data: `Store.SCHEMA` stays 2. Only new optional `db.ui.petView` keys, read with defaults, so no
  migration.
- [x] Trust model: n/a. No peer data is shown. The companion is my own.
- [x] Localization: no stored strings. Tooltips and options go through `Text` (enUS and deDE).
- [x] Load order: `UI\PetView.lua` after `UI\AzeCaughtPanel.lua` (it uses `Panel.ShowModel` and `Panel.Care`) and
  before `UI\AzeCaughtOptions.lua`.
- [x] Packaging: a new file under `UI/` is picked up by the TOC. No `.pkgmeta` change.
- [x] Tests: `tests/test_pet_view.lua`: clamping, ring rounding at 0/50/100/garbage, layout symmetry, settings
  defaults.
- [x] Docs: README (Pet view section), CHANGELOG, docs/status.md, doc.md.

## Decisions (user answers and design choices, newest last)
- 2026-11-24: an icon switches between the full and minimal views. It sits at the same spot in both modes. The
  default start is minimal, and an option picks the start mode (user).
- 2026-11-24: the minimal view replaces the whole GuildGames window (user).
- 2026-11-24: the centre is the 3D model, round (user).
- 2026-11-24: the gauges sit around the pet (user). They are placed on the lower arc, because the top corners hold the
  switch icon (top left) and the hearts (top right) (claude).
- 2026-11-24: clicking a gauge does the care action (user).
- 2026-11-24: hide in combat (user). This is an option, default on (claude).
- 2026-11-24: drag plus a lock option. The full view opens where the minimal view sits (user).
- 2026-11-24: the gauge is a clockwise ring (user). It is drawn from rotated segments, not a cooldown swipe (claude:
  works on any client).
- 2026-11-24: the hearts are an icon plus tooltip, no number on screen (user).
- 2026-11-24: opacity 20-100% and scale 50-200%, plus start mode, lock and hide in combat. Full opacity while
  hovered (user).
- 2026-11-24: the pet's outline and the gauge rings are rings of small dots, not stacked masked discs: two masked
  discs on one frame drew as one solid disc in wow-ui-sim. Dots need no mask and no rotation (claude).
- 2026-11-24: replaced the dots (user: low-res, chunky edges). Shipped anti-aliased textures UI/Textures/Disc, Ring,
  RingThin (256 px TGA) draw the discs and rings; the gauge share is a standing Cooldown sweep with the ring texture,
  reversed so it fills clockwise from 12 o'clock; full ring near 100%. Without a Cooldown sweep the full ring is shown
  dimmed by the share (claude).
- 2026-11-24: `/gg` and the minimap button open the start mode. `/gg caught` and `/gg arena` always open the full window
  (`UI.ShowFull`), because they name a view (claude).
- 2026-11-24: the standing Cooldown sweep drew nothing for partial values in game (user). Replaced by a texture of 64
  pre-drawn arcs; same look in every client and in the sim (claude).

## Open questions
- None blocking. Assumptions to confirm while building: the placeholder when there is no companion, and that the
  view's close goes through `/gg`, the minimap button or the switch (no extra X, to keep it text-free).

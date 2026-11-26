# Compact pet view

Status: done | Since version: 0.5.0 | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
A small window that shows only the AZEcaught companion and no text. The round pet sits in the middle with four round
care buttons around its lower half: feed, water, pet and sleep. The ring around each button fills clockwise with that
need and turns green, yellow or red by zone. A heart in the top-right corner pulses on a gain and turns dark below 0.
It stands in for the whole GuildGames window: the icon in the top-left corner switches to the full window and back, at
the same screen spot. Every 90-240 s an awake companion plays a random animation its model has.

## How to use
- UI:
  - `/gg` or the minimap button opens the start view (minimal by default). The top-left icon switches views.
  - Click a gauge to care. While the pet sleeps, the sleep gauge wakes it. Hover for the need's value, the price and
    why a button is greyed out.
  - Drag the view anywhere, unless the position is locked.
  - Options > AddOns > GuildGames AZEcaught, section "Minimal view": start view, opacity (20-100%, full while hovered),
    size (50-200%), position lock, hide in combat (on by default), "Show minimal view".
- Commands: `/gg caught` and `/gg arena` always open the full window. Dev build: `/ggd caught hearts <n>`,
  `/ggd caught emote` (an idle emote now), and the existing `/ggd caught add`, `need`, `time`.

## How it works
- Data (SavedVariables): `db.ui.petView = { mode, open, left, top, startMode, opacity, scale, locked, hideInCombat }`.
  Every value is read through `Model.PetViewSettings` (defaults, limits). Schema stays 2, so no migration.
- Messages: no change (protocol 1.2).
- Drawing: shipped white anti-aliased textures in `UI/Textures/`, tinted in game.
  - `Disc` (backgrounds), `RingThin` (the pet's outline), `Ring` (the gauge track).
  - `RingArcs`: an 8 x 8 grid of 64 pre-drawn arcs (cell n = n/64 of the ring, clockwise from 12 o'clock). The
    gauge picks a cell with SetTexCoord (`Model.RingArc`, `Model.ArcTexCoord`). No rotation, clipping or cooldown API.
- Modules:
  - `Core/View/Model.lua`: settings, layout, ring share and arc cell, keep-on-screen, idle emote list, delay and
    shuffle.
  - `UI/PetView.lua`: the view, refresh, tooltips (hidden as soon as the mouse leaves their owner), drag, opacity,
    scale, combat fade, reopening at login.
  - `UI/AzeCaughtPanel.lua`: shared care (`ClickCare`/`Care` with a target view, one click cooldown for both views),
    `EmoteThenIdle`, `MaybeIdleEmote`.
  - `UI/Window.lua`: `UI.SetMode`, `UI.ShowFull`, `UI.Toggle` (opens the start view), the switch icon.
  - `UI/AzeCaughtOptions.lua`: the "Minimal view" options section.

## Localization
Tooltips and options go through `Text` (enUS and deDE). Need labels, prices and refusal texts reuse the panel's
strings. Nothing is stored or sent as display text.

## Limits and known issues
- A 3D model cannot be masked, so the pet stands on a round disc rather than being clipped to a circle.
- The ring moves in 64 steps (about 1.6% each).
- Which idle animations a companion plays depends on its model. Most creatures only roar and attack.
- wow-ui-sim does not draw cooldown sweeps or rotated, clipped textures like the game, so only the arc texture
  approach renders the same in both.

## Changelog line
- New minimal view: only the companion, round care gauges that fill clockwise, a heart icon, no text; random idle emotes.

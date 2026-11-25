# Pet runner game and pet in Survivor

Status: final | Since version: 0.9.0 | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
Companion Dash is a runner game: your companion runs through a scrolling landscape and monsters from your AZEcaught
collection come at it. Jump over the ones on the ground and duck under the flying ones; the speed keeps rising and
one hit ends the run. Each full 100 m pays 1g into the money pool (at most 50g a day), and the guild board shows the
best distances. In Survivor your companion now stands in the tower's place and attacks whenever a weapon fires.

## How to use
- UI: `/gg`, the last button of the game switch (running icon). Start, or click into the play area. Top half = jump
  (hold for higher), hold the bottom half = duck; Space / Up / W jump, Down / S duck while a run is open.
- Needs an active companion (AZEcaught).
- Commands: `/gg caught model` (dev check of the model's animations and camera).

## How it works
- Data (SavedVariables): `runner = { day, paid, b, n, weeks, recent }` (local; sanitized at load; schema stays 2).
- Messages: record section `runner = { b, n, weeks, recent }`, protocol 1.4 additive (docs/protocol.md).
- Modules: `Core/Minigames/Runner.lua` (pure: physics at 1/120 s, spawning, collision, payout, section, board rows),
  `UI/RunnerView.lua` (play area, parallax, input, models), `UI/CompanionModel.lua` (model load/animation helper),
  `UI/SurvivorArena.lua` (the companion in the tower's place), `UI/GamesTab.lua` (switch, board).

## Localization
All UI text through `Text[...]` with deDE translations. NPC names come from the client (escaped). Only numbers are sent.

## Limits and known issues
- Flying is known from the creature type (dragonkin) or the beast family (enUS/deDE names); entries without it never
  count as flyers. With no known flyer, random monsters fly.
- The top view in Survivor depends on the client's model camera calls; without them the companion is seen from the
  front and only turns.
- Models are not drawn by the simulator; the look needs the game.

## Changelog line
- Companion Dash runner game (1g per 100 m, 50g/day, guild board, protocol 1.4); the companion fights in Survivor.

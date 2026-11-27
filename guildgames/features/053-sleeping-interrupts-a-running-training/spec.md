# 053 Sleeping interrupts a running training: spec

- Status: verifying
- Created: 2026-11-28
- Target version: 0.15.0
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
A companion cannot train while asleep, so putting it to sleep stops its running training, the same way switching the
active companion does.

## Requirements
- R1: Sleep (care action) on the active companion while its training is still running cancels the training; gold and
  energy spent on it are not refunded.
- R2: A training whose time is already up is not cancelled (the next tick finishes it and grants the point).
- R3: Sleep without a running training behaves as before.
- R4: The player is told: chat line "The running training was cancelled." after the sleep, and the Sleep tooltip warns
  while a training runs.

## Non-goals
- No pause/resume of training, no refund, no confirmation dialog (switching the companion has none either).

## Design
- `Core/Minigames/AzeCaught.lua` `AzeCaught.Care`: on "sleep", `Arena.CancelTraining()` when the training belongs to the
  active companion and `Arena.TrainingLeft() > 0`; `CareResult.trainingCancelled`.
- `UI/AzeCaughtPanel.lua`: chat line on `trainingCancelled`; tooltip warning in `Panel.AddCareTooltip`.
- `Locales/deDE.lua`: one string. Data/message shape: none.

## Tasks
- [x] T1 (S): cancel in `AzeCaught.Care` + result flag. Verify: test_arena "sleeping stops a running training".
- [x] T2 (S): chat line + tooltip warning + deDE. Verify: in game.

## Review Focus
1. RF1: training time already up when sleeping -> kept, finished by the tick. Pinned by: T1 test
2. RF2: sleep refused (energy full, read-only) -> nothing cancelled (the cancel runs after the availability check). Pinned by: code order (READ-ONLY)

## Cross-cutting checklist
- [x] Protocol: unchanged. - [x] Stored data: unchanged (state.training cleared as on a switch).
- [x] Trust model: n/a (local action). - [x] Localization: deDE added. - [x] Load order: unchanged.
- [x] Packaging: unchanged. - [x] Tests: test_arena. - [x] Docs: CHANGELOG.

## Decisions
- 2026-11-28: Cancel (not pause), no refund, no confirmation: same rule as switching the companion; the tooltip warns first.

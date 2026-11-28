# B004 Companion model switches between male and female

- Status: verifying
- Severity: S3
- Reported: 2026-11-28
- Found in: 0.15.1 (dev build)
- Fixed in: 0.16.0
- Links: [log](log.md), [probe results](evidence/gender-probe.md)

## Report
- Who saw it: the user
- Build / version: dev (0.15.1 + working copy)
- Where: AZEcaught companion models (pet view, companion panel, arena)
- What happened (their words): "why is the companion sometimes rendered as the female or male version?"
- Expected: a companion always shows the creature that was caught
- How often: sometimes (NPC ids that have a male and a female look)

## Reproduction
- Steps: catch an NPC that comes in both genders (e.g. NPC 1564); open and close the companion views a few times
- Offline repro: `roster: each catch keeps the look of the creature it was made of, not the NPC's first-seen look`

## Hypotheses (not shown yet)
- none open

## Root cause
- `Core/Game/Catcher.lua` CaptureDisplay: `PlayerModel:GetDisplayInfo()` after `SetUnit` is 0 on this client
  (evidence/gender-probe.md), so every collection entry and companion is stored with `disp = 0`.
- `UI/CompanionModel.lua` Load / `UI/AzeCaughtPanel.lua` showModel: with `disp = 0` the model is loaded by
  `SetCreature(npc)`, and the client picks one of the NPC's looks per load (NPC 1564 loaded 4462 and 4461).
- Even with a display, a companion copied the collection's first-seen look (`AzeCaught.lua` freshCompanion), and the
  load sanitizer overwrote the companion's look with the collection's on every login (`sanitizeCompanion`).

## Fix
- Change:
  - `Core/Game/Catcher.lua`: `CaptureDisplay` falls back to loading the NPC id up to `DISPLAY_TRIES` (6) times and takes
    the look whose model file is the unit's (`CreatureDisplay`, matching in `AzeCaught.PickDisplay`). Throw and trap
    always capture the target's look (before: only while the NPC had none).
  - `Core/Minigames/AzeCaught.lua`: the throw keeps the look; `recordCatch` gives it to the new companion; the load
    sanitizer keeps the companion's own look (falls back to the NPC's); `SetDisplay`, `WithoutDisplay`.
  - Migration (no schema change): `Catcher.FillDisplays` (every 10 s in the tick, once per companion and session) gives a
    companion with `disp = 0` the first look its NPC loads, so it stops changing. It cannot know the gender seen before;
    `/ggd caught look [id]` switches a companion to the NPC's next look (or a given display id).
  - `Core/Minigames/Arena.lua`: the arena fighter carries the companion's own look.
  - Dev: `/ggd caught gender [unit]` (probe), `/ggd caught look [id]`; temporary DEBUG journal lines `model.load`,
    `found.display` (npc, file, matched, tries), `companion.display(.fill)`, and `display` on the `catch` line.
- Regression test: `roster: each catch keeps the look ...` FAIL before ("expected 4461, got 4462"), passes after; plus
  `roster: the look whose model matches ...` and `roster: a companion without a look gets one once ...`
- Protocol / schema: unchanged. `disp` already exists on the companion and in the companion / fighter messages (0 =
  unknown); now it is filled. Old peers show the stored look too (they load by display id when it is > 0).
- CHANGELOG: "Fixed: a companion no longer switches between its male and female look ..."

## Verification
| Check | How | Level | Evidence | Result | Date |
|---|---|---|---|---|---|
| regression test | `luajit tests/run.lua` | OFFLINE | `240 passed, 0 failed` | pass | 2026-11-28 |
| old companion keeps one look | `/reload`, open/close the pet view | IN-GAME | log 13:14: 6x `companion.display.fill`; user: "stays the same" | pass | 2026-11-28 |
| new catch keeps the caught gender | `/ggd caught add` on a female and a male of NPC 1564 | IN-GAME | log 13:27: stored u8 4462, u9 4461; caught view still showed both female (log 13:33, fixed) | re-check | 2026-11-28 |
| SetDisplayInfo draws on this client | journal `model.load` | IN-GAME | `method=display ... file=1000764 ok=true` | pass | 2026-11-28 |

## Open questions
- answered: SetDisplayInfo draws (model.load method=display with a model file, log 13:14)
- answered: reloading the same frame picks again (tries=2 and 3 before a match, log 13:27)


## Accepted gaps
- Companions caught before the fix get a look picked by the client, not necessarily the gender seen at the catch
  (nothing stored tells it); `/ggd caught look` fixes one by hand.

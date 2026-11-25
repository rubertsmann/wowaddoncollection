# 036 Item batch: catch charms, care items, arena buffs, minigame items

Status: verifying (draft until the in-game checks in [verify](verify.md) are done).

## What it does for the player
The shop gains 13 items in four new groups (prices are first values, to be tuned):

| Group | Item | Effect | Price | Where it is used |
|---|---|---|---|---|
| Charms | Lucky Charm | catch rewards +10% | 300g | Inventory: Equip (one slot) |
| Charms | Steady Hand | the best moment starts at 13% health instead of 10% | 300g | Inventory: Equip |
| Charms | Second Chance | when the rope slips off (the enemy died too late), one more throw at the same enemy | 300g | Inventory: Equip |
| Charms | Rare Lure | elite and rare catches pay +25% | 300g | Inventory: Equip |
| Care | Feast | hunger and thirst to full | 1g | Inventory: Use |
| Care | Squeaky Toy | affection to full | 50s | Inventory: Use |
| Care | Care Elixir | hunger, thirst and affection don't drop for 4 h | 5g | Inventory: Use |
| Arena | War Paint | attack +10%, next 3 fights | 250g | Inventory: Use |
| Arena | Bark Skin | vitality (health) +10%, next 3 fights | 250g | Inventory: Use |
| Arena | Swift Tonic | speed +25%, next fight | 100g | Inventory: Use |
| Games | Dash Shield | the next Companion Dash run survives one hit | 10g | Companion Dash: the button left of Start |
| Games | Head Start | the next run starts at 200 m (no gold for those 200 m) | 5g | Companion Dash: the button right of Start |
| Games | Survivor Bomb | clears every monster on the screen, once per run, stake at most 250g | 100g | Survivor: the button bottom left during a run |

- A charm is bought once and stays owned. Equipping, swapping and taking it off are free, and only the equipped charm works.
- Runs that used a game item carry a bag icon on the leaderboards and in the feeds.
- Arena buffs show as icons next to the fighter, for both sides.

## How it works
- Logic lives in `Core/Minigames/Items.lua`:
  - The catalog, the groups and the kinds `charm`, `care`, `arenaBuff`, `runner` and `survivor`.
  - `Items.Equip`, `Equipped` and `CharmValue`.
  - `Items.ArenaBuffs`, `RunningArenaBuffs` and `SpendArenaBuffs`.
  - The Elixir is a `booster` with `boost = "care"`.
- Charms in AzeCaught:
  - `AzeCaught.BestHealth()` moves the best moment.
  - `AzeCaught.CharmRewardFactor(cls)` scales the reward of a catch, traps included.
  - `EndLateThrows` lets a slipped first rope count as not rolled (`again`), so one more throw is allowed; `Catcher.OnSecondChance` says so in chat.
- Care: `AzeCaught.CareItem(needs, now)`. The need decay skips hunger, thirst and affection while a care boost runs.
- Arena:
  - `Arena.Fighter` multiplies the stats by the running buffs and lists their ids in `bf`.
  - Challenge, Answer and Counter spend one fight per buff when the fighter is stored.
  - `Arena.SanitizeBuffs` cleans peer ids.
- Runner: `Runner.New(pool, seed, { shield, start })`.
  - A shield hit emits `shield`, removes the monster and gives 1 s of grace.
  - Head Start puts the run at the time and speed of 200 m, and `Finish` pays only beyond `startMeters`.
  - Marks: `bi` (the best run used an item) and recent `it`.
- Survivor: `Survivor.Bomb(run)` kills every living enemy (kills and XP count). `Settle` records the play with `it`.
- Saved data:
  - New: `db.caught.equipped` (charm id) and `db.caught.arenaBuffs` (id -> 1..3).
  - Existing: items and boosts.
  - All of it is sanitized in `Items.SanitizePersisted`; schema stays 2.
- Wire: protocol 1.5, additive (`bf`, `bi`, `it`). See `docs/protocol.md`, "Item marks".

## Limits and known issues
- The weekly runner board has no item mark; only the all-time best (`bi`) and the feed entries (`it`) carry one.
- A charge of an arena buff is used when the fighter is sent, even if the challenge is later withdrawn or declined.
- Running arena buffs whose items are all used do not show in the inventory. They show on the fighter line in the Arena tab.
- Prices are first values; tuning comes later (user, 2026-11-25).
- Swift Tonic is +25% speed, not a fixed first strike, so the fight stays the same on older clients.

## Localization
Every new text is in `Locales/deDE.lua` (the "-- shop and items" block). Only item ids are stored and sent.

## Verification
See [verify.md](verify.md): every rule is covered offline (180 passed, 0 failed), and the UI ran in the simulator. The in-game and two-client checks are still open.

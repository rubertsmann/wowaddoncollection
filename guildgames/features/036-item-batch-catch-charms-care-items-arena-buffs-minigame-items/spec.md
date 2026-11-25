# 036 Item batch: catch charms, care items, arena buffs, minigame items: spec

- Status: verifying
- Created: 2026-11-25
- Target version: 0.10.0
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
Add 13 new shop items in four new groups (charms, care, arena, games). A charm is equipped in one slot and stays on.
Care items look after the companion. Arena buffs are shown on the published fighter. A minigame run that used an item is
marked on the boards.

## Item list (proposal, prices in gold)
| Group | Id | Name (EN) | Kind | Effect | Price |
|---|---|---|---|---|---|
| charms | `charmLuck` | Lucky Charm | charm | catch rewards +10% | 300 |
| charms | `charmSteady` | Steady Hand | charm | the best moment starts at 13% health instead of 10% | 300 |
| charms | `charmSecond` | Second Chance | charm | when the rope slips off (the enemy died too late), one more throw at the same enemy | 300 |
| charms | `charmLure` | Rare Lure | charm | elite and rare catches pay +25% | 300 |
| care | `feast` | Feast | care | hunger and thirst to 100 | 1 |
| care | `toy` | Squeaky Toy | care | affection to 100 | 0.5 |
| care | `elixir` | Care Elixir | booster (`care`) | hunger, thirst and affection don't drop for 4 h | 5 |
| arena | `warPaint` | War Paint | arenaBuff | attack +10% for the next 3 fights | 250 |
| arena | `barkSkin` | Bark Skin | arenaBuff | vitality (health) +10% for the next 3 fights | 250 |
| arena | `swiftTonic` | Swift Tonic | arenaBuff | speed +25% for the next fight (nearly always acts first) | 100 |
| games | `dashShield` | Dash Shield | runner | the next Companion Dash run survives one hit | 10 |
| games | `headStart` | Head Start | runner | the next run starts at 200 m (no gold for those 200 m) | 5 |
| games | `bomb` | Survivor Bomb | survivor | one use in a run: clears every monster on the screen | 100 |

Prices against the economy (skill table):
- A charm pays back only after about 1500 catches at +10% of a 2g reward.
- A Feast costs more than food plus water (75s).
- The Elixir saves about 2g of food and water over 4 h.
- An arena buff costs about as much as its edge is worth at the 1000g wager cap.
- The Dash items stay under the 50g daily cap.
- The bomb is the only item whose gain grows with the stake: see the open questions.

## Requirements
- R1: The shop and inventory show the groups Catch items, Charms, Care, Arena and Games, in that order. Every new item can be bought with the existing checks (funds, stack, readonly).
- R2: Charms:
  - The inventory has a "Charms" subsection with one equip slot. Equipping or swapping is free.
  - A charm is bought at most once (stack 1).
  - The equipped charm's effect works on every catch (reward, best moment, second throw, elite/rare bonus).
  - An unequipped charm does nothing.
- R3: Care items:
  - Feast and Toy fill their needs at once. Using one with nothing to fill, or without a companion, is refused and the item is kept.
  - The Elixir stops hunger, thirst and affection from dropping for 4 h. Energy and sleep are not affected.
- R4: Arena buffs:
  - Using a buff gives it charges: 3 fights, or 1 for Swift Tonic. The three buffs can run together.
  - A charge is used when a fighter snapshot is published: a challenge, an accepted answer or a counter offer.
  - The buffed stats are part of the snapshot. Every client computes the same fight, old ones included.
  - The snapshot lists the buff ids (`bf`), and the arena UI shows them on both sides.
- R5: Minigame items:
  - Dash Shield and Head Start are chosen before a run and used up when the run starts.
  - The Survivor Bomb is a button during a Survivor run, once per run.
  - A run that used an item is marked (`it`) in the runner section and the survivor play entry, and boards and feeds show an icon there.
- R6: Saved data:
  - New stored data: `db.caught.equipped` and `db.caught.arenaBuffs`. It is sanitized at load, and a bad value drops alone.
  - Ids follow the catalog rules (never reused).

## Non-goals
- No trading, selling back or gifting items.
- No more than one charm slot.
- No cosmetic items.
- No changes to the fight formula (`Arena.Fight`).

## Design
- `Core/Minigames/Items.lua` (changed):
  - CATALOG entries and the GROUPS `charms`, `care`, `arena`, `games`.
  - New kinds `charm`, `care`, `arenaBuff`, `runner`, `survivor`, with EFFECTS handlers.
  - New functions: `Items.Equip(id)`, `Items.Equipped()`, `Items.CharmEffect(name)`, `Items.ArenaBuffs()`, `Items.ConsumeArenaBuffs()`, `Items.SanitizePersisted` for the new tables.
  - Boost `care` comes through `Items.ActiveBoost("care")`.
- `Core/Minigames/AzeCaught.lua` (changed):
  - `Reward` gets a charm factor.
  - `Chance` uses the `charmSteady` best health.
  - `EndLateThrows` allows one more throw after a slipped rope (`charmSecond`).
  - The need decay skips hunger, thirst and affection while the care boost runs.
  - New `Feed(full)` / `Pet(full)` helpers for the care effects.
- `Core/Minigames/Arena.lua` (changed):
  - `Arena.Fighter(companion, buffs)` multiplies atk, vit and spd and sets `bf`.
  - `SanitizeFighter` allow-lists `bf` (at most 3 known ids).
  - Challenge, Answer and Counter consume the charges.
- `Core/Minigames/Runner.lua` (changed):
  - `New(pool, seed, options)` with `shield` and `start`.
  - Step absorbs one hit with 1 s of grace.
  - The section's best and recent entries carry `it`.
- `Core/Minigames/Survivor.lua` (changed): `Survivor.Bomb(run)` clears the enemies, and the play entry carries `it`.
- UI (changed):
  - `UI/ShopView.lua` and the inventory: groups, a charm slot with Equip/Unequip.
  - `UI/RunnerView.lua`: item toggles before the run.
  - `UI/SurvivorArena.lua`: a bomb button.
  - The arena view shows the buff icons.
  - `UI/GamesTab.lua`: the item icon on marked board and feed rows.
- `Core/Data/Games.lua`: the play entries and the runner section sanitize the optional `it`.
- Data shape change: `db.caught.equipped` = item id or nil, `db.caught.arenaBuffs` = { id -> charges 1..3 }. Schema stays 2, sanitized at load.
- Message shape change: protocol 1.5. Fighter `f.bf` (list of up to 3 buff ids), runner entries and survivor plays `it = 1`. All of it is additive; older peers drop it with their allow-list copy.
- Pure logic lives in Items, AzeCaught, Arena, Runner and Survivor. No new WoW calls.

## Tasks
- [x] T1 (M): catalog, groups, charm kind, Equip/Equipped, sanitize. Verify: test_item_batch "charms".
- [x] T2 (M): charm effects in AzeCaught (reward, steady, second throw, lure). Verify: test_item_batch "charm effects".
- [x] T3 (M): care kind + Elixir boost in the need decay. Verify: test_item_batch "care items".
- [x] T4 (M): arena buffs: Fighter multipliers, `bf`, charges consumed, SanitizeFighter. Verify: test_item_batch "buffs".
- [x] T5 (M): runner items (shield, head start, `it`). Verify: test_item_batch "items".
- [x] T6 (S): survivor bomb + `it` on the play entry. Verify: test_item_batch "bomb".
- [x] T7 (L): UI: shop/inventory groups, charm slot, runner toggles, bomb button, arena buff icons, board markers. Verify: simulator shots + in game.
- [x] T8 (S): protocol 1.5 (Init, run.lua, test_load, docs/protocol.md). Verify: suite.
- [x] T9 (S): locales deDE, README, CHANGELOG, doc.md. Verify: locale test.

## Review Focus (failure modes a happy-path test would miss)
1. RF1: A peer sends `bf` with unknown or too many ids, or stats far above the buff. The snapshot is cleaned, and the stats keep the existing caps. Pinned by: T4.
2. RF2: A challenge is withdrawn or declined. The charge stays used, as documented, and is never used twice for one snapshot. Pinned by: T4.
3. RF3: The equipped charm id is retired or not owned in SavedVariables. Then no charm is equipped. Pinned by: T1.
4. RF4: The Elixir boost and the clock going back. Then the decay resumes and never goes negative. Pinned by: T3.
5. RF5: A 1.4 peer computes a fight against a buffed fighter and gets the same result as a 1.5 client. Pinned by: T4.

## Cross-cutting checklist (answer every line; "n/a: reason" is fine)
- [x] Protocol: additive MINOR 4 -> 5 (`bf`, `it`). The fight result stays the same everywhere because the buffs are baked into the stats.
- [x] Stored data: schema stays 2. New tables sanitized in `Items.SanitizePersisted`.
- [x] Trust model: the stats were already self-reported. `bf` is an allow-list of ids, and `it` is a boolean flag.
- [x] Localization: only ids are stored and sent. Names and effects go through `Text[...]` with deDE.
- [x] Load order: no new files.
- [x] Packaging: unchanged.
- [x] Tests: new tests/test_item_batch.lua (9 tests, adversarial: RF1-RF5) plus the kind checks in the test_items catalog guard.
- [x] Docs: README item list, CHANGELOG, docs/protocol.md, doc.md.

## Decisions (user answers and design choices, newest last)
- 2026-11-25: The new items cover all four areas: catch, care, arena and minigames.
- 2026-11-25: Catch items:
  - The effects are Lucky Charm, Second Chance, Steady Hand and Rare Lure.
  - They are equippable items in their own inventory subsection.
- 2026-11-25: Equipping uses one slot, permanently. The effects are small (+10% range). Your answer was "small, stacking", but with one slot nothing can stack, so the effects simply do not add up.
- 2026-11-25: Care items: Feast, Toy and Care Elixir.
- 2026-11-25: Minigame items: Dash Shield, Head Start and Survivor Bomb. Runs that used an item are marked on the boards.
- 2026-11-25: Arena buffs: War Paint, Bark Skin and Swift Tonic, shown on the record, so the protocol goes up.
- 2026-11-25: Everything ships as one feature.
- 2026-11-25: The user accepted the plan; prices will be tuned later. The bomb only works up to a 250g stake.
- 2026-11-25: Second Chance changed after the user's test ("second chance doesnt work the icon disappears"): it now allows one more throw at the same enemy after the rope slipped off (the enemy died too late), instead of a 10% re-roll of a failed catch.
- 2026-11-25 (design): The weekly runner board carries no item mark; only the all-time best (`bi`) and the feed entries (`it`) do.
- 2026-11-25 (design): Swift Tonic is +25% speed, not "always strikes first". A fixed first strike would change `Arena.Fight`, and 1.4 peers would compute a different winner. Speed in the snapshot keeps every client in agreement.

## Open questions
- (answered 2026-11-25) The bomb works only in runs with a stake of at most 250g, price 100g.
- (answered 2026-11-25) The prices are fine for now; tuning comes later.

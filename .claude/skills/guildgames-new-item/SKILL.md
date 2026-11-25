---
name: guildgames-new-item
description: Use when adding, changing, pricing or removing a GuildGames shop item (catch item, trap, booster, a future arena buff), or when adding a new item kind or item group to the GuildGames shop and inventory.
---

# Adding a GuildGames item

Every item is ONE entry in `guildgames/Core/Minigames/Items.lua` `Items.CATALOG`. The Shop tab, the Inventory tab and
the catch items at the target read the catalog; nothing else lists items. `tests/test_items.lua` "the catalog guard"
checks every entry, so a finished item is one whose tests pass.

## 1. Ask (one message, each with the default in brackets)
- English name and German name (Locales/deDE.lua).
- Group: an existing `Items.GROUPS` id [`catch`] or a new group (name EN + DE).
- Kind: `booster` (timed, global) | `trap` (instant on the target) | a new kind (say what it does and on what).
- Price in gold (see the economy table below).
- Kind fields: booster `duration` seconds and `boost` (what it boosts); trap `tier` (`normal` | `elite` | `rare`).
- Icon: an `Interface\Icons\...` path that exists in WoW Forever (ask the user to check in game when unsure).
- One-line effect text (EN + DE); `{seconds}` is replaced by the duration.

## 2. Change, in this order
1. `Items.CATALOG`: the entry. `id` is camelCase letters/digits, new, not in `Items.RETIRED`. Write `name` and `effect`
   as `Text["..."]` (the locale test finds keys only in that form).
2. Only for a new kind: `Items.EFFECTS[kind] = function(item, context) ... return true, result end` (or `nil, reason`;
   the item is only removed on success), the guard's kind checks in `tests/test_items.lua`, the refusal texts, and how
   the item is used in `guildgames/UI/CatchItems.lua` (the row at the target) and `guildgames/UI/ShopView.lua` (Use).
   A boost that something reads: add the read where it applies (example: `Items.CatchBoosted(now)` in
   `AzeCaught.OnDeath`; an arena buff would be read in `Core/Minigames/Arena.lua`).
3. Only for a new group: an `Items.GROUPS` entry (shown in that order).
4. `guildgames/Locales/deDE.lua`: every new `Text["..."]` key (the "-- shop and items" block).
5. `guildgames/tests/test_items.lua`: one test that uses the item (buy, use, its effect, one refusal).
6. `guildgames/README.md` item list and `guildgames/CHANGELOG.md` `## Unreleased`: one line.
7. Run `luajit tests/run.lua` in `guildgames/` (LuaJIT: `%LOCALAPPDATA%\Programs\LuaJIT\bin`). Done = `N passed, 0 failed`.

A plain new entry of an existing kind is a CHANGELOG line. A new kind, a new group or an effect on arena fights is a
feature: use the `feature-workflow` skill (spec, log, verify) around these steps.

## Rules
- Ids are stored in SavedVariables (`db.caught.items`, `db.caught.boosts`). Never rename or reuse an id. Removing an
  item: delete the entry, add its id to `Items.RETIRED`; `Items.SanitizePersisted` drops the stored counts.
- Items are local: nothing about them is sent to the guild. An item that changes what the guild sees (a published
  companion, an arena fight) needs a protocol decision in the feature spec first.
- Prices are copper: `50 * 10000` = 50g.

## Economy (check the price against what an item can earn)
| Source | Amount |
|---|---|
| Catch reward | 2g at the best moment, up to 50g for a risky catch (`AzeCaught.CATCH_REWARD`, `MAXIMUM_REWARD`) |
| Weekly payout | 500g / 300g / 150g for places 1-3, 25g for everyone else |
| Start grant | 20g |
| Food / water | 50s / 25s per use |
| Delicious Meat | 50g: 20 s of sure catches (normal rewards still paid) |
| Magic Trap / Elite / Rare | 500g / 1000g / 1500g: one catch without a fight (reward of a best-moment catch) |

An item must not earn more on average than it costs (example: a booster that doubles rewards for 60 s costs more than
the rewards a fast player catches in 60 s).

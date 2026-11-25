# 034 Shop and inventory: catch items (Delicious Meat, Magic Traps): spec

- Status: verifying
- Created: 2026-11-25
- Target version: GuildGames 0.8.0 (protocol 1.3 unchanged, schema 2 unchanged)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
Players buy items with their AZEcaught gold in a Shop tab, keep them in an Inventory tab, and use catch items right at
the rope icon: Delicious Meat makes every catch roll succeed for 20 s, a Magic Trap catches an enemy without a fight.

## Requirements
- R1: The AZEcaught panel has five tabs (icons, the name on hover): Companion, Collection, Arena, Shop, Inventory. A saved view outside these
  opens Companion.
- R2: Shop lists every item from the item catalog (icon, name, price, short effect, owned count) with a Buy button;
  buying spends from the wallet (ledger kind "shop") and adds one to the inventory. Refusals: not enough gold, stack
  full (99), read-only database. Each refusal shows as a text in the view's status line.
- R3: Inventory lists owned items (icon, name, count, effect) grouped by item group ("Catch" now); usable items have a
  Use button; empty inventory shows a hint to the Shop.
- R4: Item catalog (data only, one entry per item, group + kind + price + effect fields) so new items are one table
  entry plus an effect handler. Kinds: `booster` (timed, global) and `trap` (instant on a unit). Planned later:
  temporary attack/defense boosters (group "arena"), not built now.
- R5: Delicious Meat (group catch, booster, 50g): using it starts a global 20 s boost; while it runs, every catch roll
  succeeds. Using it again while active restarts the 20 s (no stacking beyond 20 s). The roll still pays the normal risk
  reward of the real chance. The boost survives a /reload (stored end time).
- R6: Magic Traps (group catch, trap), three tiers: Magic Trap (normal, 500g), Elite Magic Trap (elite and below,
  1000g), Rare Magic Trap (rare, rareelite and below, 1500g). World bosses can never be trapped. Using a trap on a unit
  catches it at once, at any health, without a kill; the trap is removed from the inventory. Same limits as the rope:
  hostile NPC, not tagged by others, in range, not in dungeons, not already rolled. A refusal keeps the trap. It pays
  the reward of a catch at the best moment (`Reward(Chance(BEST_HEALTH, class))`). The trapped NPC counts as rolled
  (no rope throw afterwards).
- R7: Catch-items label: when the player owns at least one catch item, a small round bag button sits next to the
  current target's catch icon (on full-health enemies too, since traps need no fight). A click opens a row of the
  owned catch items (icon + count). The behaviour is the same as the compact pet view's training menu: a click on an
  item uses it, a click anywhere else or on the bag again closes the row. Traps that cannot catch this unit (tier too
  low) are greyed out with the reason in the tooltip.
- R8: Boost timer: while Delicious Meat is active, a small icon with the seconds left shows next to the catch icons
  (and on the bag button); it disappears when the boost ends.
- R9: Non-immersive option (icon options, default off): "Show at the target frame". When on, the rope icon, bag and
  boost timer are drawn only for the current target, next to the target frame, and no nameplate icons are shown.
- R10: New texts localized (deDE); item names and effects come from the catalog through `Text[...]`.
- R11: A project skill `guildgames-new-item` lets anyone (agent or user) add an item to the catalog in one guided pass:
  it asks the item questions, makes every needed change, and the offline suite proves the item is complete.

## Non-goals
- No attack/defense boosters yet (only the catalog shape for them).
- No selling, trading or gifting items; nothing about items is sent to the guild.
- No change to the normal rope/kill catch rules outside an active meat boost.

## Design
- `Core/Minigames/Items.lua` (new, pure): `Items.CATALOG` (ordered list: id, group, kind, price, icon, name/effect
  text keys, `duration` for boosters, `tier` for traps), `Items.Get(id)`, `Items.Inventory()` (db.caught.items:
  id -> count), `Items.Count(id)`, `Items.Buy(id, myName, now)`, `Items.Use(id, context)` dispatching to
  `Items.EFFECTS[kind]`, `Items.Boosts()` (db.caught.boosts: id -> end server time), `Items.BoostLeft(id, now)`,
  `Items.TrapAllows(id, classification)`, `Items.SanitizePersisted(caught)`.
- `Core/Minigames/AzeCaught.lua` (changed): `OnDeath` treats an active catch boost like `forced` (journal
  `boost=meat`); new `AzeCaught.TrapCatch(target, trapID, clockSeconds, now)` sharing the throw refusals and the catch
  bookkeeping (counts, reward, auto companion) with `OnDeath` through one local `recordCatch`.
- `Core/Data/Wallet.lua` (changed): ledger kind "shop" documented; nothing else.
- `Core/Game/Catcher.lua` (changed): bag button + item row + boost timer per shown icon; target-frame anchoring mode
  (`settings.atTarget`); `Catcher.UseTrap(unit, trapID)` (client checks, then `AzeCaught.TrapCatch`, rope effect).
  The open/close logic of the row is shared with the pet view: `addon.UIHelpers.CloseOnClickAway` (moved out of
  `UI/PetView.lua`: GLOBAL_MOUSE_DOWN outside closes, catcher-frame fallback).
- `UI/ShopView.lua` (new): Shop and Inventory views (scroll lists, Buy/Use buttons, status line).
- `UI/CatchItems.lua` (new): the bag, the item row and the boost clock at the target (see the decisions).
- `UI/AzeCaughtPanel.lua` (changed): five view buttons (58 px), `SelectView("shop"|"inventory")`, refresh on
  `ITEMS_CHANGED`.
- `UI/AzeCaughtOptions.lua` (changed): checkbox "Show at the target frame"; `ICON_DEFAULTS.atTarget = false`.
- `Core/Game/Api.lua` (changed): `Api.TargetFrameAnchor()` (TargetFrame or nil).
- `GuildGames.toc` / Dev TOC: `Core/Minigames/Items.lua` after `AzeCaught.lua`, `UI/ShopView.lua` and
  `UI/CatchItems.lua` before `UI/AzeCaughtPanel.lua`.
- `Locales/deDE.lua`, `tests/test_items.lua` (new), `tests/test_load.lua`.
- Data shape change: db.caught.items `{ [id]=count }`, db.caught.boosts `{ [id]=endTime }`, ledger kind "shop";
  additive, sanitized on load; unknown ids dropped. Message shape change: none.

## Tasks
- [x] T1 (M): `Items.lua` catalog, inventory, buy, boosts, sanitize. Verify: tests/test_items.lua (buy, funds, stack
  cap, unknown id, readonly, boost left/restart, sanitize garbage).
- [x] T2 (M): meat boost in `OnDeath`, `TrapCatch` with tiers and shared catch bookkeeping. Verify: test_items (roll
  0.99 caught while boosted, not after 20 s; trap tiers; world boss refused; refusal keeps the trap; reward paid).
- [x] T3 (M): Shop and Inventory tabs (`UI/ShopView.lua`, five view buttons). Verify: test_load (views exist, buy
  click, use click, status text).
- [x] T4 (L): bag button + item row + boost timer at the catch icon, shared popup row helper. Verify: test_load (bag
  shown only with items, row opens/closes, trap greyed by tier, timer text).
- [x] T5 (M): target-frame mode + option checkbox. Verify: test_load (atTarget: no nameplate icons, icon at target).
- [x] T6 (S): simulator screenshots of Shop, Inventory and the bag row (tools/wow-sim.ps1). Verify: evidence PNGs.
- [ ] T7 (S): in game: buy, meat boost catch, trap catch, target-frame mode. Verify: user (dev build).
- [ ] T8 (M): catalog guard test + `guildgames-new-item` skill (written; the RED/GREEN subagent runs are open), built after T1-T4 so it describes the real code.
  Verify: guard test fails on a broken entry; RED/GREEN subagent runs (see "Item skill" below).

## Item skill (T8)
- Where: `.claude/skills/guildgames-new-item/SKILL.md` at the monorepo root, next to `feature-workflow` and `release`.
  No script: an item is one catalog entry, and the mechanical checks go into a test instead.
- Description (trigger only): "Use when adding, changing, pricing or removing a GuildGames shop item (catch item,
  trap, booster, future arena buff), or adding a new item kind or group."
- Contents, as a recipe:
  1. Questions to ask (each with a default): id, English + German name, group (existing or new), kind (existing or
     new), price, kind fields (`duration` for boosters, `tier` for traps), icon path, one-line effect text, and whether
     item catches/fights pay rewards.
  2. Files to change, in order: the `Items.CATALOG` entry; `Items.EFFECTS[kind]` only for a new kind (plus its use
     context, e.g. a unit for traps, the fighter for arena buffs); the `Locales/deDE.lua` keys; one test case in
     `tests/test_items.lua`; README item list; CHANGELOG `## Unreleased`.
  3. Rules: ids are stored in SavedVariables, so they never change and are never reused (a removed item is dropped by
     sanitize, and its id stays retired in a list in the catalog); prices are checked against the reward table
     (catch reward 2g-50g, weekly payouts) that is part of the skill; nothing about items is sent to the guild.
  4. Done means `luajit tests/run.lua` passes, including the catalog guard.
  5. Larger items (a new kind or group, an effect on arena fights) go through `feature-workflow`; a plain new entry of
     an existing kind is a CHANGELOG line.
- Catalog guard (in `tests/test_items.lua`, runs over every entry): unique ids, no retired id reused, known group and
  kind, an effect handler for the kind, fields the kind needs (duration > 0, known tier), price in 1..MAXIMUM_AMOUNT,
  the icon a string, the name and effect keys present in deDE.
- Testing the skill (writing-skills TDD): RED: a fresh subagent without the skill gets "add a 15-minute +3 Attack
  booster for 30g"; write down what it misses (expected: deDE keys, the test case, the retired-id rule, a new kind's
  handler, the price check). GREEN: the same task with the skill: the guard test passes and nothing is missed. Then a
  variation run ("add a Worldboss Trap") to look for gaps. The runs are done on a throwaway branch and thrown away.

## Review Focus (failure modes a happy-path test would miss)
1. RF1: buy with the exact balance / one copper short, and a corrupt `items` table (negative, string, huge counts,
   unknown ids) -> correct refusal, sanitized to 0..99, unknown dropped. Pinned by: T1.
2. RF2: meat used, /reload, then a kill -> still boosted (server-time end); clock jumps backwards -> never longer than
   20 s. Pinned by: T1/T2.
3. RF3: trap on a tapped / out-of-range / dead / already rolled / dungeon unit, or a rare with a normal trap -> refused,
   trap kept, no gold change. Pinned by: T2.
4. RF4: the target changes or dies while the item row is open -> the row closes, no use on the wrong unit. Pinned by: T4.
5. RF5: target-frame mode on a client without `TargetFrame` -> falls back to the nameplate, journal warning once.
   Pinned by: T5.

## Cross-cutting checklist (answer every line; "n/a: reason" is fine)
- [x] Protocol: unchanged; items and boosts are local, catches publish as before.
- [x] Stored data: `Store.SCHEMA` stays 2; new optional tables `caught.items`, `caught.boosts`, sanitized on load.
- [x] Trust model: n/a, no peer data; own SavedVariables are re-validated on load.
- [x] Localization: only item ids stored; names/effects via `Text[...]`, deDE added.
- [x] Load order: Items.lua after AzeCaught.lua (uses its constants), ShopView before AzeCaughtPanel builds.
- [x] Packaging: two new files listed in GuildGames.toc; tools/package.ps1 reads the TOC.
- [x] Tests: new tests/test_items.lua plus test_load assertions (adversarial cases in RF1-RF3).
- [x] Docs: README, CHANGELOG (Unreleased), doc.md.

## Decisions (user answers and design choices, newest last)
- 2026-11-25: user: a shop with buyable items and an inventory; Delicious Meat (guaranteed catch, global for 20 s,
  small timer icon), Magic Trap (click to catch without a fight, expensive, removed from the inventory); system easy to
  extend (later temporary attack/defense boosters); catch items as their own group with a floating label next to the
  catch icons that opens like the compact view's training menu; a non-immersive option to show the icon at the target
  frame instead of the nameplate.
- 2026-11-25: user chose: two separate tabs Shop + Inventory; item catches pay the normal reward; Meat 50g, Trap 500g;
  traps in three versions: normal, rare, elite; target-frame anchor (only the current target, nameplate icons off).
- 2026-11-25: design: trap tiers are ordered normal < elite < rare (rare covers rareelite); a trap catches its tier
  and below; world bosses never. Elite 1000g, Rare 1500g (scaled from the user's 500g). A trap catch pays the reward
  of a best-moment catch, since it has no roll.
- 2026-11-25: design: the meat boost ends at a stored server time, so a /reload keeps it; restart, not stack.
- 2026-11-25: user: "go ahead and integrate it", then start the simulator GUI. Open questions taken at the proposal
  (Elite 1000g, Rare 1500g, meat pays the normal reward); logged as an assumption.
- 2026-11-25: design: the bag and clock are one holder for the current target only (items act on the target); it sits
  right of the target's rope icon, else where that icon would be (nameplate or target frame). Nameplates off and
  target-frame mode off: nothing shows (the option is the answer for that).
- 2026-11-25: design: a throw armed while the boost ran still counts when the NPC dies just after the 20 s.
- 2026-11-25: design: the click-away closer moved from the pet view to `UIHelpers.CloseOnClickAway` and is shared.

## Open questions
- Prices of the Elite and Rare traps (1000g / 1500g, built as proposed) and whether the meat should pay less than the
  normal reward. (needs: user)

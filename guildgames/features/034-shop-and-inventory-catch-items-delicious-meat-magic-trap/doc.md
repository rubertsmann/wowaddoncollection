# Shop and inventory: catch items (Delicious Meat, Magic Traps)

Status: verifying | Since version: 0.8.0 | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
Two new AZEcaught tabs: **Shop** sells items for the money pool, **Inventory** shows what you own. Delicious Meat makes
every catch roll succeed for 20 seconds; the Magic Traps (normal, elite, rare) catch an enemy at once without a fight.
Catch items are used from a small bag next to the target's rope icon.

## How to use
- Shop tab: **Buy** (price from the money pool). Inventory tab: **Use** (a trap acts on the current target).
- At the target: the bag next to the rope icon (also at full health) -> a row of your catch items -> click one. A click
  anywhere else closes the row. While the meat runs, a clock shows the seconds left.
- Options > AddOns > GuildGames AZEcaught > **At the target frame**: icons next to the target frame instead of the
  nameplates (`/gg caught icon target on|off`).

## How it works
- Data (SavedVariables): `db.caught.items = { [itemID] = count }` (1..99), `db.caught.boosts = { [itemID] = end server
  time }`; ledger kind `shop`; `db.caught.icon.atTarget`. Sanitized on load; unknown ids dropped. Schema stays 2.
- Messages: no change; nothing about items is sent.
- Modules: `Core/Minigames/Items.lua` (catalog, inventory, buy, use, boosts), `AzeCaught.TrapCatch` and the boost check
  in `AzeCaught.OnDeath`, `Core/Game/Catcher.lua` (`UseTrap`, target-frame mode), `UI/ShopView.lua`,
  `UI/CatchItems.lua`, `UIHelpers.CloseOnClickAway` (shared with the pet view's training menu).
- New items: the `guildgames-new-item` skill (`.claude/skills/` at the monorepo root).

## Localization
All names and effects are `Text[...]` keys with deDE translations; only item ids are stored.

## Limits and known issues
- With nameplates off and the target-frame option off, the bag has nowhere to sit and is not shown.
- Several catches inside one 20 s meat boost can earn more than the meat costs (normal rewards, by choice).

## Changelog line
- Shop and Inventory tabs: Delicious Meat (20 s sure catches) and Magic Traps (catch without a fight); a bag at the
  target's rope icon; option to show the icons at the target frame.

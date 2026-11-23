# Changelog

## 0.4.0 (2026-11-23, protocol 1.2, schema 2, LibGuildSync MINOR 4)
- The minimap button is now a standard LibDataBroker-1.1 launcher shown by LibDBIcon-1.0 (LibGuildSync MINOR 4,
  `Widgets.CreateMinimapButton`), so button collectors (Leatrix Plus "Combine addon buttons", Minimap Button Bag,
  ElvUI, ...) and data displays (Titan Panel, ChocolateBar) find it. CallbackHandler-1.0, LibDataBroker-1.1 and
  LibDBIcon-1.0 are embedded under `Libs/` and loaded before LibGuildSync. Drag with the LEFT mouse button now.
  The position lives in `db.ui.minimapIcon` (LibDBIcon's table); the old `minimapAngle` is not carried over, so the
  button starts at its default spot (185 degrees, dev 165). The counter badge stays.
- Tooltip hint is now "Click: open window. Drag: move."
- Code comments checked against the code across the addon and the library (feature 021, comment audit run by the tests).
- AzeCaught: the steps of the companion tick and the seen-list eviction are named functions (refactor, no behaviour
  change); an unused combat-log constant was dropped from the Catcher.

## 0.3.1 (2026-11-22, protocol 1.2, schema 2, LibGuildSync MINOR 3)
- Fix: the minimap button was drawn inside the minimap; it now sits on the ring outside it, like other addons'
  buttons (LibGuildSync MINOR 3).
- Fix (LibGuildSync MINOR 3): a request from a member whose client still reports realm names ("Name-Realm") was
  ignored as a name mismatch, so that member never received the record; such names now fold to the realm-free name.
- Every HELLO carries the addon version and library MINOR (`ver`, optional field, no protocol change); `/gg comm`
  lists each member's version.

## 0.3.0 (2026-11-21, protocol 1.2, schema 2)
- AZEcaught arena (protocol 1.2): challenge guild members' companions to hands-off auto battles with an optional
  wager; the challenged player accepts or declines; the guild bets on the winner for 5 minutes at odds from the win
  chance; train Attack/Defense/Speed/Vitality, gain arena levels, keep wins and losses, and watch every fight as a replay.
  The Guild list is now a page of the Arena (Guild, Fighter, Fights); a fight icon on another member's pet there opens a
  step-by-step challenge window (matchup, wager, confirm).
  One fight at a time per player; a waiting challenge can be stopped (stake back); Accept/Decline/Stop sit in the Fights list.
- Accept/decline and yes/no buttons are tick and X icons (the word shows in the tooltip).
- Arena replay: the companions attack, flinch when hit and fall dead at 0 health.
- AZEcaught: the Seen tab keeps a history per NPC: how often you met it, how many you killed, caught x of y throws,
  first and last seen (stored with the collection; older entries start at "seen once").
- AZEcaught: the Seen stats are icon badges with small animations (fade in, count up, a pulse and "+1" when a number rises).
- AZEcaught: a catch becomes your companion at once when you have none, so the guild sees it right away.
- The dev build has its own key binding (no "Binding AZECAUGHT_THROW was attempted to be loaded more than once" with live and dev installed).

## 0.2.0 (2026-11-20, protocol 1.1, schema 2)
- Code reorganised like TalentShare (folders by role, shared helpers, naming lints); durations in the companion panel and
  minimap tooltip now read "2h" instead of "2h 0m" (feature 019).
- New game **AZEcaught** (feature 018): catch hostile NPCs and raise one as a companion.
  - Every NPC you fight is added to your collection. Below 35% health a rope icon shows on its nameplate; throw it (icon,
    the "AZEcaught: throw rope" key binding or `/gg catch`) and kill the NPC within 3 s for a chance to catch it (the first catch always succeeds). The chance
    rises from 20% at 35% health to 90% at 10% health; elite, rare, rare elite and boss NPCs subtract 5/10/15/25 points.
    The riskier the catch, the bigger the reward. Kill too slowly and the rope snaps (the icon breaks apart); an escape
    sends rope fragments flying off the target.
  - One caught NPC is your companion, shown as a 3D model. It gets hungry (every 2 h), thirsty (every 1 h), wants petting
    (every 2 h) and sleep (1 h every 4 h), counted in play time only. Food (50s) and water (25s) are paid from the money
    pool; petting and sleep are free. Caring in time earns hearts and a care streak (at most one step per hour), neglect costs them (down into the negatives); two hours
    without food or water and it dies. Switching away from a companion with negative hearts makes it run away.
  - The collection: Caught (no limit) and Seen (every enemy fought, highest level); switching asks first ("stats will be
    reset"). The model always shows the whole body (scroll to zoom). Hovering the model shows everything known about the NPC; its needs and thresholds come from its stats
    (creature type, power type, rarity).
  - The rope icon is round and sits above the nameplate; its ring turns from red to green with the chance and pulses
    at the best moment (with a short ping), turns into a net while the rope is out and shakes just before it
    snaps, a red arrow points at it until your first throw, and it can be
    moved, resized or turned off (Options > AddOns, `/gg caught icon`), and each enemy takes one throw. A throw winds
    up on your character and a moment later the lasso closes on the target itself (on its nameplate; above you when
    the target has none). The care buttons
    are icons, greyed out while not usable, with a short cooldown.
  - A Guild view ranks every member's companion (NPC level + rarity + hearts); the weekly place pays 500g / 300g / 150g /
    25g into the pool. The minimap button shows a badge when a need is due (`/gg notify off` turns it off).
  - Diagnostics: `/gg caught state|log|wallet|chance|collection|verbose|notify|export|probe`, an AZEcaught journal of its
    own (400 lines), warnings and errors also in `/gg debug`.
- **Money pool:** one balance for every game: 20g to start, plus your casino results, catch rewards and weekly payouts,
  minus food and water. **A stake can no longer be higher than the balance** (all games). The balance is shown next to
  the game switch.

## 0.1.0 (2026-11-18)
- The coin flip and the slot machine from TalentShare 0.6.0 are now their own addon, with the same rules, animations and
  leaderboards. They have their own saved data (`GuildGamesDB`), their own prefix (`GGames`) and protocol 1.0, and use the
  shared LibGuildSync-1.0 library. Results from TalentShare 0.6.0 are not imported (fresh start).
- The window is a light overlay: no border and a faint backdrop that only darkens while the mouse is over it.
  Clicks on its empty parts reach the game. The buttons and boxes are flat.
- The guild leaderboard is a sidebar that slides out from the window (arrow button in the header, closed by default).
  Its top three are marked gold, silver and bronze. Hover over a row to see won and lost.
- New effects:
  - coin flip: the coin hovers and rocks while idle and leaves a sparkle trail in the air. A win adds a shockwave,
    sparkles and a rising "+gold"; a loss adds a dust puff and a sinking "-gold".
  - slot machine: each reel flashes when it stops, and every win adds sparkles and a rising payout. Big wins also get
    a shockwave and a gold flash.
  - window: fades in and out; the game panels fade and the leaderboard rows slide in.
- New game **Survivor**: a tower fights waves of monsters, and you bet on how long it survives (1:00 x2, 1:30 x3, 2:00 x5,
  3:00 x10). Every level-up offers three items: weapons (fire bolt, cleave, frost nova) and passives (might, haste,
  armor, vitality, regeneration). It has its own leaderboard and feed. A run left open by a /reload or logout counts as lost.
  **Endless** mode: no end time, every minute doubles the payout (up to x64), cash out at any time.
  10 more ranged weapons: arcane missiles, shadow bolt, multi-shot, chain lightning, fireball, ice lance, smite,
  throwing knives, throwing axe and starfall. A tower holds at most 6 weapons.
  7 more upgrades: volley (+1 projectile), penetration (+1 pierce), reach (+15% area), thorns, deflect (reflects
  damage), barrier (a recharging shield, drawn as a bubble) and leech (kills heal).
- The game switch shows icons (the name is the tooltip).
- Window handles: drag the bottom-left one to move the window, drag the bottom-right grip to scale it (double-click
  resets the size). The window remembers its position and size.

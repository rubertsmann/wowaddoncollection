# Changelog

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

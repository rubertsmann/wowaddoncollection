# GuildGames

A coin flip, a slot machine and a survivor game for your guild, each with its own guild leaderboard (this week and all time), the
latest plays and last week's winner. **For fun only:** the addon never reads, checks or moves real gold. Stakes are
bookkeeping.

WoW Forever (interface 16001). The games started in TalentShare 0.6.0 and moved here with TalentShare 0.7.0.

## Use
- `/gg` opens the window. The buttons at the top left choose the game. They are locked while a game animates.
- **Coin flip:** enter a stake in gold/silver/copper (1c to 100 000g), choose Heads or Tails, then **Flip**. A win
  nets the stake and a loss costs it.
- **Slot machine:** 3 reels x 3 rows with 5 paylines (the rows and both diagonals). Three equal symbols on a line pay
  3x to 75x the stake, and lines add up (about 94% return). Press **Spin** or click the lever's knob. Hover the
  machine to see the paytable.
- **Survivor:** a tower in the middle of the arena fights monsters that walk in from the edges. Bet a stake on how
  long it survives: 1:00 pays 2x, 1:30 3x, 2:00 5x, 3:00 10x. The tower starts with a fire bolt. Every level-up pauses
  the run and offers three items to pick from: 13 weapons and 12 passives. Offence: might, haste, volley (+1 projectile),
  penetration (+1 pierce), reach (+15% area). Defence: armor, vitality, regeneration, thorns (damage to monsters touching
  the tower), deflect (turns damage away and hits the attacker with 3x of it), barrier (a shield that refills after 3 s)
  and leech (kills heal).
  Weapons: fire bolt, cleave (melee), frost nova, and the ranged arcane missiles (homing), shadow bolt (piercing),
  multi-shot (arrow fan), chain lightning, fireball (explodes), ice lance (pierces and slows), smite and starfall
  (strike from above), throwing knives (spiral) and throwing axe (flies out and comes back). The tower holds at most
  6 weapons. Reach the time and you win; if the tower falls first, you lose the stake. **Give up**
  ends the run as a loss. The stake is booked when the run starts, so a /reload or logout mid-run counts as a loss.
  Closing the window pauses the run.
  **Endless** mode has no end time: every full minute doubles the payout (1:00 x2, 2:00 x4, 3:00 x8, up to x64), and
  **Cash out** takes it at any time. If the tower falls, the last minute reached is still paid; before 1:00 the stake is lost.
- **Window:** the icons at the top left switch the game (hover for the name). Drag the handle in the bottom-left
  corner (or the header) to move the window; drag the grip in the bottom-right corner to scale it, double-click it to
  reset the size. Position and size are saved.
- `/gg version | comm | hello | debug [n] | trace [n] [problems] | clean [confirm] | locale [code|auto]`

## How it syncs
Every guild member running GuildGames shares one record of results (copper amounts, the last 4 weeks and the 20 latest
plays per game). A play is decided and **stored before** the animation runs, and is then announced with a coalesced
HELLO (at most one every 30 s). Peers pull the record by whisper and fall back to the guild channel. Only the
author of a record can send it, and every record is validated (shape, bounds, internal consistency). Results are
self-reported, so the guild has to trust its members.

The comms layer is **LibGuildSync-1.0** (embedded under `Libs/LibGuildSync`, shared with TalentShare): chunking, one
send budget for every addon that embeds it, the guild-only gate, record pulls with retries. Protocol:
[docs/protocol.md](docs/protocol.md).

## Development
- Tests: `luajit tests/run.lua` (needs `Libs/LibGuildSync`, created by deploy).
- Deploy: `powershell tools/deploy.ps1`. It links `AddOns\GuildGames-Dev` to this repo and `Libs\LibGuildSync` to
  `..\libguildsync\LibGuildSync`, and generates `GuildGames-Dev.toc`. The dev build uses `/ggd`, `GuildGamesDevDB` and
  prefix `GGamesDev`.
- Package: `powershell tools/package.ps1` builds `dist/GuildGames-<version>.zip` with the library as real files.
- Dev only: `/ggd anim` (animation probe), `/ggd anim speed 0.25`, `/ggd game sim <n>` (fake leaderboard players that are
  never stored or sent). Offline: `luajit tools/coinflip.lua [H|T] [flips]`.

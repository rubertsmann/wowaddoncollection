# GuildGames

A coin flip, a slot machine, a survivor game, the runner Companion Dash and AZEcaught (catch and raise a companion) for your guild, each with its own guild leaderboard (this week and all time), the
latest plays and last week's winner. **For fun only:** the addon never reads, checks or moves real gold. Stakes are
bookkeeping.

WoW Forever (interface 16001). The games started in TalentShare 0.6.0 and moved here with TalentShare 0.7.0.

## Use
- `/gg` opens the window. The buttons at the top left choose the game: AZEcaught (your companion) first, then the coin flip, slots, survivor and Companion Dash. They are locked while a game animates.
- **Minimal view:** `/gg` and the minimap button open, by default, a small view with only your AZEcaught companion and
  no text. The round pet sits in the middle, with four round care buttons around its lower half: feed, water, pet and
  sleep. The ring around each button fills clockwise with that need (half a ring = 50%) and is green, yellow or red by
  zone. A click does the care action. The small button at 6 o'clock under the pet opens the training: the four stat
  icons (Attack, Defense, Speed, Vitality); a click on one starts that training, its icon shows the time left and the
  others are greyed out; a click anywhere else closes them. The heart at the top right pulses on a gain and turns dark below 0. The icon at
  the top left switches to the full window and back, at the same screen spot. Hover anything for the details. Options
  > AddOns > GuildGames AZEcaught set the start view (minimal or full), the opacity (20-100%, full while hovered), the
  size (50-200%), a position lock and hiding in combat (on by default). The view stays open across reloads. Every few
  minutes an awake companion does something on its own: a roar, a dance, a wave, a swing, whatever its model can do.
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
  With a companion, your companion stands in the tower's place and attacks whenever a weapon fires.
- **Companion Dash:** your companion runs through a scrolling landscape; the monsters you have found or caught come at
  it. Click the top half of the play area to jump (hold for a higher jump), hold the bottom half to duck under flying
  monsters (Space / Up and Down work too). The speed keeps rising; one hit ends the run. No stake: every full 100 m
  pays 1g into your money pool, at most 50g a day. The guild board shows the best distances (this week and all time)
  and the recent runs. Needs an active companion.
- **AZEcaught:** catch NPCs and raise one as a companion.
  - Every hostile NPC you fight lands in your **collection**. When one is below 35% health, a rope icon shows on its
    nameplate. Throw the rope (click the icon, bind "AZEcaught: throw rope" in the key bindings, or `/gg catch` in a
    macro) and kill it within 3 seconds for a chance to catch it. Your very first catch always succeeds. One throw per
    enemy. Catching does not work in dungeons and raids: a throw there says so on screen and in chat. The enemy must be your
    own kill (not tagged by someone else) and fighting you: until it does, the icon is greyed out. After a failed throw or the enemy's death the icon goes away. The icon's ring turns from red to green as the chance grows and pulses at the best moment; until your first
    throw a red arrow points at it. Kill too slowly and the rope snaps. Move, resize or hide the icon in Options >
    AddOns > GuildGames AZEcaught (or `/gg caught icon on|off|x|y|size|reset`). There, **At the target frame** puts the
    rope icon and the catch items next to the target frame, for your target only, instead of on the nameplates
    (`/gg caught icon target on|off`).
  - **Shop** and **Inventory** tabs: buy items with the money pool, see and use what you own. Catch items:
    **Delicious Meat** (50g: every catch roll succeeds for 20 seconds, everywhere; a small clock shows the seconds
    left), **Magic Trap** (500g: catches a normal enemy at once, at any health, without a fight), **Elite Magic Trap**
    (1000g: normal or elite) and **Rare Magic Trap** (1500g: normal, elite, rare or rare elite; never a world boss).
    - **Charms** (300g each, owned once): one charm slot in the Inventory (Equip / Take off, free). **Lucky Charm**
      (catch rewards +10%), **Steady Hand** (the best moment starts at 13% health instead of 10%), **Second Chance** (when the
      rope slips off because the enemy died too late, you can throw once more at it), **Rare Lure** (elite and rare catches pay +25%).
    - **Care**: **Feast** (1g: hunger and thirst to full), **Squeaky Toy** (50s: affection to full), **Care Elixir** (5g:
      hunger, thirst and affection don't drop for 4 hours).
    - **Arena**: **War Paint** (250g: attack +10% for 3 fights), **Bark Skin** (250g: health +10% for 3 fights), **Swift
      Tonic** (100g: speed +25% for one fight). A fight is used when your fighter is sent (a request or an accept); the
      buff icons show next to the fighter for everyone.
    - **Games**: **Dash Shield** (10g: the next Companion Dash run survives one hit) and **Head Start** (5g: the next run
      starts at 200 m, no gold for those 200 m), armed with the two buttons beside the Start button; **Survivor Bomb**
      (100g: a button during a Survivor run with a stake of at most 250g, clears every monster on the screen, once per
      run). Runs that used an item carry a bag icon on the boards and in the feeds.
    Catches with items pay the normal reward (a trap: that of a best-moment catch). While you own catch items, a small
    bag sits next to your target's rope icon (also at full health): click it for a row of your catch items, click one
    to use it (a trap on the target), click anywhere else to close it. A refused trap is kept.
  - The chance rises from 20% at 35% health to 90% at 10% health and below; elite, rare, rare elite and boss NPCs
    subtract 5, 10, 15 and 25 points. A catch pays a reward into the money pool: the riskier the catch, the more.
  - The collection has two sections: **Caught** (no limit; duplicates count) and **Seen** (every enemy you fought with
    its highest level and how often you met it, the 100 seen most recently). The preview and the hover panel show
    the history: seen, killed, caught x/y, first and last seen. Select a caught one and press **Make companion** (it asks first: stats are reset).
  - Hover the model to see everything known about the NPC. Its needs come from its stats: e.g. beasts are hungrier,
    undead and mechanical companions never get thirsty, rage users and rare NPCs get needy sooner.
  - Every catch is its own companion in your **roster** (Collection > Caught: one row per companion, its arena level
    and NPC level). One is active at a time: **Make companion** switches for free, both keep their needs, hearts,
    XP and training (a running training session is cancelled). Resting companions are frozen: no needs, no death.
    **Release** lets one go for good. Every companion can be given a nickname **once** (up to 24 characters): select it
    in Collection > Caught and press **Rename** (above Make companion), type the name and press the tick (the cross cancels). The same works
    by clicking the active companion's name or with `/gg caught name <text>`. Once named, the Rename button is gone. Guild members see the nickname in the guild list and in fights, with
    the species on hover. Hover over the name (or a roster row) to see where and when it was caught (companions caught
    before 0.12.0 have no record of it). In play time only, the active one needs water every hour, food every 2 hours,
    petting every 2 hours and 1 hour of sleep every 4 hours; the bars show the thresholds.
  - **Companion** view: a click on a need bar cares for it (Food bar feeds, Water waters, Petting pets, Energy puts it
    to sleep or wakes it; hover for the price). Under the name: the arena level, wins/losses and an XP bar (hover for
    the stats and the ability). Below the bars: the four stat icons with their trained points (e.g. 10/25); a click
    trains that stat.
  - Food costs 50s and water 25s from the pool; petting and sleep are free. Care in time earns hearts (red heart counter) and a care streak (at most +1 per hour);
    a critical need costs a heart every 10 minutes, into the negatives. Two hours without food or water and it dies.
  - **Guild** view: everyone's companion, ranked by NPC level + rarity + hearts. Last week's place pays 500g, 300g, 150g,
    or 25g into your pool. The minimap button shows a badge when a need is due; `/gg notify off` turns reminders off.
  - **Arena:** every fight is **3 against 3**. Request a fight on the **Fights** page: pick a guild member in the
    dropdown (members on another version, with fewer than 3 companions, in a fight or offline are greyed out; hover
    says why), then **Fight!** opens the team picker: your three companions in fighting order and your wager (at least
    1g). Send takes the wager and crossed swords clash. The other player accepts in the same picker: your team in a
    carousel (stats, ability, buffs), their three and **their own wager** (any amount from 1g); or
    they decline. The first of each side fight; the winner stays in with its health and running effects and meets
    the next one; the side without fighters left loses. Every companion that entered gains XP (more per opponent it
    beat). Both players need the **same GuildGames version**, otherwise requests and accepts are refused. 5 minutes
    after the accept the fight is decided on its own (no input: stats, arena level, training, hearts, needs and the
    creature type's ability decide). In those 5 minutes the rest of the guild can bet on either side (one bet each).
    **The pot:** each fighter's wager is the first stake on their own side, every bet joins its side; the winning side
    gets its stakes back plus the losing side's whole total, split by each stake's share. The losing side loses
    everything. Train Attack, Defense, Speed or Vitality in the Companion view or the minimal view's training button
    (gold, energy and 10 minutes of play time per point) and gain XP and arena levels. The Arena view has the Guild
    and Fights pages. A decided fight shows "watch!": its result, the pot and the bets are paid only after you watched
    the replay in the Arena view (`/gg arena`), or on their own an hour after the fight.
- **Money pool:** one balance for all games: 20g to start, plus your casino results, catch rewards and weekly payouts,
  minus food, water and the shop. You cannot stake more than the balance. It is shown next to the game switch.
- **Window:** the icons at the top left switch the game (hover for the name). Drag the handle in the bottom-left
  corner (or the header) to move the window; drag the grip in the bottom-right corner to scale it, double-click it to
  reset the size. Position and size are saved.
- `/gg version | comm | hello | debug [n] | trace [n] [problems] | clean [confirm] | locale [code|auto]`
- AZEcaught diagnostics: `/gg caught state | log [n] [filter] | wallet | chance | collection | dump [unit] | verbose on|off |
  notify on|off | export | probe | model` (`model`: the companion model's animations and camera, shown for 15 s). Every catch logs everything the client tells about the NPC (`/gg caught log 1 catch.dump`). The journal keeps the last 400 AZEcaught steps (throws, rolls with every factor, care, hearts, money).

## How it syncs
Every guild member running GuildGames shares one record of results (copper amounts, the last 4 weeks and the 20 latest
plays per game). A play is decided and **stored before** the animation runs, and is then announced with a coalesced
HELLO (at most one every 30 s). Peers pull the record by whisper and fall back to the guild channel. Only the
author of a record can send it, and every record is validated (shape, bounds, internal consistency). Results are
self-reported, so the guild has to trust its members.

The comms layer is **LibGuildSync-1.0** (embedded under `Libs/LibGuildSync`, shared with ProfessionShare): chunking, one
send budget for every addon that embeds it, the guild-only gate, record pulls with retries. Protocol:
[docs/protocol.md](docs/protocol.md).

## Development
- Tests: `luajit tests/run.lua` (needs `Libs/LibGuildSync`, created by deploy).
- Deploy: `powershell tools/deploy.ps1`. It links `AddOns\GuildGames-Dev` to this repo and `Libs\LibGuildSync` to
  `..\libguildsync\LibGuildSync`, and generates `GuildGames-Dev.toc`. The dev build uses `/ggd`, `GuildGamesDevDB` and
  prefix `GGamesDev`.
- Package: `powershell tools/package.ps1` builds `dist/GuildGames-<version>.zip` with the library as real files.
- Dev only, AZEcaught: `/ggd caught setup [items|boost]` (one start state: a test companion if none, 3000g, 3 of
  every shop item, the window on the Shop tab; `items` only the items, `boost` also starts Delicious Meat),
  `/ggd caught add` (target or a test NPC as caught), `time <minutes>` (fast-forward play time),
  `give <gold>`, `force` (next roll catches), `need <name> <0-100>`, `week` (run the weekly payout again),
  `restore <code>` (a companion from a restore code built out of a backup with `AzeCaught.RestoreCode`, once per
  character; it was a player command in 0.11.2 only).
- Dev only, arena (also the icons in a row just below the Fights page; all memory only, never stored or sent):
  `/ggd arena dummy [off]` (a fake member that accepts after 20 s), `request [gold]` (it challenges you), `accept` /
  `decline` (it answers your waiting challenge now), `skip` (its accepted fights are decided now), `crowd` (fake bettors
  on both sides of the selected open fight), `latebet` (a fake bet after the selected fight's fight time),
  `members` (a fake member that can be challenged and answers like the dummy, plus one for every greyed reason), `expire` / `reveal` (fake fights past their time
  to live / past the one hour reveal), `clear` (all of it gone).
- Dev only: `/ggd anim` (animation probe), `/ggd anim speed 0.25`, `/ggd game sim <n>` (fake leaderboard players that are
  never stored or sent). Offline: `luajit tools/coinflip.lua [H|T] [flips]`.

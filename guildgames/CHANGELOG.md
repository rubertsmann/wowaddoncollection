# Changelog

## 0.15.0 (2026-11-28, protocol 1.9, schema 3, LibGuildSync MINOR 6)
- Survivor and Companion Dash no longer draw the pulsing hitbox markers (the ring and orange fill around the Survivor tower, the pulsing gold square glow behind it, the boxes around the runner and the monsters); `UIHelpers.CreateHitbox` / `Shimmer` are gone.
- Putting the companion to sleep stops its running training (no refund), like switching companions; the Sleep tooltip warns while a training runs (feature 053).
- Daily win limit display (feature 051): the limit line above the games is gone; hovering the pool amount explains the limit in detail (won today, cut today, left, reset time, why), and a "!" next to each stake warns when a win would be cut, the stake is above the pool, or it is free play.

## 0.14.0 (2026-11-28, protocol 1.9, schema 3, LibGuildSync MINOR 6)
- Daily win limit and smaller Survivor payouts (feature 051, protocol 1.9): coin flip, slots and Survivor together raise the money pool by at most 500g net per UTC day (the record keeps the real result, the part above the limit is a `cap` ledger entry; play goes on, a win just pays nothing more). Stake 0 is free play in all three. Survivor pays 105/110/120/140% (1:00/1:30/2:00/3:00), endless 105% at 1:00 plus 5% per minute up to 130%; new runs are stored in the record field `tower` (peers on 1.8 drop it and keep the record), the old `survivor` field stays as history in the pool without a leaderboard. From 4:00 monsters grow 2.5x stronger per minute, so no run lasts past 8:00. Coin and slots wait while a Survivor stake is pending. `/gg caught wallet` shows the limit.
- Maintainer-only (i) button at the bottom left of the window (feature 052): its tooltip lists each guild member's live build (HELLO) next to the version their synced record carries, stale records in orange. Fix: at login the own arena section (which carries the version fights compare) is written again when it is missing or from an older build; before, it was only written by arena actions, so members who updated or never used the arena counted as "another version" for everybody.

## 0.13.0 (2026-11-27, protocol 1.8, schema 3, LibGuildSync MINOR 6)
- Survivor and Companion Dash polish (feature 043): game models are no longer cut off (their frames have room around the creature) and are framed again when the window is scaled or shown; the companion seen from above in Survivor is framed by its own size; pulsing outlines show the real hitboxes (the Survivor tower's ring, the Companion Dash runner and monsters). Survivor's target buttons (which overlapped) are one dropdown, and Start is an icon (charge to start, red X to give up, coin to cash out; the word is in the tooltip). Companion Dash's stats and last result sit in a framed box.
- Arena > Guild: hovering a member's row or the companion model shows the same info panel as Collection > Caught (level, rarity, type, combat stats, needs, traits), with the companion's TLevel and hearts on top. The ranking value (NPC level + rarity + hearts) is now called TLevel (training level) everywhere: the guild list, its badge, the companion view and "last week's best"; plain "Level" is only the NPC level. Hovering a fighter in a fight card (Fights page and team picker) also shows its TLevel from when the team was sent (new optional `tl` on each fighter; older teams show none). Your own history with that NPC is shown only if you met it.

## 0.12.0 (2026-11-27, protocol 1.7, schema 3, LibGuildSync MINOR 6)
- Arena fight requests move to the Fights page: a dropdown of the guild members (another version, fewer than 3 companions, in a fight or offline: greyed out with the reason on hover), "Fight!" opens the team picker with your wager, Send plays a swords clash. The fight icon in the Guild view is gone (feature 041).
- Each fighter sets their own wager (at least 1g); the accepting player picks their team and wager in the same picker. Counter offers are gone.
- Side bets go into one pot per fight: the winning side (fighter plus bettors) gets its stakes back plus the losing side's total, split by share; the losing side loses everything. No more fixed odds.
- A decided fight nobody watched settles by itself 1 hour after the fight time (was 24 hours).
- Companion nicknames (feature 042): every companion can be named once, with up to 24 characters. In Collection > Caught, select it and press Rename, then type the name and press the tick (the cross cancels). Clicking the active companion's name or `/gg caught name <text>` does the same. The nickname shows everywhere, and guild members see it in the guild list and in fights, with the species on hover. Each companion also remembers when and where it was caught (zone from the map id, shown in the client's language; only you see it). Companions caught earlier have no record. The fight history keeps NPC ids and nicknames instead of name text.
- Dev build: icons and `/ggd arena` commands for fake events (dummy accept/decline, fake bettors, a late bet, greyed members, expire, reveal, clear).

## 0.11.3 (2026-11-26, protocol 1.6, schema 3, LibGuildSync MINOR 6)
- `/gg caught restore` is gone from the player build (a public code format made it an easy way to forge trained companions); it lives on as the dev command `/ggd caught restore <code>` (feature 040).

## 0.11.2 (2026-11-26, protocol 1.6, schema 3, LibGuildSync MINOR 6)
- Fix: updating from 0.10.x or older no longer loses every catch and the active companion. 0.11.0 and 0.11.1 lost them when a guild member's outdated arena or companion section was dropped during the same load (feature 040).
- `/gg caught restore <code>`: brings back a companion lost to that bug from a restore code built out of a pre-update backup (once per character).

## 0.11.1 (2026-11-26, protocol 1.6, schema 3, LibGuildSync MINOR 6)
- Fix: the game no longer blocks GuildGames in combat ("reserved for the Blizzard UI"). The rope's 28 yard range check used a function the client forbids in combat; the rope and the traps now need the enemy to be fighting you instead (feature 039).
- The rope icon is greyed out while the enemy is not fighting you, and hides on a dead enemy and after a failed throw (it came back after a minute before).

## 0.11.0 (2026-11-25, protocol 1.6, schema 3, LibGuildSync MINOR 6)
- Companion roster (feature 037): every catch is its own companion with its own needs, hearts, arena XP and training; one is active, resting ones are frozen; switching is free (a running training is cancelled); Release lets one go. No more running away on a switch.
- Team arena fights (feature 038): every fight is 3 against 3 in the picked order; the round winner carries its health and effects into the next round; the defender sees the challenger's team in full and picks three in a dialog (also for counter offers); XP per companion that entered plus per knockout; arena buffs work on the whole team, one charge per fight; the dummy fields a team. Their team shows as a carousel (portrait with model, stats, arrows).
- Same-version gate: the arena section carries the addon version; challenges, accepts and counter offers need the same version on both sides; a fight between different versions is void and refunded.
- Protocol 1.6 (arena entries carry a team `t` instead of a fighter `f`, the section carries `ver`); schema 3 (`caught.roster`, `activeID`, `nextID`; progress per companion `ar`); open one-against-one challenges are void and their stakes refunded once.
- Dev: `/ggd caught setup` fills the roster up to three test companions.

## 0.10.0 (2026-11-25, protocol 1.5, schema 2, LibGuildSync MINOR 6)
- Item batch (feature 036), 13 new shop items in four new groups:
  - Charms: Lucky Charm, Steady Hand, Second Chance and Rare Lure, worn in one charm slot.
  - Care: Feast, Squeaky Toy and Care Elixir.
  - Arena buffs: War Paint, Bark Skin and Swift Tonic, built into the published fighter's stats.
  - Games: Dash Shield, Head Start and Survivor Bomb (stake at most 250g).
- Protocol 1.5, additive: the fighter's `bf` (buff ids), the runner `bi` and recent `it`, and the survivor play `it` (item marks). 1.4 peers drop them and compute the same fights.
- Saved data gains `caught.equipped` and `caught.arenaBuffs`; schema stays 2.

## 0.9.1 (2026-11-25, protocol 1.4, schema 2, LibGuildSync MINOR 6)
- The Arena, Shop and Inventory tabs of AZEcaught open only once a companion is chosen (your next catch becomes it).
- Pets and monsters show as icons while their model is not drawn (the UI simulator draws no models).

## 0.9.0 (2026-11-25, protocol 1.4, schema 2, LibGuildSync MINOR 6)
- Companion Dash (feature 035): a runner game. Your companion jumps over and ducks under monsters from your collection in
  front of a parallax landscape; mouse (top half jump, bottom half duck) or Space / arrow keys; the speed ramps up and one
  hit ends the run. 1g per 100 m, at most 50g a day. Guild board of best distances: new optional record section
  `runner = { b, n, weeks, recent }`, protocol 1.4 (additive; 1.3 peers drop it). Saved data gains `runner` (schema stays 2).
- Survivor: the companion stands in the tower's place (from above when the client allows the model camera) and attacks
  whenever a weapon fires; the tower icon stays without a companion. The arena is a grass field seen from above and
  clips projectiles and monsters at its edge.
- Dev: `/gg caught model` reports the model's animations and camera calls and shows the top view for 15 s.

## 0.8.0 (2026-11-25, protocol 1.3, schema 2, LibGuildSync MINOR 6)
- Shop and Inventory tabs in AZEcaught (feature 034): Delicious Meat (50g, every catch roll succeeds for 20 s, a clock
  shows the time left) and Magic Traps (500g normal, 1000g elite, 1500g rare: catch at once without a fight). A bag
  next to the target's rope icon opens a row of the owned catch items. Option "At the target frame": icons next to the
  target frame instead of on nameplates. Saved data gains `caught.items` and `caught.boosts` (schema stays 2); nothing new is sent.
- The AZEcaught tabs are icons (name on hover); AZEcaught is the first button of the game switch.
- Dev: `/ggd caught setup [items|boost]` sets a test start state in one command.
- Project skill `guildgames-new-item` (monorepo `.claude/skills`) for adding items; the catalog guard test checks every entry.

## 0.7.0 (2026-11-25, protocol 1.3, schema 2, LibGuildSync MINOR 6)
- The fighter moved into the Companion view (feature 033): arena level, W/L and XP under the name, the four stat icons
  with their points (10/25) below the need bars, a click trains. Arena > Fighter is gone (Arena: Guild, Fights).
- The need bars are the care buttons: a click on Food, Water, Petting or Energy feeds, waters, pets or sleeps/wakes
  (the four care icons are gone).
- Minimal view: a training button under the pet opens the four stat icons; a click trains, the time shows on the icon,
  a click elsewhere closes them.

## 0.6.0 (2026-11-25, protocol 1.3, schema 2, LibGuildSync MINOR 6)
- `/gg catch` (and the throw binding and rope icon) inside a dungeon or raid now says, in the red line at the top of
  the screen and in chat, that catching does not work there (feature 031).
- The rope is refused at an enemy someone else tagged and at one farther than 28 yards (when the client tells the
  distance; otherwise the throw is allowed as before).
- Arena (feature 032): watch to see the result. A decided fight says "your fight is decided, watch it"; the result,
  the wager, W/L, XP and side bets are settled only after the replay (or by themselves 24 h later).
- Arena: counter offers. The challenged player can answer with another wager (paid at once); the challenger accepts
  (pays or gets back the difference, the fight starts) or declines (both wagers come back). Protocol 1.3 (additive: a
  1.2 peer sees a countered challenge as unanswered).

## 0.5.0 (2026-11-24, protocol 1.2, schema 2, LibGuildSync MINOR 6)
- New minimal view (feature 030): only the companion, round care gauges that fill clockwise, a heart icon, no text.
  `/gg` opens it by default; the top-left icon switches to the full window and back. Options: start view, opacity,
  size, lock, hide in combat (`db.ui.petView`, no schema change). Dev: `/ggd caught hearts <n>`.
- An awake companion plays a random animation it has (roar, dance, laugh, wave, attack, ...) every 90-240 s in the
  minimal view and the companion panel. Dev: `/ggd caught emote` plays one now.

## 0.4.2 (2026-11-23, protocol 1.2, schema 2, LibGuildSync MINOR 6)
- The minimap button is also listed in the addon compartment where the client has one, so GuildGames stays reachable
  when Leatrix Plus or another collector hides minimap buttons (LibGuildSync MINOR 6).

## 0.4.1 (2026-11-23, protocol 1.2, schema 2, LibGuildSync MINOR 5)
- Fix: no addon whispers to members who went offline ("no player named ... is online"); a newer games record to the
  same member replaces one still waiting in the send queue (LibGuildSync MINOR 5, ProfessionShare feature 023).

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

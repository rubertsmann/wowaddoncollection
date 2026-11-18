# Guild game base (first game: coin flip)

Status: draft (verifying) | Since version: 0.6.0 (unreleased) | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
A **Games** tab with an animated coin flip. The player enters a stake in gold, silver and copper (1c to 100 000g), picks heads or tails and
flips against "the house" (50/50, win = +stake, loss = -stake). The coin is tossed, spins and lands on the result; a win
glows and plays a coin sound, a loss shakes. Every guild member's wins and losses show on a leaderboard (this week / all
time), with the 15 latest flips and last week's winner. For fun only: the addon never reads, checks or moves real gold.

Second game: a **slot machine** (3 reels x 3 rows, 5 paylines: the rows and both diagonals; three equal symbols on a line
pay 3x to 75x the stake, lines add up, about 94% return). The reels spin and stop left to right, the lever is pulled,
the cabinet lights chase; a win highlights each winning line in turn, makes the winning symbols glow and pulse, counts the
payout up and, from 15x or on a coin line (jackpot), rains coins. Each game has its own leaderboard and recent list.

## How to use
- UI: `/ts` -> **Games**; the buttons at the top left pick the game (locked while a game animates). Slots: stake
  boxes, **Spin** (or click the lever's knob), hover the machine for the paytable.
- Coin flip panel: coin, Heads/Tails, "Stake (gold)", **Flip**. Right: last week's winner, This week / All time,
  leaderboard (rank, player, net, won, lost, wins/losses; my row highlighted), Recent flips.
- Three stake boxes (gold, silver, copper; Tab moves between them, Enter flips). The stake is remembered in copper
  (`db.ui.lastStakeCopper`), the scope too (`db.ui.gamesScope`). Amounts show as "1g 50s 25c" in coin colours.
- Dev build only: `/tsd anim` (animation probe P1-P8, prints `anim P1..P8` lines and shows test squares for 10 s),
  `/tsd anim speed 0.25` (slow motion; `1` = normal), `/tsd game sim <n>` (n fake leaderboard players, memory only; `0` clears).
- Offline: `luajit tools/coinflip.lua [H|T] [flips]` prints the coin's pose curve and a flip distribution.

## How it works
- Data (SavedVariables, schema 4): `games[name] = { name, rev, total, weeks["YYYY-Www"] (<= 4), recent (<= 20) }`, all amounts in copper
  (`Core/Play/Games.lua`; full shape and limits in `docs/protocol.md` section 9).
- Messages (protocol 2.3, additive): `HELLO.grev`, `WANTG {names, via?}`, `GAMES {games}`; pulled like offers
  (whisper, then GUILD retries). A flip announces itself with a coalesced HELLO (at most one per 30 s plus the due one).
- Order of a flip: `Games.Flip` decides and **stores** the result -> `GAMES_CHANGED` (announce) -> coin tween
  (`Animate.Tween("coin", ...)` applying `CoinFlip.Pose`) -> landing effects -> leaderboard refresh. The Flip button is
  disabled and the leaderboard refresh deferred while the coin flies; a `/reload` mid-flip keeps the stored result.
- Slots: `Core/Play/Slots.lua` (strip of 35 symbols, `Spin` draws one stop per reel and stores the play with
  `Games.RecordPlay` in `record.slots` before the reels move; `ReelPose` = staggered reel motion with overshoot),
  `UI/SlotMachine.lua` (cabinet, reels cropped per frame, lever, lights, paylines, shower).
- Modules: `Core/Play/Games.lua` (rules, records, validation, ISO weeks, simulated players), `Core/Play/CoinFlip.lua`
  (pure pose math), `Core/View/Model.lua` (`BuildLeaderboardRows`, `BuildFlipFeedRows`, `PreviousWinner`),
  `UI/Animate.lua` (FadeIn, Pulse, Shake, Glow on AnimationGroups with fallbacks; shared OnUpdate tween driver),
  `UI/GamesTab.lua` (the tab), `UI/Window.lua` (tab list, `UI.Widgets`), `Core/Net/Sync.lua` + `Communication.lua` (sync).

## Localization
All labels via `Text[...]` (enUS keys, deDE translations). Only numbers, week keys, "W"/"L" and names go on the wire.
Dev probe output is English on purpose.

## Limits and known issues
- Results are self-reported: a modified client can report any well-formed numbers (guild trust model).
- Gold is bookkeeping only; no settlement between players.
- Animation facts (types, alpha end state, scale origin, texture paths, coin sound) are not yet measured on the Forever
  client: `/tsd anim` answers them; every effect falls back to its end state when a type is missing.
- A record pull lost late in a lossy period can lag up to the retry schedule (45 + 90 + 180 s) or the next HELLO.

## Changelog line
- Games tab: animated coin flip with a gold stake and a guild leaderboard (protocol 2.3, schema 4). For fun only.

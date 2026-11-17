# 014 Guild game base (first draft: coin flip): spec

- Status: verifying
- Created: 2026-11-17
- Target version: 0.6.0 (protocol 2.3, schema 4)
- Owner: claude (decisions: user)
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md) | [animation study](evidence/animations-research.md)

## 0. Read me first (for the implementing agent)
This file is self-contained: everything needed to implement 014 is here or linked. Workflow rules:
`.claude/skills/feature-workflow/SKILL.md` (tick tasks, append to `log.md` after each task, keep this spec true).
1. Baseline: `luajit tests/run.lua` -> **209 passed, 0 failed** (2026-11-17, before any 014 code). Run it first.
2. Read, in this order: this spec; `evidence/animations-research.md`; `docs/protocol.md` (sections 1-8); the offers
   feature as the template for a per-player synced record: `Core/Data/Offers.lua`, `Sync:_onWANTO`/`_onOFFERS`/
   `RECORD_KINDS` in `Core/Net/Sync.lua`, `Store.Migrate` in `Core/Data/Store.lua`; tests `tests/test_offers.lua`, `tests/test_sync.lua`.
3. Code conventions (features 012/013, see their `doc.md`): full-word names, LuaLS annotations (`---@class`, `---@param`),
   one logging helper `addon.Log.Information|Warning|Error|Exception(area, message, fields)`, helpers in `addon.Utility`
   (`SafeInteger(value, min, max)`, `IsSafeName`, `Escape`, `Now`, `CanonicalName`, `DeepCopy`, `SanitizeMap`, `SortedKeys`, `Count`).
   Pure modules never touch WoW globals; WoW calls only in `Core/Game/Api.lua` and `UI/*`.
4. Dev-only slash commands live under `/tsd` and are registered inside `if addon.IS_DEVELOPMENT_BUILD then ... end`
   (pattern: `UI/DevProbe.lua:334`). Player commands are `addon.SlashCommands.<name>` (`/ts <name>`).
5. After any TOC change run `powershell tools/deploy.ps1` (regenerates `TalentShare-Dev.toc`; `tests/test_load.lua` fails
   while it is stale) and restart the game (`/reload` does not re-read the TOC).
6. Commit only if the user asked; message `feat(guild-game-base): ...` with the Co-Authored-By trailer. Never push or tag.

## 1. Goal
A "Games" tab with a reusable base for asynchronous guild-wide games, first used by an **animated coin flip**: the player
enters a gold stake, picks heads or tails, the coin is tossed with an animation, and every player's wins and losses (gold
amounts) are shown on a guild leaderboard that syncs like offers do.

## 2. Requirements
- R1: The window gets a 5th tab "Games" (between "Available" and "Debug"); tabs are driven by one ordered tab list.
- R2: Coin flip: stake = whole gold, 1..`MAXIMUM_STAKE` (100 000); pick = heads `"H"` or tails `"T"`; outcome 50/50
  from `Api.Random()`; win = `+stake`, loss = `-stake`. Invalid stakes are refused with a message, nothing is recorded.
- R3: The outcome is decided and **stored before the animation starts**; the animation only reveals it. `/reload` during the
  animation neither loses nor re-rolls the flip. The Flip button is disabled while a flip animates (no double flips).
- R4: The flip is animated: toss (rise and fall), spin (coin narrows and widens, face swaps at each edge-on moment, slowing
  down), landing on the outcome face, landing pulse, result text fading in ("+250g" / "-250g"), win: glow + coin sound,
  loss: short shake. If an animation type is unavailable, the final state is shown directly and no Lua error is raised.
- R5: My results are ONE record per character (`GameRecord`), authored only by me, replaced as a whole by a newer `rev`,
  synced with protocol 2.3 (`HELLO.grev`, `WANTG`, `GAMES`), stored in schema 4.
- R6: Leaderboard: scope "This week" (ISO week of server time, UTC) or "All time"; columns rank, player, net, won, lost,
  flips (wins/losses); sorted by net desc, then flips desc, then name; my row highlighted; players without flips in the scope hidden.
- R7: "Recent flips" feed: the newest 15 flips of all guild members (name, +/- amount, time ago) - every win/loss amount is visible.
- R8: "Last week's winner: <name> (+<net>g)" line from the previous ISO week.
- R9: The tab states "For fun only: no gold changes hands." The addon never reads, moves or checks real gold.
- R10: Peers on protocol 2.2 or older keep syncing everything else; a schema-4 file opened by 0.5.x is left untouched.
- R11: Offline iteration: rules, record validation, leaderboard, coin pose math and sync run in `luajit tests/run.lua`;
  `luajit tools/coinflip.lua` prints the animation curve and a flip distribution; the dev build has `/tsd anim` (probe P1-P8)
  and `/tsd game sim <n>` (n fake leaderboard players, in memory only, never stored or sent).

## 3. Non-goals
- Real gold: no trade, mail, `GetMoney()` checks or settlement. Numbers are bookkeeping for fun.
- Player-vs-player sessions, invites, hidden information, real-time play (transport is paced at ~0.9 msg/s).
- Cheat-proof results: results are self-reported (trust model: guild members are trusted); only shape, bounds and internal
  consistency are validated. A modified client can report any plausible numbers.
- The local UI preview / WoW widget emulator (proposed as its own feature, see Open questions).
- The final guild game and its theme (later feature).

## 4. Design

### 4.1 Files
| File | New/changed | Content |
|---|---|---|
| `Core/Play/Games.lua` | new, pure | `addon.Games`: constants, `PeriodKey`, `Flip`, `Sanitize`, `SanitizePersisted`, `Get`, `Put`, `Mine`, `Simulate`, `AllRecords` |
| `Core/Play/CoinFlip.lua` | new, pure | `addon.CoinFlip`: `DURATION`, `Pose(elapsed, outcome)` (animation math, no WoW calls) |
| `Core/Data/Store.lua` | changed | `SCHEMA = 4`; `"games"` in `withAllTables` list (`:77`); `MIGRATIONS[3]` adds `games = {}`; `SanitizePersisted` calls `addon.Games.SanitizePersisted` (next to Offers, `:194`) |
| `Core/Net/Sync.lua` | changed | `RECORD_KINDS.games`; `wantedGames = {}` in `Sync.New` (`:84`); `grev` in `_helloMessage` (`:128`) and `_onHELLO`; `_onWANTG`, `_onGAMES`; header comment lists the new messages |
| `Core/Net/Communication.lua` | changed | `WANTG` in `PRIORITY_TYPES` (`:114`); `Communication.RequestHelloSoon()` (coalesced announce, 4.5) checked in the 1 s pump (`:503`) |
| `Core/Base/Init.lua` | changed | `PROTOCOL_MINOR = 3` (`:44`) |
| `Core/Game/Api.lua` | changed | `Api.Random()` -> `math.random()`; `Api.CoinSoundKit()` -> `SOUNDKIT and SOUNDKIT.LOOT_WINDOW_COIN_SOUND` or nil |
| `Core/Game/Events.lua` | changed | `Events.On("GAMES_CHANGED", addon.Communication.RequestHelloSoon)` (next to `:107`) |
| `Core/View/Model.lua` | changed | `Model.BuildLeaderboardRows`, `Model.BuildFlipFeedRows`, `Model.PreviousWinner` (escaped names) |
| `UI/Animate.lua` | new, client | `addon.Animate` effects + tween driver (4.6) |
| `UI/Window.lua` | changed | tab list refactor (`:592-603`, `:1338-1357`); `UI.Widgets` export of the local widget helpers |
| `UI/GamesTab.lua` | new, client | `addon.GamesTab.Build(tabFrame)`, `addon.GamesTab.Refresh()` (4.7) |
| `UI/DevProbe.lua` | changed | `/tsd anim` probe, `/tsd anim speed <x>`, `/tsd game sim <n>` |
| `Locales/enUS.lua`, `Locales/deDE.lua` | changed | strings in 4.8 |
| `TalentShare.toc` | changed | `Core\Play\Games.lua`, `Core\Play\CoinFlip.lua` after `Core\Data\Offers.lua`; `UI\Animate.lua`, `UI\GamesTab.lua` after `UI\Window.lua` |
| `tests/run.lua` | changed | add `Core/Play/Games.lua`, `Core/Play/CoinFlip.lua` after `Core/Data/Offers.lua` in the module list (`:28`); `PROTOCOL_MINOR = 3` (`:22`) |
| `tools/coinflip.lua` | new, dev | console view of `CoinFlip.Pose` and of 10 000 simulated flips |
| tests | new/changed | 4.9 |

Load order: Store calls `addon.Games` only at call time (`Store.Init` runs at ADDON_LOADED), so `Core/Play` after
`Core/Data/Offers.lua` is fine. Window builds its frame lazily (first open), so `UI/GamesTab.lua` may load after it.

### 4.2 Data shape (stored in `TalentShareDB.games[name]`, and on the wire)
```lua
---@class GameTotals
---@field won integer    gold won in the scope (sum of winning stakes)
---@field lost integer   gold lost in the scope
---@field wins integer   number of won flips
---@field losses integer number of lost flips

---@class GameFlip
---@field g integer   stake in gold, 1..MAXIMUM_STAKE
---@field r "W"|"L"
---@field t integer   server time of the flip

---@class GameRecord
---@field name string                       owner, canonical "Name-Realm"
---@field rev integer                       newer wins (commit rule as Offers: max(now, previous + 1))
---@field total GameTotals                  all time
---@field weeks table<string, GameTotals>   "YYYY-Www" -> totals; at most MAXIMUM_WEEKS (4) newest keys
---@field recent GameFlip[]                 newest first, at most MAXIMUM_RECENT (20)
```
Constants in `Games`: `MAXIMUM_STAKE = 100000`, `MAXIMUM_TOTAL = 2000000000`, `MAXIMUM_COUNT = 1000000`,
`MAXIMUM_WEEKS = 4`, `MAXIMUM_RECENT = 20`. The pick (H/T) is not stored or sent (it does not change the odds).
Field names are wire format: keep them short and never rename them inside protocol major 2.

### 4.3 Pure API (`Core/Play/Games.lua`)
- `Games.PeriodKey(serverTime) -> "YYYY-Www"`: ISO 8601 week in UTC, integer arithmetic only (no `os.date`, it is local
  time in tests and absent/limited in the client). Algorithm: days = floor(t / 86400); weekday = (days + 3) % 7 (0 = Monday,
  since 1970-01-01 was a Thursday); thursday = days - weekday + 3; isoYear = civil year of `thursday`
  (days-to-civil, Howard Hinnant's algorithm); week = floor((thursday - dayOfYear0(isoYear, Jan 1)) / 7) + 1.
- `Games.Flip(myName, stake, pick, now, randomFunction) -> result|nil, errorKey`: validates (`stake` integer 1..MAX,
  `pick` "H"/"T"); `outcome = randomFunction() < 0.5 and "H" or "T"`; `won = outcome == pick`; updates a deep copy of my
  record (total, `weeks[PeriodKey(now)]`, prepend to `recent`, prune weeks to the 4 lexically largest keys, cap recent),
  commits with the new rev, returns `{ outcome, won, stake, net = won and stake or -stake }`. Totals are clamped at
  `MAXIMUM_TOTAL`/`MAXIMUM_COUNT` (a capped record stays valid). Error keys: `"stake"`, `"pick"`, `"readonly"` (db readonly).
- `Games.Sanitize(record) -> clean|nil`: allow-list copy, **one bad entry rejects the record** (Offers convention):
  name `IsSafeName`; rev `SafeInteger(0, Store.Horizon())`; totals: integers, `won,lost` in 0..MAXIMUM_TOTAL,
  `wins,losses` in 0..MAXIMUM_COUNT, consistency `wins <= won <= wins * MAXIMUM_STAKE` (same for losses/lost, unless clamped
  at the maximum); weeks: <= 4 keys, key matches `^(%d%d%d%d)%-W(%d%d)$` with year 2020..2100 and week 1..53, key not later
  than `PeriodKey(Horizon())` when the clock is usable; recent: array (consecutive 1..n), n <= 20, each `g` in 1..MAXIMUM_STAKE,
  `r` in {"W","L"}, `t` in 0..Horizon.
- `Games.Get(name)`, `Games.Put(record)` (store only if newer rev), `Games.Mine(myName)`, `Games.SanitizePersisted(sv)`
  (via `Utility.SanitizeMap`, key must equal `clean.name`), all like Offers.
- `Games.Simulate(count, now, randomFunction)`: fills `Games.simulated` (module table, never in `db`) with `count` fake
  records named `Sim<i>-Test`; `count = 0` clears. `Games.AllRecords()` = db records + simulated (simulated never returned
  by `Get`, so Sync can never answer with them).

### 4.4 Coin animation math (`Core/Play/CoinFlip.lua`, pure)
`CoinFlip.DURATION = 1.6` s, `CoinFlip.HEIGHT = 70` px, `CoinFlip.MINIMUM_WIDTH = 0.04`.
`CoinFlip.Pose(elapsed, outcome) -> { width = 0..1, y = px, face = "H"|"T", done = boolean }`:
- `x = clamp(elapsed / DURATION, 0, 1)`; eased progress `e = 1 - (1 - x)^3` (decelerating spin).
- half-turns `N = (outcome == "H") and 10 or 9` (the coin starts showing heads); angle `a = N * pi * e`.
- `width = max(MINIMUM_WIDTH, |cos a|)`; face index = `floor((a + pi/2) / pi) % 2` -> 0 = "H", 1 = "T".
- `y = HEIGHT * 4 * x * (1 - x)` (parabolic toss); `done = x >= 1`; at `done`: width 1, y 0, face = outcome.

### 4.5 Sync (protocol 2.3, additive minor; `docs/protocol.md` section 9)
- `HELLO` gets optional `grev` = my `GameRecord.rev` when > 0. In `_onHELLO`: like `orev`
  (`SafeInteger(grev, 1, Horizon)` -> `self:_pull("games", sender, grev, now)`, else note "games: invalid grev ignored").
- `RECORD_KINDS.games = { requestType = "WANTG", pullList = "wantedGames", label = "games", heldRevision = Games.Get(name).rev or 0 }`.
  Retry over GUILD and give-up come for free from `_retry`.
- `WANTG {names, via?}` -> `_onWANTG`: copy of `_onWANTO` with `Games.Mine` and answer `{ t = "GAMES", games = recordUnderAskedName(...) }`, kind `"games"`.
- `GAMES {games}` -> `_onGAMES`: `Games.Sanitize`, error on nil; author check `canonical(record.name) == sender`;
  `record.name = sender`; `Games.Put` -> `onChange("games")` + note "stored", else "not newer".
- Announce: a flip fires `GAMES_CHANGED`; `Communication.RequestHelloSoon()` sends a HELLO now if the last one is >= 30 s old,
  else sets `Communication.helloDueAt = lastHello + 30`; the 1 s pump sends it when due. Ten flips in a minute = at most 2-3 HELLOs.
- 2.2 peers: they ignore `grev` and drop `WANTG`/`GAMES` as unknown types (existing behaviour, `docs/protocol.md` section 2).

### 4.6 Animation helper (`UI/Animate.lua`)
Hybrid per the study: AnimationGroup for effects that end where they started, an OnUpdate tween for position/size changes.
- `Animate.Supported(animationType) -> boolean`: creates one group on a hidden probe frame, `pcall(group.CreateAnimation, group, type)`, cached.
- `Animate.FadeIn(region, duration)`, `Animate.Pulse(region, peakScale, duration)`, `Animate.Shake(region, pixels, count)`,
  `Animate.Glow(region, times)` (Alpha 0 -> 1 BOUNCE on an ADD-blend texture). Each: one cached group per region and
  effect (weak-keyed table); `Stop()` before replay (K7); Alpha uses `SetToFinalAlpha(true)` (K3); on unsupported type or
  any `pcall` error: apply the final state and call `onDone` synchronously.
- `Animate.Tween(key, duration, onStep(elapsed), onDone)`: one shared driver frame, `OnUpdate` set only while tweens
  exist; a new tween with the same key replaces the old one (calls nothing of the old). `Animate.speed` (default 1)
  divides durations' passage of time: `/tsd anim speed 0.25` = slow motion for tuning.
- The coin uses `Tween("coin", CoinFlip.DURATION, step)` where `step` applies `CoinFlip.Pose`: texture width =
  `COIN_SIZE * width`, `SetPoint` y offset = `y`, texture = face (no Translation/Scale animation, so K1/K2 do not apply).
  Landing: `Pulse(coin, 1.15, 0.25)`, `FadeIn(resultText, 0.3)`, win -> `Glow(glowTexture, 2)` + sound, loss -> `Shake(coinHolder, 4, 4)`.
- Coin textures (to be confirmed by the probe): heads `Interface\Icons\INV_Misc_Coin_01`, tails
  `Interface\Icons\INV_Misc_Coin_02`; glow `Interface\Buttons\UI-ActionButton-Border` with `SetBlendMode("ADD")`.

### 4.7 Games tab layout (`UI/GamesTab.lua`, tab area ~760 x 440)
- Left column (300 px): title "Coin flip"; coin holder frame (120 x 200, the coin rises inside it) with coin texture 96 x 96
  and glow texture; pick toggles "Heads"/"Tails" (selected one disabled, like the tab buttons); "Stake (gold)" numeric
  EditBox (max 6 letters, default = last stake, kept in `db.ui.lastStake`); "Flip" button; result FontString; grey note R9.
- Right column: "Last week's winner" line; scope toggles "This week"/"All time"; leaderboard list (rows: rank, name, net
  green/red, won, lost, "wins/losses"); below it "Recent flips" (8 visible rows, `name +250g  5m`).
- Flip click: read stake -> `Games.Flip(me, stake, pick, Utility.Now(), Api.Random)`; on error show the localized error
  in the result line; on success: `Events.Fire("GAMES_CHANGED")`, set `flipping = true`, disable Flip, start the coin tween;
  the leaderboard/feed refresh is **deferred** while `flipping` (so my new row does not spoil the result); at the end:
  effects, result text, `flipping = false`, enable Flip, `Refresh()`.
- Refresh on `DATA_CHANGED` kinds `games` and `games-local` (Window already routes `DATA_CHANGED` to `UI.Refresh` at `:1360`;
  `UI.Refresh` calls `GamesTab.Refresh()` when the games tab is shown).
- Window uses the widget helpers through `UI.Widgets = { CreateButton, CreateFontString, CreateScrollingList, CreateSelectableRow }`
  exported from `UI/Window.lua` (the local functions at `:78-190`), so GamesTab does not duplicate them.

### 4.8 Localization (keys = English text; deDE in brackets)
Games [Spiele], Coin flip [Münzwurf], Heads [Kopf], Tails [Zahl], Stake (gold) [Einsatz (Gold)], Flip [Werfen],
"You won {gold}" [Du hast {gold} gewonnen], "You lost {gold}" [Du hast {gold} verloren], "Enter 1 to {max} gold"
[Gib 1 bis {max} Gold ein], This week [Diese Woche], All time [Gesamt], Net [Netto], Won [Gewonnen], Lost [Verloren],
Flips [Würfe], Recent flips [Letzte Würfe], "Last week's winner: {name} ({gold})" [Gewinner der letzten Woche: {name} ({gold})],
No flips yet [Noch keine Würfe], "For fun only: no gold changes hands." [Nur zum Spaß: Es wird kein Gold bewegt.],
"{n}g" [{n}g]. Only game ids, week keys and numbers go on the wire.

### 4.9 Tests (new files register themselves: `tests/run.lua` picks up every `tests/test_*.lua`)
- `tests/test_games.lua`: PeriodKey vectors (2026-11-17 -> 2026-W47; 2026-12-31 -> 2026-W53; 2027-01-03 -> 2026-W53;
  2027-01-04 -> 2027-W01; 2021-01-01 -> 2020-W53; 2024-12-30 -> 2025-W01); Flip win/loss with injected random (0.1/0.9);
  stake rejects 0, -5, 1.5, 100001, nan, inf, "10"; pick rejects "X"; totals/weeks/recent updated; recent capped at 20
  newest; weeks pruned to 4; rev strictly increases with an unchanged clock; readonly db refuses; Sanitize rejects: 21
  recent, bad `r`, `g` 0 or > max, `won < wins`, `won > wins * max`, week key "2026-W54"/"26-W1"/future, 5 weeks, sparse
  recent array, non-table; Simulate never touches `db` and `Get` never returns a simulated record.
- `tests/test_coinflip.lua`: Pose at 0 (width 1, y 0, "H"); at DURATION and beyond: face = outcome for "H" and "T", done;
  width >= MINIMUM_WIDTH at 200 sample points; y max near x = 0.5 equals HEIGHT; face changes exactly N times over the curve.
- `tests/test_games_model.lua`: leaderboard sort (net, flips, name), scope week vs all, zero-flip players hidden, names escaped
  (`|` -> `||`), feed merge order and limit 15, previous winner (none / tie by flips / name).
- `tests/test_sync.lua` additions: HELLO with `grev` -> WANTG whisper; retry -> WANTG on GUILD with `via`; WANTG -> GAMES with my
  record; GAMES from another author rejected; older rev ignored; invalid `grev` noted; `onChange("games")` fired.
- `tests/test_hardening.lua`: PROTOCOL_MINOR 3 pinned; migration 3 -> 4 adds `games`; schema-5 data untouched (readonly).
- `tests/test_soak.lua`: extend one convergence scenario so 10 peers each flip and all leaderboards converge under 10% loss.
- `tests/test_games_ui.lua` (L3, recording widget stub like `tests/test_load.lua`): `Animate` falls back when
  `CreateAnimation` errors (final alpha set, `onDone` called once); `Tween` with the same key replaces; GamesTab builds;
  Flip disabled during the tween and enabled after; a failed `Games.Flip` shows the error and starts no tween.

## 5. Testing layers
| Layer | Covers | Command | Loop |
|---|---|---|---|
| L1 pure | R2, R3 (store-before-animate order), R5-R8, R10, RF1-RF5 | `luajit tests/run.lua` | seconds |
| L2 console | R4 curve feel, 50/50 distribution | `luajit tools/coinflip.lua` | seconds |
| L3 widget stubs | R1, R4 fallback, load order | `tests/test_load.lua`, `tests/test_games_ui.lua` | seconds |
| L4 in-game solo | R1, R4 visuals, R6-R9, probe P1-P8 | `tools/deploy.ps1`, restart once, then `/reload`; `/tsd anim`, `/tsd game sim 12` | ~10 s |
| L5 two clients | R5, R10 live | two guild members, one on 0.5.x for R10 | slow, last |

## 6. Tasks (in order; T1-T5 are pure and can be done without the game)
- [x] T1 (M): `Core/Play/Games.lua` (PeriodKey, Flip, Sanitize, Get/Put/Mine, SanitizePersisted, Simulate, AllRecords) +
  TOC + `tests/run.lua` module list + `tests/test_games.lua`. Verify: L1.
- [x] T2 (S): `Core/Play/CoinFlip.lua` + `tests/test_coinflip.lua` + `tools/coinflip.lua`. Verify: L1, L2.
- [x] T3 (S): Store schema 4 (+ migration, persisted re-validation) + `tests/test_hardening.lua` additions. Verify: L1.
- [x] T4 (M): Sync protocol 2.3 (`grev`, WANTG, GAMES, RECORD_KINDS.games), `PROTOCOL_MINOR = 3` (Init + tests/run.lua),
  `RequestHelloSoon` + pump check + `GAMES_CHANGED` event, `Api.Random`; tests in `test_sync.lua`, `test_soak.lua`. Verify: L1.
- [x] T5 (S): Model rows (leaderboard, feed, previous winner) + `tests/test_games_model.lua`. Verify: L1.
- [ ] T6 (S) (probe built; BLOCKED on the user running it): `/tsd anim` probe in `UI/DevProbe.lua` answering P1-P8 of the study + coin/glow texture check; prints one line
  per question. Then **BLOCKED on the user**: run it in game, send the chat output (and screenshots for P5/P8). Record answers
  in `docs/api-findings.md` and the study. Verify: L4.
- [x] T7 (M) (built before the probe answers, see Decisions; revisit after T6): `UI/Animate.lua` shaped by the T6 answers (if P3/P4 show built-in bugs, swap the affected effect to the tween
  or decide on LibAnimate and log a DEVIATION) + `tests/test_games_ui.lua` Animate part. Verify: L3.
- [x] T8 (S): `UI/Window.lua` tab list refactor + `UI.Widgets` export; no behaviour change for the 4 existing tabs. Verify: L3, L4 click through.
- [x] T9 (M): `UI/GamesTab.lua`, locale strings (enUS + deDE), TOC, `deploy.ps1`, `Api.CoinSoundKit`; GamesTab part of
  `tests/test_games_ui.lua`. Verify: L3, then L4.
- [x] T10 (S): `/tsd game sim <n>` and `/tsd anim speed <x>`. Verify: L1 (simulated never sent/stored), L4.
- [x] T11 (S): docs: `docs/protocol.md` section 9 (2.3 + schema 4), README (Games tab, "for fun only"), CHANGELOG, `docs/status.md`, `doc.md`. Verify: read-through.
- [x] T13 (L): slot machine: `Core/Play/Slots.lua`, `UI/SlotMachine.lua`, game selector + per-game boards in
  `UI/GamesTab.lua`, `slots` record section; tests `test_slots.lua` (8), `test_games_ui.lua` (+3), `test_load.lua`.
  Verify: L1, L3, then L4 (look and feel in game).
- [ ] T12: in-game checklist in `verify.md` with the user (L4), then two clients (L5); `review-talentshare` on the change
  (it touches network, store and display of peer text) before `done`.

## 7. Review Focus (failure modes a happy-path test would miss)
1. RF1: forged or broken record (oversized recent, negative/huge numbers, `won < wins`, future week, sparse array, wrong
   author) -> whole record rejected, nothing shown, no error spam. Pinned by: T1, T4.
2. RF2: week rollover / clock edge: a flip at Sunday 23:59:59 UTC lands in that week; peers' records with next week's key up to
   1 day ahead are accepted; ISO year boundaries (W53, W01 in the previous December). Pinned by: T1 vectors.
3. RF3: `/reload` or window close mid-animation, double click on Flip, flip while db is readonly -> no lost, double or
   re-rolled flip; readonly refuses with a message. Pinned by: T1 (store before animate), T9 (button state), T7 (tween replace).
4. RF4: compatibility: 2.2 peer, schema-4 file in 0.5.x, record from a newer 2.x minor with extra fields (ignored). Pinned by: T3, T4.
5. RF5: flip spam -> HELLO announces coalesced (<= 1 per 30 s + due one); simulated players never in `db`, never sent. Pinned by: T4, T10.
6. RF6: animation type missing / AnimationGroup quirks (K1-K7 of the study) -> final state correct, no Lua error. Pinned by: T6, T7.

## 8. Cross-cutting checklist
- [x] Protocol: additive minor 2.2 -> 2.3 (`grev`, `WANTG`, `GAMES`); major unchanged; `docs/protocol.md` section 9.
- [x] Stored data: `Store.SCHEMA` 3 -> 4, `MIGRATIONS[3]` adds `games = {}`; re-validated on every load; downgrade guard unchanged.
- [x] Trust model: only my own record is authored by me (sender check); peer numbers bounded and consistency-checked, not
  trusted as true; names escaped in Model. Results are self-reported (Non-goals).
- [x] Localization: only short field names, week keys, numbers, "W"/"L" on the wire; UI text via `addon.L` (4.8).
- [x] Load order: 4.1 note; TOC + generated dev TOC + `tests/run.lua` module list stay in the same order.
- [x] Packaging: `tools/coinflip.lua` in ignored `tools/`; `Core/Play`, `UI/Animate.lua`, `UI/GamesTab.lua` packaged; dev commands gated by `IS_DEVELOPMENT_BUILD`.
- [x] Tests: 4.9.
- [x] Docs: T11.

## 9. Decisions (newest last)
- 2026-11-17: Scope = base + tiny demo game; real game later. (user)
- 2026-11-17: Game shape = async guild-wide; open information only; theme later. (user)
- 2026-11-17: Turn/real-time multiplayer out: transport paced at ~0.9 msg/s (burst 5). (design)
- 2026-11-17: Animations studied before UI code; behaviour questions P1-P8 measured in game, not assumed. (user + design)
- 2026-11-17: Demo game = animated coin flip with an entered gold stake; every win/loss amount appears on the leaderboard. Replaces "Rune Flip"; shared seed and replay verification dropped. (user)
- 2026-11-17: Opponent is "the house" (solo flip, 50/50, 1:1 payout); the pick does not change odds and is not stored. (design default)
- 2026-11-17: Gold is bookkeeping only; the addon never reads or moves gold (gold transfer is not automatable by addons, and the feature stays a fun ledger). (design default, see Open questions)
- 2026-11-17: Results are self-reported (guild trust model), validated for shape, bounds and consistency only. (design)
- 2026-11-17: Coin motion = pure `CoinFlip.Pose` driven by an OnUpdate tween (unit-testable, real layout, avoids K1/K2); effects via AnimationGroup. (design)
- 2026-11-17: Leaderboard periods = ISO week in UTC + all time; record keeps 4 weeks and 20 recent flips. (design)
- 2026-11-17: wowless not adopted (Forever support unknown). (design)
- 2026-11-17: Implementation deviations (all small, code is the truth): (implementer)
  - T7 built before the T6 answers, because every effect already falls back to its end state; the probe can only make an
    effect nicer, not make the tab unusable. Revisit `UI/Animate.lua` when the `anim P1..P8` lines arrive.
  - Sync/soak tests live in a new `tests/test_games_sync.lua` (own peer helper on a realistic clock: week keys before 2020
    are invalid) instead of additions to `test_sync.lua`/`test_soak.lua`. The soak's quiet phase is 6 x 60 s, long enough
    for the pull retry schedule.
  - Ten flips in a minute send 3 HELLOs (0 s, 30 s, 60 s), not 2: flips after the second HELLO need one more announce.
  - Extra API: `Games.PreviousPeriodKey`, `Games.IsPeriodKey`, refusal `"name"` (my name unknown), `Api.PlaySound`,
    `Animate.ShakeOffsets/IsTweening/FinishTween`, `UI.CurrentTab`, `UI.TabDefinitions` (a function, so locale keys stay
    literal for `tests/test_locale_files.lua`), `UI.Widgets.TimeAgo`.
  - `Store.Clean`, `Store.ResetPeerData` (returns `games`), `Store.Prune` and `Store.CanonicalizeStoredNames` treat
    `games` like `offers` (not in the original file table).
  - The window builds the Games tab inside `Log.Protected`, so a broken tab cannot stop the other four.
- 2026-11-17: Stakes in gold/silver/copper: every amount is copper (1c..100 000g = 1e9c, totals <= 2e13c, exact in doubles
  and in the codec's `%.17g`); flip field `g` renamed to `c`, so dev records from the gold draft fail validation and are
  dropped (2.3 was never released). UI: three boxes with coin icons, `Model.MoneyText` ("1g 50s 25c"). (user)
- 2026-11-17: Second game: slot machine, 3 reels x 3 rows, 5 paylines (rows + diagonals), animated wins; a sub-section of
  the Games tab chosen by a game selector; its own leaderboard built by the same Model functions with a game key. (user)
  Design: the record gets an optional `slots` section (same shape as the coin section, entries `{c, n, t}`), so sync needs
  no new message; `Games.Section`, `Games.RecordPlay`, `Games.EntryNet`; Model leaderboard/feed/winner take `gameKey`.
  Paytable 3/5/6/9/15/30/75 on a 35-symbol strip -> 93.8% return, 11% of spins win. Reels are cropped per frame by size
  and texture coordinates (no clipping API needed); paylines use `CreateLine`, else a rotated texture. (implementer)
- 2026-11-17: Coin drawn as a two-sided 2.5D coin (layered masked textures, end-over-end flip); heads = my portrait,
  tails = a crown. A 3D model was not used (no known coin model on Forever). (user feedback)

## 10. Open questions (none blocks T1-T5)
- Should the stake be settled in real gold between players later (would need a PvP challenge + manual trade)? Default: no. (needs: user)
- Local UI preview ("estimation UI"): run the real `UI/*.lua` against an emulated widget API with a renderer; LÖVE 2D
  (LuaJIT, same Lua 5.1) recommended over Python + lupa + pygame. Proposed as its own feature 015. (needs: user)
- Optional: export Blizzard UI code/art (`ExportInterfaceFiles code|art` at the login console, game started with `-console`)
  for animation examples and preview art. (needs: user)

# 051 Daily casino win cap and smaller Survivor payouts: spec

- Status: done
- Created: 2026-11-27
- Target version: GuildGames 0.14.0 (protocol 1.9, schema 3)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
The house games (coin flip, slots, Survivor) can raise a player's balance by at most 500g per day, and Survivor pays
small multipliers (105% to 140%) instead of 2x to 64x.

## Why (measured, see log.md 2026-11-27)
- A bot that picks cards blindly survives 60 s in ~52% of runs, 90 s ~17%, 120 s ~5%, but 1-2% of runs never die
  (one reached the 15 minute simulation limit). In endless mode those runs pay 64x, so the average run returned
  +3.35x its stake. With stakes up to 100 000g, one run outweighs every other income and every shop price (max 1 500g).
- Slots (94% return) and coin (100%) can still produce a huge single win at a 100 000g stake.

## Requirements
- R1: One shared **daily win limit** of `Wallet.DAILY_WIN_CAP` = 500g for coin, slots and Survivor: the money these
  games add to the balance on one day (00:00 UTC, the server day Companion Dash uses) is at most +500g **net**
  (wins minus losses that day).
- R2: **Playing never stops at the limit.** Any stake the balance covers is still allowed (and 1c, and free play, R8).
  A win is paid only up to the limit left (`remaining = max(0, CAP - todayNet)`; todayNet may be negative after losses); the rest is not paid. Losses always
  cost the full stake, so after the limit is reached a staked play can only lose or break even.
- R3: **The record stays true, the wallet clamps.** The play is stored in the game record with its real result (the
  leaderboards and the old validation are unchanged for coin and slots). The part of a win above the limit is booked as
  a wallet ledger entry of kind `"cap"` (negative), so the balance rises by exactly the paid part, and the journal
  explains it line by line.
- R4: The limit is shared: a big win in one game uses it up for the other two the same day. A loss the same day frees
  room again (net).
- R5: **Survivor pays a percent of the stake** (total returned, stake included): 60 s 105%, 90 s 110%, 120 s 120%,
  180 s 140%; endless 105% at 1:00, +5% per further minute, capped at 130% (6:00). Net of a win =
  max(1, floor(stake x (pct - 100) / 100)).
- R6: New Survivor plays are stored in a **new record section** `tower` (same shape, own validation: win net
  1..stake). The old `survivor` section is kept as history: it still counts in the balance, gets no new plays and is
  no longer shown as a leaderboard. Old clients (protocol <= 1.8) ignore the unknown `tower` key, so updated players
  stay visible to them.
- R7: While a Survivor stake is pending (run in progress), coin and slots refuse with reason `"run"`, so the limit
  left at the start of a run cannot shrink during it. A pending run left by a /reload is settled with the new rules
  and the limit; a 0.13 pending mark with the old `factor` field is converted to the percent of the same minute
  (factor 64 -> 130%, never 64x).
- R8: **Free play:** every house game can be played with no stake: nothing is stored in the record or the wallet,
  the result is only shown.
- R9: **No endless build:** difficulty keeps rising so every run ends; in a seeded simulation of 200 runs with three
  card strategies no run lasts past 8:00.
- R10: Hovering the pool amount in the window header shows the balance breakdown and the daily win limit in detail
  (won today, not paid today, left, when it starts again, why it exists). Each stake row (coin, slots, Survivor) shows a
  "!" right of the boxes while the typed stake deserves a warning, with the reason on hover: red = more than the pool,
  orange = the limit is reached or even the smallest win of that game would be cut, grey = big wins would be cut or
  free play; the boxes take the colour (red/orange). A cut win says "You won X, paid Y (daily win limit)." or, at 0 left,
  "You won X, but the daily win limit is reached: nothing paid."; free plays say "Free play: ..."; multipliers read
  "x1.05". enUS and deDE (decimal comma).

## Non-goals
- Arena wagers and bets (player money moving between players, not house money), Companion Dash (own 50g/day cap),
  catch rewards, weekly payouts, dev gifts: not counted, not limited.
- No change to coin or slots odds or MAXIMUM_STAKE (the daily limit bounds the gain).
- Protection against edited SavedVariables (trust model unchanged: the wallet is local bookkeeping).
- Leaderboards keep showing real game results; they can show more won than was paid out (R3).

## Design
- Files touched:
  - `Core/Data/Wallet.lua` (changed): `DAILY_WIN_CAP`, `CASINO_GAMES` += `tower`, local day state
    `db.caught.casinoDay = { d, n }` (n = paid net today), `WinRemaining(now)`, `BookCasino(myName, net, now, game)`:
    adds the paid part to the day state and, when net > remaining, appends a `"cap"` ledger entry for the excess
    (counted in `ledger.spent`, so `Breakdown`/`Balance` stay one formula); returns the paid net. `SanitizePersisted`
    cleans `casinoDay`.
  - `Core/Data/Games.lua` (changed): every kind names its record `field`; game `survivor` now lives in field `tower`
    (`minimumWinNet = 1`, `maximumWinFactor = 1`), the old field `survivor` is the game `legacySurvivor` (validated with
    the old 2x..64x bounds, in `Games.STORED` but not in `ORDER`: no leaderboard); per-kind minimum in `sanitizeEntry`;
    `Flip` and `RecordPlay` call `Wallet.BookCasino` after storing and return the paid net; refusal `"run"` while a
    Survivor stake is pending (coin, slots).
  - `Core/Minigames/Slots.lua`, `UI/GamesTab.lua` (coin): free play path (stake 0: draw and show, no record, no wallet).
  - `Core/Minigames/Slots.lua` (changed): result carries `paid` (booked net) next to `net`.
  - `Core/Minigames/Survivor.lua` (changed): `TARGETS[i].pct`, `EndlessPercent(time)`, `Net`, pending mark `pct`
    (old `factor` converted: minutes = log2(factor), pct = min(130, 100 + 5 x minutes)), records under `tower`,
    free play (stake 0: no pending mark, nothing booked), `Difficulty` ramps harder after 4:00 (R9, curve chosen in T5
    with the simulation).
  - `Core/View/Model.lua`, `UI/GamesTab.lua`, `UI/SlotMachine.lua`, `UI/SurvivorArena.lua` (changed): limit line,
    warnings, cut-win message, `"run"` refusal text, percent labels ("x1.05" style), free play control.
  - `Locales/enUS.lua`, `Locales/deDE.lua` (changed): new strings.
  - `Core/Base/Init.lua`: `PROTOCOL_MINOR = 9` (record section `tower`).
- Data shape change: local only: `db.caught.casinoDay = { d = <utc day>, n = <paid net copper> }`, ledger kind
  `"cap"`, pending mark `db.ui.survivorPending.pct`. No schema bump (new optional fields, sanitized on load).
- Message shape change: additive: record section `tower` (protocol 1.9). Old clients drop unknown keys
  (`Games.Sanitize`: "Unknown fields ... are dropped, not fatal"), so no record is rejected.
- Pure logic lives in Wallet, Games, Slots, Survivor; no new WoW calls.

### Worked example (limit 500g)
| Time | Play | Paid net before | Left | Record | Wallet |
|---|---|---|---|---|---|
| 10:00 | coin, 200g, win | 0 | 500 | +200g | +200g |
| 10:05 | slots, 100g, 9x line = +800g | 200 | 300 | +800g | +800g, `cap` -500g = **+300g** |
| 10:06 | coin, 50g, win | 500 | 0 | +50g | +50g, `cap` -50g = **0** |
| 10:07 | coin, 50g, loss | 500 | 0 | -50g | -50g, paid net now 450, **50g left** |
| 10:08 | coin, 0 (free play) | 450 | 50 | nothing | nothing |

## Tasks
- [x] T1 (S): Games: per-kind `minimumWinNet`, `tower` kind, `survivor` out of `ORDER`. Verify: test_daily_cap "tower
  validation accepts net 1..stake, rejects 0 and stake+1"; old `survivor` data still loads; a record with `tower`
  passes the 1.8 rules with the key dropped.
- [x] T2 (M): Wallet day state, `WinRemaining`, `BookCasino` with the `"cap"` entry, sanitize. Verify: test_daily_cap
  "limit is shared across games", "win above the limit pays the rest only", "loss frees room", "new UTC day resets",
  "balance = grant + casino net - cap entries", "garbage casinoDay is repaired".
- [x] T3 (M): Flip/RecordPlay/Slots book through `BookCasino`, `"run"` refusal, free play for coin and slots.
  Verify: test_daily_cap "slots result shows paid", "coin and slots refused while a run is pending", "free play
  stores nothing"; test_slots / test_games / test_wallet green.
- [x] T4 (M): Survivor percent payouts, `tower` section, pending `pct` + old `factor` conversion, free play.
  Verify: test_survivor "targets pay 105..140%", "endless +5% per minute capped at 130%", "0.13 pending factor 64
  pays 130%", "1c stake wins 1c", "free run stores nothing".
- [x] T5 (M): Difficulty ramp after 4:00. Verify: test_survivor "seeded 200 runs x 3 strategies: none past 8:00";
  60 s survival rate logged before/after.
- [x] T6 (M): UI + locales (limit line, warnings, cut-win message, run refusal, percent labels, free play).
  Verify: test_games_ui / test_store_and_locale (every new key in both locales); in-game screenshots.
- [x] T7 (S): protocol 1.9, `docs/protocol.md`, README, CHANGELOG, RELEASE_NOTES draft (EN/DE). Verify: test_load.
- [x] T8: in-game check with the user (limit line, a cut slots win, limit reached message, Survivor percent labels,
  free play, an old 0.13 client still lists an updated player).

## Review Focus (failure modes a happy-path test would miss)
1. RF1: a slots jackpot far above the limit -> record +full win, wallet +remaining exactly, one `cap` ledger entry,
   `Balance` matches `Breakdown` line by line. Pinned by: T2/T3.
2. RF2: an updated player's record with a 1.05x Survivor win reaches a 0.13 peer -> the peer keeps the record (only
   the unknown `tower` key is dropped). Pinned by: T1.
3. RF3: /reload mid-run; on load the pending run is settled with the limit of the settle day. Pinned by: T4.
4. RF4: a 0.13 pending mark `{ factor = 64 }` -> paid 130%, not 64x. Pinned by: T4.
5. RF5: 1c stake at 105% -> net 1, never 0 (an invalid entry would make peers drop the whole record). Pinned by: T4.
6. RF6: the day changes between two plays or during a run -> the day state resets once, the settle uses the new day.
   Pinned by: T2.
7. RF7: the ledger keeps only the newest 60 entries -> `ledger.spent` (not the entry list) carries the cap total, so
   pruning never changes the balance. Pinned by: T2.

## Cross-cutting checklist
- [x] Protocol: additive bump to 1.9 (new optional record section `tower`); old peers ignore it, no record rejected.
- [x] Stored data: no `Store.SCHEMA` bump; new optional local fields `caught.casinoDay`, ledger kind `cap`,
  `ui.survivorPending.pct`, sanitized on load; old pending `factor` converted.
- [x] Trust model: the `tower` section is allow-list validated like the other games; the daily limit is local
  bookkeeping (an edited SavedVariables file can bypass it, same as the balance today).
- [x] Localization: only numbers stored/sent; new UI text through `Text[...]` in enUS and deDE.
- [x] Load order: no new file.
- [x] Packaging: no new file; `features/` stays excluded.
- [x] Tests: new `tests/test_daily_cap.lua`; `test_survivor.lua`, `test_slots.lua`, `test_games.lua`,
  `test_wallet.lua` updated.
- [x] Docs: README, CHANGELOG, docs/protocol.md, doc.md; RELEASE_NOTES are written at release (release skill).

## Decisions (user answers and design choices, newest last)
- 2026-11-27: Survivor multipliers about 1.1x, "way stricter" (user).
- 2026-11-27: one daily win limit shared by the house games (user asked for "a gold limit win per day").
- 2026-11-27: new Survivor plays go into a new `tower` section instead of changing the `survivor` validation (design):
  peers reject a whole record when one entry fails validation, so lowering the minimum win in place would hide every
  updated player from not-yet-updated guild members.
- 2026-11-27: limit 500g per day (user, Q1).
- 2026-11-27: "+500 per day; if you decide to bet more after that you won't be gaining anything; you can still play
  without betting anything or 1c" (user, Q2): net limit, no refusal at the limit, wins above it are not paid, free play
  and 1c stay available. Design consequence: the record keeps the real result and the wallet books the excess as a
  `cap` entry (R3), so coin and slots keep their record format.
- 2026-11-27: Survivor table "even smaller": 105 / 110 / 120 / 140%, endless max 130% (user, Q3).
- 2026-11-27: block coin and slots while a Survivor run is pending (user, Q4).
- 2026-11-27: the old `survivor` leaderboard disappears; its history still counts in the balance (design default, not
  asked; easy to revisit).
- 2026-11-28: R9 is met by a "frenzy": from 4:00 monster health and damage grow 2.5x per minute (`Survivor.FRENZY_FROM`, `FRENZY_GROWTH`; 1.8x still let one of 600 simulated runs reach 8:57).
- 2026-11-28: R10 is met by a header line plus the result text; no separate warning before a play, and no extra cash-out hint in endless mode (deviation, see log).

## Open questions
- none

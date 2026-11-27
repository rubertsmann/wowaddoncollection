# Daily casino win cap and smaller Survivor payouts

Status: implemented, verifying | Since version: unreleased (target 0.14.0, protocol 1.9) | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
The coin flip, slots and Survivor together can raise a player's money pool by at most 500g per day (UTC, net: losses
that day make room again). Play never stops: past the limit a win just pays nothing more. Survivor pays small bonuses
(x1.05 to x1.4, endless up to x1.3) instead of x2 to x64, and from 4:00 the monsters grow so fast that every run ends.
A stake of 0 is free play in all three games.

## How to use
- UI: the header shows "Win limit today: X left" (or "Daily win limit reached") right of the pool. A cut win reads
  "You won X, paid Y (daily win limit)." Empty stake boxes (0) play for free.
- Commands: `/gg caught wallet` prints the casino net per game (old survivor runs separately), the day's paid net and the
  limit left, and the ledger with `cap` lines.

## How it works
- Data (SavedVariables, local only): `caught.casinoDay = { d = UTC day, n = paid net copper }`; ledger kind `cap`
  (spent) for the part of a win above the limit; `ui.survivorPending.pct` (a 0.13 `factor` is converted on settle).
- Messages: record field `tower` (survivor plays, a win nets 1c..stake), protocol 1.9, additive: older peers drop the
  unknown field and keep the record. The old field `survivor` is still sent and validated (game `legacySurvivor`).
- Modules: `Core/Data/Wallet.lua` (CasinoDay, WinRemaining, BookCasino, sanitize), `Core/Data/Games.lua` (kind
  fields, per-kind minimum win, RunRefusal, Flip/RecordPlay book through the wallet and return `paid`),
  `Core/Minigames/Slots.lua` and `Survivor.lua` (free play, percent payouts, frenzy), `Core/View/Model.lua`
  (PercentText, WinText, WinLimitText, `run` refusal text), UI in GamesTab, SlotMachine, SurvivorArena.

## Localization
New strings in enUS (source) and deDE; the decimal mark of the multipliers is a locale string (`{whole}.{fraction}`,
German `{whole},{fraction}`). Only numbers are stored or sent.

## Limits and known issues
- Leaderboards show real game results, so a player can show more won than the pool paid.
- There is no warning before a play whose possible win is above the limit left; the header line and the result text
  carry it.
- The limit is local bookkeeping: an edited SavedVariables file can bypass it (same trust model as the pool).
- The day is UTC, not the realm's reset time.

## Changelog line
- See CHANGELOG.md "Unreleased" (feature 051).

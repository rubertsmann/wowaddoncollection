# GuildGames wire protocol and stored data

Protocol **1.0**, schema **1** (0.1.0). Source of truth in code: `Core/Init.lua` (versions, prefix), `Core/Sync.lua`
(messages), `Core/Games.lua` (record, validation), `Core/Store.lua` (schema). The transport, chunk header, compatibility
rules, guild gate and record-pull engine are LibGuildSync-1.0's (`Libs/LibGuildSync`, documented in the libguildsync repo).
Tests: `tests/test_games_sync.lua`, `tests/test_games.lua`, `tests/test_store_and_locale.lua`.

## 1. Transport
- Addon-message prefix `GGames` (dev build `GGamesDev`), channels `GUILD` and `WHISPER` only, guild members only.
- Chunk header `<major>.<minor>|<id>|<idx>|<total>|<part>` (`1.0|...`). The payload carries `v = 1`. A peer with another
  major is dropped before anything is buffered, with one notice per session.
- The send budget (burst 5, 0.9 per second) is **shared** with every other addon that embeds LibGuildSync (TalentShare).

## 2. Messages
The names are kept from TalentShare 0.6.0 (protocol 2.3), where the games started. They now run on their own prefix and
protocol, so TalentShare and GuildGames never read each other's messages.
- `HELLO {grev?, login?}`: broadcast on GUILD (a whispered reply to a `login` HELLO). `grev` = my record's `rev`, left out
  while I have no record.
- `WANTG {names, via?}`: "send me your record". Whisper first, repeated on GUILD with `via = "GUILD"` after 45 and 90 s,
  given up after 180 s and restarted by the owner's next HELLO a minute later. Only the receiver's own name is answered.
- `GAMES {games}`: the record. It is accepted only from its author (canonical name equal to the sender) and only when it
  is newer than the held one.
- Announce: a play sends a coalesced HELLO, at once when the last one is 30 s old, otherwise one when the 30 s are over.
  Every 15 minutes an anti-entropy HELLO goes out.

## 3. Record, validation, stored data
- **Record** (`Core/Games.lua`), one per character, authored only by that character, replaced as a whole by a newer `rev`:
  `{ name, rev, total = {won, lost, wins, losses}, weeks = { ["YYYY-Www"] = {won, lost, wins, losses} } (<= 4 keys),
  recent = { {c = stake, r = "W"|"L", t = time} } (<= 20, newest first) }`. Amounts are in **copper** (1g = 10 000c),
  bookkeeping only (no real gold is read or moved). Week keys are ISO 8601 weeks in UTC.
- **Slot machine section (optional) `slots = { total, weeks, recent }`:** same shape and limits as the coin section, but
  recent entries are `{c = stake, n = net, t}` with `n = -c` (a loss) or `c <= n <= c * 374` (a win; 5 paylines x 75 is the
  highest multiplier). Win totals may reach `wins * 1e9 * 374`. Every game has its own section and its own leaderboard;
  a client that does not know a section drops it (allow-list copy).
- **Survivor section (optional, 0.1.0) `survivor = { total, weeks, recent }`:** same shape as the slot section, with
  `n = -c` or `c <= n <= c * 63` (endless mode doubles the payout every minute up to 64x the stake). A run's outcome depends on the player's item
  picks, so it cannot be decided up front: the stake is kept as `ui.survivorPending = { name, c, t }` while a run is open
  and booked at the next login if the run never ended: a loss, or for an endless run the factor it had reached
  (`factor`, 2..64; local only, never sent).
- **Validation (whole record rejected on one bad entry):** safe name equal to the sender (canonical form); `rev` in
  `[0, now + 1 day]`; totals integers with `won, lost <= 2e13` copper, `wins, losses <= 1 000 000` and consistent
  (`wins <= won <= wins * 1e9`, same for losses); week keys `YYYY-Www` with year 2020..2100, week 1..53, not after the week
  of `now + 1 day`; `recent` a dense array of at most 20 flips with `c` in 1..1e9 (1c to 100 000g), `r` "W"/"L", `t` in `[0, now + 1 day]`.
  Results are self-reported (trust model): bounds and consistency are checked, truth is not.
- **Stored data (schema 1, `GuildGamesDB`):** `games[name]`, re-validated on every load,
  emptied by `/gg clean`, pruned with players who left the guild. A newer schema on disk is left untouched (read-only session).
- **Display:** names are escaped in `Core/Model.lua`. Dev-build simulated players (`/ggd game sim`) live outside the
  database and are never sent.


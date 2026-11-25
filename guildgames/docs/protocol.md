# GuildGames wire protocol and stored data

Protocol **1.5**, schema **2** (1.5 since the item marks; 1.4 since the runner section; 1.3 since arena counter offers; 1.2 since the companion arena, 0.3.0; 1.1 since 0.2.0; 0.1.0 was protocol 1.0, schema 1). Source of truth in code: `Core/Base/Init.lua` (versions, prefix), `Core/Net/Sync.lua`
(messages), `Core/Data/Games.lua` (record, validation), `Core/Data/Store.lua` (schema). The transport, chunk header, compatibility
rules, guild gate and record-pull engine are LibGuildSync-1.0's (`Libs/LibGuildSync`, documented in the libguildsync repo).
Tests: `tests/test_games_sync.lua`, `tests/test_games.lua`, `tests/test_store_and_locale.lua`.

## 1. Transport
- Addon-message prefix `GGames` (dev build `GGamesDev`), channels `GUILD` and `WHISPER` only, guild members only.
- Chunk header `<major>.<minor>|<id>|<idx>|<total>|<part>` (`1.0|...`). The payload carries `v = 1`. A peer with another
  major is dropped before anything is buffered, with one notice per session.
- The send budget (burst 5, 0.9 per second) is **shared** with every other addon that embeds LibGuildSync (ProfessionShare).

## 2. Messages
The names are kept from TalentShare 0.6.0 (protocol 2.3), where the games started. They now run on their own prefix and
protocol, so ProfessionShare and GuildGames never read each other's messages.
- `HELLO {grev?, login?}`: broadcast on GUILD (a whispered reply to a `login` HELLO). `grev` = my record's `rev`, left out
  while I have no record.
- `WANTG {names, via?}`: "send me your record". Whisper first, repeated on GUILD with `via = "GUILD"` after 45 and 90 s,
  given up after 180 s and restarted by the owner's next HELLO a minute later. Only the receiver's own name is answered.
- `GAMES {games}`: the record. It is accepted only from its author (canonical name equal to the sender) and only when it
  is newer than the held one.
- Announce: a play sends a coalesced HELLO, at once when the last one is 30 s old, otherwise one when the 30 s are over.
  Every 15 minutes an anti-entropy HELLO goes out.

## 3. Record, validation, stored data
- **Record** (`Core/Data/Games.lua`), one per character, authored only by that character, replaced as a whole by a newer `rev`:
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
- **AZEcaught section (optional, protocol 1.1, feature 018) `caught = { c?, weeks }`:** my current companion and my
  weekly peaks. `c = { npc, n, lvl, cls, disp, h, hu, th, af, en, sl?, fs }`: NPC id (1..2^31-1), NPC name (client text,
  at most 48 bytes, UTF-8, no control characters), level 1..200, classification `normal|elite|rare|rareelite|worldboss`,
  display id (0 = unknown), hearts (-1e6..1e6), the four needs 0..100, asleep `true` or absent, fed streak.
  `weeks = { ["YYYY-Www"] = peak companion level }` (<= 4 keys, same key rules as above). Unlike the casino sections a bad
  `caught` section is **dropped alone** (the record stays). Protocol 1.0 peers drop the unknown key (allow-list copy), so
  the change is additive (minor 1.1). It is written by `Games.SetSection` with a new `rev` (at most every 30 s while the
  companion changes, at least every 5 min, at once after select/care/death) and announced like a play.
- **Arena section (optional, protocol 1.2, feature 020) `arena = { w, l, ch, an, bt }`:** my arena wins and losses
  (0..1e6) and my open entries, each table at most 20 entries keyed by the fight id `<challenger>#<time>` (a safe name,
  at most 80 bytes). `ch[id] = {to, at, wg, f, wd?}` (`wd`: stopped at, optional): my challenges only (the id names me, `at` equals the id's time, `to`
  is another safe name, wager 0..1000g in copper). `an[id] = {ok, at, f?}`: my answer to someone else's challenge
  (`f` required when `ok`). `bt[id] = {s = "a"|"b", c, o, at}`: my bet (10s..500g, odds 110..1000 hundredths).
  Fighter `f = {npc, n, cls, disp, ty, al, atk, def, spd, vit, ab}`: NPC id, name (<= 48 bytes), classification,
  display id, creature type 0..100, arena level 1..50, the four stats 1..1e6, ability (`rend|breath|burn|surge|smash|
  drain|focus|barrier|strike`). A bad `arena` section is dropped alone. Every client computes a fight from the two
  snapshots and the id (`Arena.Fight`, deterministic) and settles only its own pool; an answer counts only from the
  challenged player within 24 h of the challenge. Written by `Games.SetSection("arena")`; 1.1 peers drop it.
- **Arena counter offers (protocol 1.3, feature 032):** `co[id] = {wg, at, f}` in the challenged player's arena section:
  a counter offer (wager 0..1000g, the time, the counter's fighter) instead of an `an` answer; it counts when made within
  24 h of the challenge and before a stop. The challenger answers it in its own `ch[id]` with `ca` (accepted at) or
  `cd` (declined at), at most one, within 24 h of the counter. With `ca` the fight uses `co.f`, `co.wg` and
  `fightAt = ca + 5 min`. A 1.2 peer copies only `ch/an/bt` (it ignores `co`, `ca`, `cd` and keeps the section), so it
  sees the challenge as unanswered and cannot bet on a counter fight. Local only (never sent): `watched[id]`, the
  fights whose replay I watched; a fight's money is settled after that or 24 h after the fight time.
- **Runner section (optional, protocol 1.4, feature 035) `runner = { b, n, weeks, recent }`:** my best distance in
  meters (0..1e6), my run count (0..1e9), `weeks = { ["YYYY-Www"] = best meters }` (<= 4 keys, same key rules as above),
  `recent = { {d = meters, g = gold paid 0..50, t} }` (<= 10, newest first). A bad section is dropped alone (the record
  stays); 1.3 peers drop the unknown key (allow-list copy). Written by `Games.SetSection("runner")` after every finished run.
  Local only: `runner.day` and `runner.paid` (the 50g daily cap, server day = time / 86400).
- **Item marks (protocol 1.5, feature 036), all optional and additive:**
  - Arena fighter `f.bf`: the ids of the arena buffs (War Paint, Bark Skin, Swift Tonic) used for this fighter.
    - The list holds known `arenaBuff` items only, no repeats, at most 3; anything else is dropped from the list and the fighter stays.
    - The buffs are already part of `atk`/`vit`/`spd`, so a 1.4 peer that drops `bf` computes the same fight.
  - Runner section `bi = 1`: the best run used an item.
  - Runner recent entries and survivor play entries `it = 1`: the run used an item (Dash Shield, Head Start, Survivor Bomb).
  - Any other value of `bi` or `it` counts as unmarked. Peers on 1.4 or older drop these fields (allow-list copy).
- **Money pool (local only, never sent):** `balance = 20g + casino net (coin + slots + survivor) - pending survivor stake
  + ledger.earned - ledger.spent` (runner payouts are ledger earnings, kind `runner`). Every casino play START (flip, spin, survivor run) is refused with `funds` when the stake
  is above the balance; settling a run never is.
- **Validation (whole record rejected on one bad entry):** safe name equal to the sender (canonical form); `rev` in
  `[0, now + 1 day]`; totals integers with `won, lost <= 2e13` copper, `wins, losses <= 1 000 000` and consistent
  (`wins <= won <= wins * 1e9`, same for losses); week keys `YYYY-Www` with year 2020..2100, week 1..53, not after the week
  of `now + 1 day`; `recent` a dense array of at most 20 flips with `c` in 1..1e9 (1c to 100 000g), `r` "W"/"L", `t` in `[0, now + 1 day]`.
  Results are self-reported (trust model): bounds and consistency are checked, truth is not.
- **Stored data (schema 2, `GuildGamesDB`):** `caught` (AZEcaught: `collection[npcId] = {n, lvl, cls, disp, seen, caught, st?, cnt?, last?, kills?, thr?, got?}`
  (<= 2000), `active` companion state, `activeSeconds`, `peaks`, `paidWeek`, `ledger = {earned, spent, entries}` (<= 60),
  `journal` (<= 400 log lines), `notify`, `verbose`, `items` (id -> count), `boosts` (id -> end time), `equipped` (the charm
  in the one slot, only while owned), `arenaBuffs` (id -> fights left, 1..3), `arena` = local arena state: per NPC `{xp, w, l, tr}`, the running
  training, my `ch`/`an`/`bt`, `settled`, `noticed`, `history` (<= 30)); migration 1 -> 2 adds it empty; re-validated on every load and kept
  by `/gg clean`. `games[name]`, re-validated on every load,
  emptied by `/gg clean`, pruned with players who left the guild. A newer schema on disk is left untouched (read-only session).
- **Display:** names are escaped in `Core/View/Model.lua`. Dev-build simulated players (`/ggd game sim`) live outside the
  database and are never sent.


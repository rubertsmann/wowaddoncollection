# 032 Arena watch to reveal and counter offers: spec

- Status: abandoned
- Created: 2026-11-24
- Target version: GuildGames 0.6.0 (protocol 1.3, schema 2)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
An arena fight's result (and its money) is revealed only after watching the replay, and the challenged player can
answer a challenge with a counter offer (another wager) that the challenger accepts or declines.

## Requirements
Watch to reveal
- R1: When my own fight is decided, I get "your fight is ready: watch it" (once), not the result. W/L, XP, payout and
  history are applied only after I watched the replay (played to the end, skipped to the end or closed after the start).
- R2: The same for a side bet: "the fight you bet on is ready: watch it"; the bet is paid / lost after watching.
- R3: Auto reveal: `REVEAL_AFTER` (24 h) after the fight time it is settled without watching (money never hangs).
- R4: The fight list hides the result of every decided fight I have not watched yet ("watch!"), for everybody (also
  fights I am not in).
Counter offer
- R5: The challenged player can, next to Accept/Decline (both in the dialog below the fight list), send a counter offer with another wager (0..1000g, not equal
  to the offered one). Their stake (the counter wager) leaves their pool at once. One counter per challenge; after a
  counter they cannot accept or decline the original.
- R6: The challenger sees the counter ("countered: X gold") and accepts or declines it. Accepting pays the difference
  (or gets it back) at once; the fight is on with the countered wager and the 5-minute bet window starts at that moment.
- R7: A declined counter, a stopped challenge or a counter not answered in time (`CHALLENGE_TTL` + `ANSWER_GRACE` after
  the counter) refunds both stakes once.
- R8: One fight at a time still holds: a countered challenge keeps both players busy.
- R9: Chat notices: "X made a counter offer (wager)", "X accepted / declined your counter offer".

## Non-goals
- No counter to a counter (one counter, then the challenger decides).
- No hiding of other players' W/L totals in the Guild view.

## Design
- `Core/Minigames/Arena.lua` (pure):
  - local `state.watched = { [id] = at }` (persisted, sanitized, cleaned like `settled`); `Arena.MarkWatched(records, me, id, now)`.
  - `Arena.Revealed(fight, now)`: watched or `now >= fightAt + REVEAL_AFTER`.
  - `Settle`: the "done" branches for fighters and bettors need `Revealed`; before that a notice `ready` / `betready` once.
  - counter: new section table `co = { [id] = {wg, at, f} }` (the challenged player's record); challenge fields
    `ca` (counter accepted at) / `cd` (counter declined at) in the challenger's `ch[id]`.
  - `Arena.Counter(records, me, id, wager, now)`, `Arena.AnswerCounter(records, me, id, accept, now)`.
  - `Fights`: states `countered` (waiting for the challenger), `rejected` (counter declined); with `ca` the fight is
    `open`/`done` with `fb = co.f`, `wager = co.wg`, `answerAt = ca`, `fightAt = ca + BET_WINDOW`; `fight.counter`.
  - refunds: challenger on rejected / withdrawn / expired (its original stake; after `ca` it paid the difference, so
    the stake is the counter wager); challenged on rejected / withdrawn / expired when it countered (counter wager).
- `Core/Base/Init.lua`: `PROTOCOL_MINOR = 3`.
- `Core/Game/Catcher.lua`: notice texts (`ready`, `betready`, `countered`, `counteranswered`).
- `UI/ArenaView.lua`: incoming row: Accept / Decline / Counter (wager box + Counter button in the details);
  countered row on the challenger's side: accept / decline the counter; done fights: "watch!" until watched; the replay
  marks the fight watched when it starts and settles (result + notices) when it ends or is closed.
- Locales/deDE.lua: the new texts. docs/protocol.md: 1.3.

## Tasks
- [x] T1 (M): watch gate in Arena.lua (watched state, Revealed, Settle, MarkWatched, persistence). Verify: test_arena
- [x] T2 (L): counter offer in Arena.lua (section `co`, `ca`/`cd`, Fights states, Counter, AnswerCounter, refunds, busy). Verify: test_arena
- [x] T3 (M): UI: rows/buttons, wager box, replay marks watched, hidden results; Catcher notices. Verify: test_load + wow-sim screenshot
- [x] T4 (S): protocol 1.3, protocol.md, deDE, README, CHANGELOG, doc.md. Verify: locale test, suite
- [ ] T5 (S): in game / two clients. Verify: user

## Review Focus (failure modes a happy-path test would miss)
1. RF1 Money never doubles or vanishes with a counter: challenger stake W, counter W2 (higher and lower), accepted /
   declined / stopped / expired: each side ends at the right balance, refunds once. Pinned by T2 tests.
2. RF2 A 1.2 peer never drops my whole arena section because of the new fields (`co` is a new key; `ca`/`cd` are extra
   fields an old sanitizer ignores). Pinned by T2 (old sanitizer behaviour reasoned + new sanitizer test).
3. RF3 Every client computes the same fight after a counter (fighter snapshot of the counter, the same id). Pinned by T2.
4. RF4 Watch gate: Settle before watching pays nothing and notices `ready` once; after watching it pays once; auto
   reveal after 24 h. Pinned by T1.
5. RF5 Hostile `co` entries (other owner, wager out of range, bad fighter) drop the section alone. Pinned by T2.

## Cross-cutting checklist (answer every line; "n/a: reason" is fine)
- [x] Protocol: additive minor 1.2 -> 1.3: new optional `co` table and optional `ca`/`cd` fields; 1.2 peers ignore them
  (they see a countered challenge as pending, then expired; they cannot bet on a counter fight).
- [x] Stored data: no schema bump: `watched` is additive and sanitized; `co` in local state like `an`.
- [x] Trust model: `co` sanitized by allow-list with bounds; only the challenged player's counter counts; only the
  challenger's `ca`/`cd` count.
- [x] Localization: texts via `Text[...]`, deDE.
- [x] Load order: n/a, no new file.
- [x] Packaging: n/a, no new file.
- [x] Tests: tests/test_arena.lua new cases.
- [x] Docs: README, CHANGELOG, docs/protocol.md, doc.md.

## Decisions (user answers and design choices, newest last)
- 2026-11-24 User: "i want to change that you need to "watch" the fight before seeing the result of the fight" and
  "the accepting side also needs to be able to counter offer the bet with another offer before accepting the fight".
  User chose: result AND money wait for the watch (auto reveal after 24 h); bettors watch too; one counter, then the
  challenger decides; the counter stake leaves at once.
- 2026-11-24 Claude: "watched" = the replay reached its end, was skipped to the end, or was closed after it started
  (not at its start: the 5 s arena tick would otherwise print the result in chat during the replay). Result hidden in
  the list for every fight until I watched it.
- 2026-11-24 Claude: counter stored in a new `co` table (not in `an`): a 1.2 sanitizer requires `an.ok` to be a boolean
  and would drop the whole section for a counter-shaped `an` entry.

- 2026-11-25 User: "move the inline button down to the dialog where you can do the counter offer". Accept / Decline
  left the fight rows (this replaces the 020 decision of 2026-11-21 "accept only in the row"): they are on the first
  line of the dialog below the list, the counter offer (gold box + button) on the second, Stop of a countered challenge
  there too; the waiting challenge's Stop stays in its row.

- 2026-11-25 User: "instead of annehmen / ablehnen 2 icons that display that information": the dialog's Accept /
  Decline are icon buttons (check / cross) with the text as tooltip; for a counter offer the tooltip names the amount.

## Open questions
- none

# 041 Fight requests in the Fights view (member dropdown, own wagers, pooled guild bets): spec

- Status: done
- Created: 2026-11-26
- Target version: 0.12.0 (protocol 1.7, schema 3)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
A challenge is started from a "Request a fight" subsection of the Fights view. Both fighters set their own wager.
The guild bets into one pot, and the winning side splits that whole pot by its share of the stakes.

## Requirements
- R1 Member dropdown: the Fights view has a request subsection with a dropdown of every guild member who runs
  GuildGames, except me. A member who can't be challenged is greyed out and shows the reason on hover:
  - another addon version (theirs and mine are shown);
  - fewer than 3 companions;
  - in a running (accepted, not yet decided) fight; a member whose own challenge waits can still be challenged
    (they can decline), as before;
  - offline.
  Greyed entries can't be picked.
- R2 Request: after picking a member, I pick 3 companions in fighting order (the team carousel/picker is reused) and
  a wager of at least `MINIMUM_WAGER` (1g) and at most `MAXIMUM_WAGER`. Send takes my stake and publishes the challenge.
- R3 Send animation: after Send, two crossed swords flash over the subsection with a short shake (~0.8 s, built on
  `UI/Animate.lua`). Then a "sent" line shows. A refused send plays no animation and shows the reason.
- R4 Accept: the challenged player accepts in the same reused picker/carousel menu: the challenger's team in the
  carousel, their own 3 picks, and their own wager (`MINIMUM_WAGER`..`MAXIMUM_WAGER`, independent of the challenger's).
  Or they decline. Counter offers are removed.
- R5 Pot: each fighter's wager is that fighter's stake on their own side. Other guild members (not the two fighters,
  same version) may place one bet each on one side, `MINIMUM_BET`..`MAXIMUM_BET`. Bets count only when placed before
  the fight time (accept + `BET_WINDOW`, 5 min).
- R6 Payout: the winning side (its fighter plus its bettors) gets back its own stakes plus the losing side's whole
  total, split by each stake's share of the winning side's total (rounded down to copper). The losing side loses
  everything. There are no odds.
- R7 Settlement: each player settles only themselves (fighter or bettor), from the stakes visible on their client,
  exactly as the fight result is computed today.
- R8 Guild view: the fight icon on another member's pet and its modal are removed; the Guild view only shows pets.
- R9 Upgrade: entries from 0.11.x finish under their old rules instead of being refunded. An accept without its own
  wager stakes the challenger's wager; a counter offer already made still fights or refunds; a bet with fixed odds is
  paid by its odds, outside the pot. No new counter offers or odds bets can be made. The same-version gate keeps
  0.11.x and 0.12.0 players apart.
- R10 Dev build: the arena dummy appears in the dropdown and accepts with its own wager (0.5x..2x the request, at
  least 1g) `DUMMY_DELAY` (20 s) after the request; the fake bettors of R11 fill the pot.
- R11 Dev event buttons: the dev build's icon row on the Fights page (next to "dummy challenges me" and "fight now")
  gets one button per fake event. Each button also has a `/ggd arena <word>` command, and each event is journaled:
  - `crowd`: 4 fake guild bettors place bets on both sides of the selected open fight;
  - `latebet`: a fake bet stamped after the fight time, to check that it is ignored;
  - `members`: fake members for the dropdown: one that can be challenged (`Sparring-Test`, it answers like the
    dummy) and one per greyed reason (version, fewer than 3 companions, busy, offline), so the
    dropdown and its tooltips can be checked;
  - `accept` / `decline`: the dummy answers my waiting challenge now (accept with a random own wager);
  - `expire`: waiting challenges with a fake member are moved past their time to live and grace, so the refund runs;
  - `reveal`: decided fake fights nobody watched are moved past `REVEAL_AFTER`, so they settle without watching.
  Only fights with a fake member are moved: a real player's fight never changes.
  Fake members and bettors live in `Games.simulated` (memory only, never stored or sent, like the dummy). A
  "clear" button removes them all.

## Non-goals
- A pot that is exact across clients when a bet syncs late: a client that has not seen a bet does not count it
  (see RF2, accepted limit).
- Betting by the fighters themselves; more than one bet per player per fight; changing a bet.
- New textures: the swords use stock icons.

## Design
- `Core/Minigames/Arena.lua` (changed):
  - The answer `an[id] = {ok, at, t?, wg?}` gains the accepting player's own wager (`Answer(..., uids, wager)`).
  - The bet `bt[id] = {s, c, at}` is written without `o`.
  - `Counter`, `AnswerCounter` and `Odds` are removed. `co`, `ca/cd` and a bet's `o` are still read (0.11.x leftovers).
  - `Arena.Pot(fight)`: the side totals and the stakes that count (the fighters' wagers, `fight.bets` without `o`);
    `Fights` already filters bets (after the accept, before the fight time, not a fighter, the fighters' version).
  - `Arena.Payout(pot, winner, name)`: own stake + floor(losing total x own stake / winning total).
  - `Settle` pays fighters and bettors through the pot; my own bet that did not count is refunded ("late"); bets on
    void (version, withdrawn) fights are refunded after the grace time.
  - `Arena.Candidates(records, myName, now, isOnline)`: dropdown entries, available first, with the greyed reason.
  - `MINIMUM_WAGER = 10000`; `DUMMY_DELAY`, `DummyWager`, `DummyRespond(..., onlyID, accept)`.
  - Dev helpers (memory only): `DevCrowd`, `DevLateBet`, `DevMembers`, `DevAnswer`, `DevShift`, `DevClear`,
    `devShift` (read in `Fights` and `Revealed`), `devOffline` (read in `Candidates`).
- `Core/Minigames/AzeCaught.lua` (changed): the caught section carries `rc` (my roster size), validated on receipt.
- `Core/Game/Catcher.lua` (changed): `/ggd arena crowd|latebet|members|accept|decline|expire|reveal|clear`,
  `Catcher.DevArena(word)` for the buttons; the win notice shows the pot payout.
- `UI/ArenaView.lua` (changed): the request row (member dropdown + Fight!), the member menu with greyed rows and
  tooltips, accept through the team picker with my wager, the two carousels with gold badges (wager / pot, my bet) in a framed box, the framed bet panel, the dev icon row.
  The Guild-view challenge modal and the counter widgets are removed.
- `UI/TeamDialog.lua` (changed): an optional wager box (`request.wager`, `onConfirm(uids, wager)`).
- `UI/Animate.lua` (changed): `Animate.Clash` (two swords fly in and cross, flash, ring, sparks, a shake, fade).
- `UI/AzeCaughtPanel.lua` (changed): the fight icon is removed; the arena guide goes Arena tab -> the member dropdown
  on the Fights page -> done after the first request.
- `UI/Window.lua` (changed): icon kinds for the dev tools.
- `Locales/deDE.lua` (changed): new strings, the modal's and counter offers' strings removed.
- Data shape change: the arena section (`an.wg`, bets without `o`) and the caught section (`rc`). Schema stays 3.
- Message shape change: protocol 1.6 -> 1.7 (minor). The exact-version gate already refuses mixed versions.

## Tasks
- [x] T1 (M): `Arena.Pot` / `Arena.Payout` with tests: the split by share, rounding, a late bet ignored, fighters can't bet, a 1g minimum wager. Verify: `tests/test_arena_pot.lua`
- [x] T2 (M): the challenge and answer with own wagers; counters removed; `Settle` through the pot; 0.11 leftovers read. Verify: arena tests updated plus `pot: ...` settle tests
- [x] T3 (S): `Arena.Candidates` with greyed reasons. Verify: `candidates: ...` tests
- [x] T4 (M): Fights view request subsection + dropdown with tooltips, TeamDialog wager field, accept flow. Verify: `tests/test_load.lua` (the request flow on stubs) + in game (dev build, dummy)
- [x] T5 (S): swords clash animation. Verify: in game
- [x] T6 (S): Guild view fight icon and modal removed. Verify: in game + suite
- [x] T7 (S): dummy: own wager on accept (after `DUMMY_DELAY`). Verify: `arena: the dev dummy accepts ...` + `/ggd arena dummy` in game
- [x] T9 (M): dev event buttons and commands (crowd, latebet, members, accept, decline, expire, reveal, clear); pure helpers in `Arena` (fake bettor records, time shifts) with tests. Verify: `dev events: ...` tests + the buttons in game
- [x] T8 (S): docs: protocol.md, README, CHANGELOG, doc.md. Verify: review

## Review Focus (failure modes a happy-path test would miss)
1. RF1: a winning side of one fighter with 1g against 500g -> gets 501g, nothing is created or lost in the sum. Pinned by: T1
2. RF2: a bet placed before the fight time but synced after it -> counted only where seen (documented); never counted twice, never paid twice. Pinned by: T1/T2
3. RF3: a fighter's own bet record or a bet from a non-member/another version -> ignored. Pinned by: T1
4. RF4: a 0.11 accept without its own wager, or a bet with odds, open at the upgrade -> the accept stakes the challenger's wager, the bet is paid by its odds outside the pot. Pinned by: T2
5. RF5: the member goes busy or offline between pick and Send -> refused with the reason, no stake taken, no animation. Pinned by: T3/T4

## Cross-cutting checklist (answer every line; "n/a: reason" is fine)
- [x] Protocol: 1.6 -> 1.7 (arena section shape: own answer wager, no counters, bets without odds); the exact-version gate already separates versions.
- [x] Stored data: schema stays 3; 0.11 leftovers (counters, odds bets, accepts without a wager) are still read and finish under their old rules.
- [x] Trust model: wagers and bets clamped and validated by allow-list; a payout uses only stakes in validated records; member names escaped in the dropdown and tooltip.
- [x] Localization: only reason ids in data; texts through `addon.Text` EN/DE.
- [x] Load order: n/a: no new file planned.
- [x] Packaging: n/a: no new file planned.
- [x] Tests: `tests/test_arena_pot.lua` (new), arena, team arena, item batch and load tests updated; counter tests removed.
- [x] Docs: README, CHANGELOG, docs/protocol.md, doc.md.

## Decisions (user answers and design choices, newest last)
- 2026-11-26 Q1: bets are frozen at the fight time; each client splits from the bets it has seen; a late-synced bet is not counted (user).
- 2026-11-26 Q2: one big pot: the fighters' wagers are their sides' stakes and split by share like any bet (user).
- 2026-11-26 Q3: an empty side can't happen, because both fighters always stake on their own side (user). This follows from Q5.
- 2026-11-26 Q4: the defender sets an own wager; the stakes don't have to match (user). Under Q2 "winner takes both" means the winning side takes the whole pot.
- 2026-11-26 Q5: a wager is required, minimum 1g (user).
- 2026-11-26 Q6: only other guild members bet; the fighters stake only through their wagers (user).
- 2026-11-26 Q7: every member with the addon is listed; greyed with a hover reason: version, fewer than 3 companions, busy, offline (user).
- 2026-11-26 Q8: the Guild view fight icon is removed (user).
- 2026-11-26 Q9: the send animation is a swords clash: crossed swords flash, a short shake, then "sent" (user).
- 2026-11-26 Q10: counter offers are dropped; the betting window stays 5 min after the accept (user).
- 2026-11-26 User: "add more buttons to fake events similar to skip time button". Claude picked the events the new flow needs to be testable alone (R11); they're dev build only, memory only and never sent.
- 2026-11-26 Claude: protocol 1.7 and release as 0.12.0 (a new feature plus a message shape change).
- 2026-11-26 Claude: the request is a row on the Fights page (dropdown + Fight!), and the team picker is the reused
  "menu with the carousel" for both send and accept, with the wager box next to Confirm. There is no separate panel.
- 2026-11-26 Claude: "busy" in the dropdown means a running fight. A member whose own challenge waits stays
  pickable, which keeps the existing rule `arena: one fight at a time ...`.
- 2026-11-26 Claude: the caught section gets `rc` (roster size) so "fewer than 3 companions" can be shown; it is
  additive, and older sections are not greyed for it.

## Open questions
- none

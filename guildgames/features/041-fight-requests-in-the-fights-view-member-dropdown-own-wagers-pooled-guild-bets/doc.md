# Fight requests in the Fights view (member dropdown, own wagers, pooled guild bets)

Status: verifying | Since version: 0.12.0 (unreleased) | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
- **Request:** AZEcaught > Arena > Fights has a row at the top: a dropdown of every guild member with a companion
  record (full page width, opaque), and **Fight!**. Members who can't be challenged are greyed out with a short
  reason; hovering says more: another version (theirs and mine), fewer than 3 companions, in a running fight,
  offline. Fight! opens the team picker: three companions in fighting order and my wager (at least 1g, the last one I
  used). Send takes the wager, crossed swords clash over the page and the new fight is selected in the list.
- **Accept:** the challenged player selects the fight; the fight box shows a framed panel "<Name> challenges you" with
  **Accept: pick your team and wager** and **Decline**. Accept opens the same picker with the challenger's
  team in the left carousel and their own wager (it starts at the challenger's). There are no counter offers.
- **Pot:** each fighter's wager is the first stake on their own side; every other member on the same version may bet
  once on one side in the 5 minutes after the accept. The winning side (fighter plus bettors) gets its stakes back
  plus the whole losing side, split by each stake's share; the losing side loses everything.
- **No win chance** is shown anywhere (picker or fights).
- **Guild view:** only shows the pets; the arena guide points from the Arena tab to the member dropdown.

## The team picker (request and accept)
- Two carousels side by side: the challenger's team left, "VS", the challenged player's team right. Each card shows
  one fighter at a time (round portrait, "2/3", name, level and ability, buffs; < > or the mouse wheel; hover for the
  full stats) and the player's name on a coloured plate below. My card shows my picks (a new pick jumps to it); their
  card shows a note while their team is unknown (my request).
- No title, no "your team" line and no slot buttons: below the carousels only my roster (9 rows; a click picks a
  companion into the next place or takes it out, the number is its place), then the wager box on the left and a tick
  (confirm: send or accept) and a cross (cancel) on the right.

## The Fights page
- Top: the request row. Then the fight list (4 rows): "Red vs Blue", the wagers, a tick when my bet is on it, and
  Stop in the row of my own waiting challenge (the only place for it).
- Below it a framed box (gold border, dark shade) for the selected fight:
  - both teams as carousels side by side (as in the picker; a team not picked yet shows a note);
  - a **gold badge** on each name plate, at its end toward the middle (no background): a coin and the amount as a plain gold number, no "g" (before the accept the
    challenger's wager; after it each side's pot: the fighter's wager plus every bet on them), a green tick on the
    side my bet is on; hover explains it and shows my bet;
  - another version or "one fight at a time" when that applies;
  - for an incoming challenge the answer panel (gold border, header "<Name> challenges you", a tick (accept: pick your team
    and wager, in the tooltip) and a cross (decline) in the middle), for a decided fight the watch panel (the same border, header "The fight is decided" or
    "<Name> won" once watched, [Watch] in the middle), or for an open fight of others the bet panel: the same border, the header
    "Place your bet" on a gold strip, then "[gold] (coin) [Red] [Blue]". After a bet the panel goes; the tick on the
    plate and in the list shows it (no chat or status line);
  - no status line: a success shows in the list and the box; a refusal is one red line in the box until the next
    action or another selection.
- Side colours everywhere: the challenger red, the challenged player blue (names in the list, plates, portrait rings,
  the bet buttons).
- Dev build: the event icons sit in a row just below the window.
- The whole window is 300 x 376 (was 336).

## How it works
- Data: the answer `an[id].wg` (own wager), bets `bt[id] = {s, c, at}` (no odds), the caught section `rc` (roster
  size). Protocol 1.7; see `docs/protocol.md` "Own wagers and the pot".
- `Arena.Pot(fight)` and `Arena.Payout(pot, winner, name)` are pure; every client computes them from the records it
  has. `Arena.Fights` counts a bet only after the accept, before the fight time, not from a fighter, and from a bettor
  on the fighters' version.
- `Arena.Candidates(records, me, now, isOnline)` builds the dropdown; `UI/ArenaView.lua` shows it.
  `TeamDialog.BuildCard` / `FillCard` / `SetCardGold` are the carousel card (picker and fight box), `Animate.Clash` the
  send animation.

## Dev build
- Icons in a row just below the Fights page, the same as `/ggd arena <word>`: `request` (the dummy challenges me),
  `accept` / `decline` (it answers my waiting challenge now), `skip`, `crowd` (4 fake bettors on the selected open
  fight), `latebet` (a fake bet at the fight time: stays out), `members` (a fake member that can be challenged and
  answers like the dummy, plus one for every greyed reason), `expire` / `reveal` (fake fights past their time to live
  / the one hour reveal), `clear`. All in `Games.simulated` and memory-only tables: never stored, never sent; only
  fights with a fake member are moved in time.
- The dummy accepts on its own 20 s after a request, with 0.5x..2x the wager.

## Limits
- A bet that reaches a client only after the fight time is left out there (each client splits what it saw in time),
  so players can disagree by that bet. A bettor whose own bet did not count gets it back.
- Payouts are rounded down to copper: the winning side may get a few copper less than the pot in total.
- A member's companion count is known only from 0.12.0 records.
- 0.11 leftovers finish under their old rules: an accept without its own wager stakes the challenger's, a bet with
  fixed odds is paid by its odds, a counter offer still waiting expires and refunds.

## Localization
- New strings EN (keys) and DE (`Locales/deDE.lua`); only reason ids are in data.

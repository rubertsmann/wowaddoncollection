# 041 Fight requests in the Fights view (member dropdown, own wagers, pooled guild bets): log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-26 21:46 | PLAN | Feature created
- Did: scaffolded `features/041-fight-requests-in-the-fights-view-member-dropdown-own-wagers-pooled-guild-bets/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-26 21:57 | DECISION | Ten questions answered, spec filled
- Did: asked Q1-Q10 (pot, wagers, minimum wager, bettors, dropdown, Guild view icon, animation, counters); wrote spec.md
- Result: R1-R10, T1-T8, protocol 1.7, schema 3, target 0.12.0
- Evidence: spec.md "Decisions"
- Next: user reviews the spec; then T1 (`Arena.Pot` / `Arena.Payout`, tests first)

## 2026-11-26 21:59 | DECISION | Dev event buttons added to the plan, implementation started
- Did: R11/T9 (fake events: crowd, latebet, members, accept, decline, expire, reveal, clear) added to spec.md; the user said "start implementation"
- Result: plan accepted
- Evidence: spec.md "Decisions"
- Next: T1

## 2026-11-26 22:04 | BUILD | T1 pot and T2 own wagers in Arena.lua
- Did: `Arena.Pot` / `Arena.Payout`, `MINIMUM_WAGER` (1g), `Answer(..., uids, wager)` with `an.wg`, `Counter` / `AnswerCounter` removed, `Bet` without odds (+ version check), `Settle` pays fighters and bettors from the pot (a late own bet comes back), bets on void (version/withdrawn) fights are refunded after the grace time, dummy answers after `DUMMY_DELAY` with its own wager (`DummyWager`); `tests/test_arena_pot.lua` (new), arena tests moved to the pot, counter tests removed
- Result: core suite green; only the UI accept flow (test_load) fails, pending T4
- Evidence: `195 passed, 1 failed` (tests/test_load.lua:571 accepted with the team: false)
- Next: T4 UI (ArenaView request subsection, TeamDialog wager)

## 2026-11-26 22:04 | DEVIATION | 0.11.x leftovers finish under the old rules instead of a refund
- Did: R9 and the design changed in spec.md; Fights still reads counters (`co`, `ca/cd`) and bets with odds (`o`)
- Result: a refund at load can't know a counter's wager (it is in the peer's record), so reading them is exact where a refund would guess
- Evidence: `pot: a bet ... with old fixed odds is paid by its odds`, `pot: an accept from before the pot ... stakes the challenger's wager`
- Next: T4

## 2026-11-26 22:20 | BUILD | T3 candidates, T4-T7 UI, T9 dev events
- Did: `Arena.Candidates` (+ `rc` in the caught section), Fights page request row + member menu (`UI/ArenaView.lua`), wager box in `UI/TeamDialog.lua`, `Animate.Clash`, Guild-view fight icon and modal removed, guide goes to the dropdown (`UI/AzeCaughtPanel.lua`), dev helpers `DevCrowd/DevLateBet/DevMembers/DevAnswer/DevShift/DevClear` + `/ggd arena` commands + icon row, deDE strings, protocol 1.7, `Arena.Odds` removed
- Result: suite green; the load test walks the request flow (dropdown, picker, wager checks, send, greyed members, every dev icon)
- Evidence: `198 passed, 0 failed`
- Next: T8 docs

## 2026-11-26 22:20 | DOC | T8 docs
- Did: README (arena paragraph, dev arena commands), CHANGELOG Unreleased, docs/protocol.md (protocol 1.7 section), doc.md, verify.md, spec.md (design = what is built)
- Result: status verifying; offline rows pass, the in-game look and a real two-player fight are NOT-VERIFIED
- Evidence: verify.md
- Next: the user runs the in-game checklist in verify.md on the dev build (deploy, /reload); then two real players; then release 0.12.0

## 2026-11-26 22:26 | BUILD | members: one fake member can be challenged
- Did: the user asked for at least one legitimate entry among the fake members; `Arena.DevMembers` adds `Sparring-Test` (pickable), `Arena.DevResponders` (dummy + sparring) answer my challenges on the arena tick and through the accept/decline icons; spec R11, doc, README, verify updated
- Result: suite green
- Evidence: `198 passed, 0 failed` (`dev events: ...` picks and fights the sparring member; `load: ...` picks it in the dropdown)
- Next: the user runs the in-game checklist in verify.md on the dev build

## 2026-11-26 22:29 | VERIFY | first in-game check on the dev build
- Did: the user tried the feature in game (dev build)
- Result: the user reported "looks and works fine now needs fine tuning"; which rows of the checklist were covered was not stated
- Evidence: user statement in chat, 2026-11-26
- Next: collect the fine-tuning points from the user; keep the in-game rows NOT-VERIFIED until the user confirms each one

## 2026-11-26 22:30 | BUILD | tuning: the member list spans the full page width
- Did: `UI/ArenaView.lua` member menu 230 -> 292 wide (list 288, name column 170, reason column 110), the same width as the request row (dropdown + Fight!)
- Result: suite green; the look needs the user in game
- Evidence: `198 passed, 0 failed`
- Next: more tuning points from the user

## 2026-11-26 22:32 | BUILD | tuning: the member list is fully opaque
- Did: `UI/ArenaView.lua` member menu backdrop alpha 0.97 -> 1 and `SetIgnoreParentAlpha(true)` when the client has it (the window fades its parts)
- Result: suite green; the look needs the user in game
- Evidence: `198 passed, 0 failed`
- Next: more tuning points from the user

## 2026-11-26 22:36 | BUILD | tuning: the picker shows both teams as carousels side by side
- Did: the user asked for "(CAROUSEL VIEW) vs (CAROUSEL VIEW) with each player's name below". `UI/TeamDialog.lua`: `buildCard` / `fillCard` (portrait, < >, mouse wheel, "n/3", name, level and ability, buffs, the player's name, full stats on hover); challenger left, VS, challenged player right; `TeamDialog.ShowMine`, `TeamDialog.Step`, `TeamDialog.MyTeam`; the slots and the roster list (5 rows) moved down; the unused "{name}'s team" string removed from deDE
- Result: suite green; the load test checks the sides, their fighter and that my carousel wraps
- Evidence: `198 passed, 0 failed`
- Next: the user looks at the picker in game (request to the dummy, accept a dummy request)

## 2026-11-26 22:40 | BUILD | tuning: red and blue names (challenger / challenged)
- Did: the user asked for red and blue names for easier identification, meant for the Fights overview and the picker ("it looks nice"). `UI/TeamDialog.lua`: a coloured name plate under each carousel and a tinted portrait ring (left red, right blue); `UI/ArenaView.lua`: `ArenaView.SideName` colours the names in the fight rows, the team lines, the pot line and my bet
- Result: suite green; the user saw the picker in game and liked it; the colours are not seen in game yet
- Evidence: `198 passed, 0 failed`; user statement in chat
- Next: the user checks the colours in game; more tuning points

## 2026-11-26 22:45 | BUILD | tuning: the selected fight as two carousels in a framed box
- Did: the user asked for the selected fight to show both teams as carousels next to each other, the other information below, and a visible border between the list and the fight info. `UI/TeamDialog.lua`: the card is `TeamDialog.BuildCard(parent, side, options)` / `TeamDialog.FillCard` (size and step handler as options, shared with the picker); `UI/ArenaView.lua`: fight list 4 rows, a bordered box below it with the two carousels (positions kept per fight in `state.cardShown`), VS, the info lines (team lines dropped: the carousels show the teams), the buttons and the status inside the box; the dev icons moved to a row below the window
- Result: suite green; the load test checks the box and the challenger's carousel
- Evidence: `198 passed, 0 failed`
- Next: the user checks the layout in game

## 2026-11-26 22:51 | BUILD | tuning: taller window, name plate under the level line, small arrows
- Did: `UI/Window.lua` stage 300 x 336 -> 300 x 376 (all games); `UI/TeamDialog.lua` card height = portrait + `CARD_TEXT_HEIGHT` (name 14, level line 24, name plate 18 anchored under the level line instead of the card's bottom, so they no longer overlap), arrows 18x26 -> 12x16; picker slots and roster moved down, roster 5 -> 6 rows; `UI/ArenaView.lua` fight box: cards use the computed height, info and buttons moved down
- Result: suite green
- Evidence: `198 passed, 0 failed`
- Next: the user checks in game (also the other games and AZEcaught views with the taller window)

## 2026-11-26 22:57 | BUILD | tuning: the bet panel with a border and a header
- Did: the user asked for a clear border and a header like "Bet X on Name vs Name" for betting on an open fight. `UI/ArenaView.lua`: `addBorder` helper (also used by the fight box); a framed bet panel in the fight box: a gold strip with "Bet on {a} vs {b}" (side colours), then the gold box, "gold on" and two buttons in the side colours; the status line moved below it; deDE string
- Result: suite green; the load test bets on the fake members' open fight through the panel
- Evidence: `198 passed, 0 failed`
- Next: the user checks the bet panel in game (`/ggd arena members` gives an open fight of two others)

## 2026-11-26 23:03 | BUILD | tuning: no win chance, "Place your bet", gold badges on the plates
- Did: the user asked to remove every win-chance hint, rename the bet header to "Place your bet" with "___ G", drop the "bet placed" message for an indicator, and show the gold as an icon on the name plate (toward the middle, explained on hover) instead of the pot line. `UI/TeamDialog.lua`: gold badge on the card (`TeamDialog.SetCardGold`: coin, amount, a tick for my bet, hover lines), `TeamDialog.Chance` removed; `UI/ArenaView.lua`: badges filled from the wager / pot, pot, chance and my-bet lines removed, bet panel "Place your bet" + [gold] (coin) [Red] [Blue], no status text after a bet, a tick in the fight list row for my bet; `Arena.Chance` removed; deDE strings added / 8 unused removed; doc.md rewritten to the current state
- Result: suite green
- Evidence: `198 passed, 0 failed` (the load test checks both badges after a bet)
- Next: the user checks the badges and the bet panel in game

## 2026-11-26 23:06 | BUILD | tuning: transparent gold badge, no Stop in the fight box
- Did: `UI/TeamDialog.lua` gold badge without its background; `UI/ArenaView.lua` the Stop button in the fight box removed (Stop stays in the fight row, now also for an old countered challenge)
- Result: suite green
- Evidence: `198 passed, 0 failed`
- Next: the user checks in game

## 2026-11-26 23:08 | BUILD | tuning: the gold badge shows a plain number
- Did: `UI/TeamDialog.lua` `TeamDialog.GoldNumber` ("12", "2.5", "0.15"): the badge drops the "g" (the coin is the unit); hover keeps the full amounts
- Result: suite green
- Evidence: `198 passed, 0 failed`
- Next: the user checks in game

## 2026-11-26 23:15 | BUILD | tuning: framed answer panel, no status line
- Did: the user asked for the accept view to look like the bet view (border, header, clear purpose) and to drop the status line ("Declined" etc.). `UI/ArenaView.lua`: `buildActionPanel` (shared by both panels); the answer panel "<Name> challenges you" with [Accept: pick your team and wager] (primary) and [Decline]; the status line removed: success messages gone (Declined, Accepted, Challenge stopped, Request sent), a refusal is one red line in the box for that fight (`state.refusal`, cleared on a row click or a success); a greyed dropdown entry is just not pickable; deDE: 2 strings added, 4 removed
- Result: suite green; the load test checks the answer panel and a refused bet
- Evidence: `198 passed, 0 failed`
- Next: the user checks in game

## 2026-11-26 23:20 | BUILD | tuning: a lean team picker
- Did: the user asked to drop the picker's title, the "Your team (3/3): click to pick or drop" line and the slot row, keep only the roster table, and show a tick and a cross on the right instead of Accept / Cancel. `UI/TeamDialog.lua`: carousels at the top, roster 9 rows, wager box bottom left, tick (confirm) and cross (cancel) icon buttons bottom right; `request.title` dropped (ArenaView no longer passes it); 3 deDE strings removed
- Result: suite green
- Evidence: `198 passed, 0 failed`
- Next: the user checks the picker in game

## 2026-11-26 23:22 | BUILD | tuning: the watch panel
- Did: the user asked for the Watch button to match the other two panels (in the middle, with a border). `UI/ArenaView.lua`: a third action panel for a decided fight: header "The fight is decided" (or "<Name> won" in the side colour once revealed), [Watch] centred; the unused action row position removed; deDE string added
- Result: suite green
- Evidence: `198 passed, 0 failed`
- Next: the user checks in game

## 2026-11-26 23:24 | BUILD | tuning: tick and cross in the answer panel
- Did: `UI/ArenaView.lua` the answer panel's text buttons became a tick (accept, tooltip "Accept: pick your team and wager", or the busy reason when greyed) and a cross (decline), next to each other in the middle
- Result: suite green
- Evidence: `198 passed, 0 failed`
- Next: the user checks in game

## 2026-11-27 07:27 | BUILD | tuning: unwatched fights settle after 1 hour
- Did: `Core/Minigames/Arena.lua` REVEAL_AFTER 24 h -> 1 h; dev "reveal" tooltip, README, doc.md and CHANGELOG say one hour
- Result: suite green
- Evidence: `198 passed, 0 failed`
- Next: the user checks in game

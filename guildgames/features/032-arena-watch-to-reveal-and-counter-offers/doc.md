# Arena watch to reveal and counter offers

Status: verifying | Since version: 0.6.0 (protocol 1.3) | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
- **Watch to see the result:** when an arena fight is decided, the chat says "your fight is decided, watch it" and the
  fight list shows "watch!". The result, the wager, W/L, XP and history (and side bets) are settled only after you
  watched the replay (played to the end, skipped to the end, or closed). After 24 hours it settles by itself.
- **Counter offers:** the challenged player can answer a challenge with another wager instead of Accept / Decline. That
  wager leaves their pool at once. The challenger accepts it (pays or gets back the difference, the fight starts and
  the 5-minute bet window opens) or declines it (both wagers come back). One counter per challenge.

## How to use
- AZEcaught > Arena > Fights. Select an incoming challenge: below the details two icons (green check = accept, red cross = decline; hover for the text), and under them
  the gold box with **Counter offer**. A counter offer to your challenge: the row says "counter offer!"; select it,
  the details show the amount, the check / cross icons answer it (the tooltip names the amount), **Stop** is below them.
- A decided fight: select it, **Watch**. Dev build: `/ggd arena request [gold]`, `/ggd arena skip` (the dummy accepts
  counter offers too).

## How it works
- Data: local `db.caught.arena.watched[id] = time` (sanitized, cleaned like `settled`) and `co` (my counter offers).
- Messages: arena section `co[id] = {wg, at, f}`; challenge fields `ca` / `cd` (docs/protocol.md, protocol 1.3).
- Modules: `Core/Minigames/Arena.lua` (`Counter`, `AnswerCounter`, `MarkWatched`, `Revealed`, `Fights` states
  `countered` / `rejected`, `Settle`), `UI/ArenaView.lua` (rows, counter box, replay marks the fight watched),
  `Core/Game/Catcher.lua` (chat lines).

## Localization
All new texts in deDE.

## Limits and known issues
- A 1.2 peer does not see counter offers: for it the challenge stays unanswered (then expires), and it cannot bet on a
  fight that started from a counter offer.
- Other members' W/L totals in the Guild view may change before I watched a fight they were in.

## Changelog line
- Arena: watch a decided fight to see its result (auto after 24 h); counter offers with another wager (protocol 1.3).

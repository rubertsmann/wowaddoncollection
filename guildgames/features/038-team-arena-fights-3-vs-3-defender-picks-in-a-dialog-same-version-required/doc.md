# 038 Team arena fights (3 vs 3)

Status: verifying (the in-game and two-client checks in [verify](verify.md) are open).

## What it does for the player
- Every arena fight is three against three. A team is picked for each fight from the roster (037); you need three
  companions.
- Challenge: the modal shows your team (the first three of your roster to start with; **Change team** opens the team
  dialog) and the wager.
- Accept or counter offer: the team dialog opens. It shows the challenger's three in full (level, ability, attack /
  defense / speed / vitality, buffs), your whole roster (a click puts a companion into the next slot, a click on a
  slot empties it) and your win chance with that pick.
- The fight: the first of each side fight. The winner of a round stays in with its remaining health and everything
  still running (shield, bleeding, burn, stun, focus, ability cadence) and meets the loser's next fighter, who comes
  in fresh. The side without fighters left loses. The replay swaps the fighters and shows three squares per side
  (gold: fighting, green: waiting, dark: beaten).
- Rewards: the wager and side bets as before. Every companion that entered gets 15 XP plus 25 XP per opponent it
  beat; its wins/losses count rounds. Your arena record counts team fights. An arena buff works on all three and uses
  one charge per fight.
- Both players need the same GuildGames version. Otherwise the challenge (or accept) is refused with both versions
  named; a fight that turns mixed (one updated) is void and both stakes come back.

## How it works
- See `docs/protocol.md`, "Arena teams and the version gate (protocol 1.6)": entries carry `t` (3 fighters), the
  section carries `ver`.
- `Arena.Fight(teamA, teamB, id)` (a single fighter is a team of one: the old duel). `Arena.Team(uids)`,
  `Arena.SanitizeTeam`, `Arena.SameVersion`, `Arena.VersionOf`, `Arena.MissingForTeam`.
- `arena.uids[id]` (local) remembers my team per fight for the XP.
- UI: `UI/TeamDialog.lua` (new, after ArenaView in the TOC); ArenaView opens it from Accept, Counter offer and the
  challenge modal; the Fights page is hidden while it is open.

## Limits
- One-against-one fights that were open at the update are void: my own challenges and counter offers are refunded
  once; the stake of a one-against-one challenge I had **accepted** is not known locally and is not refunded.
- When one player updates after a fight was already watched and paid on the other side, the void refund can pay
  that player back once more (rare; only during an update).
- The win chance in the dialog uses 40 simulated fights per pick (cached); speed in game not measured.

## Verification
See [verify.md](verify.md).

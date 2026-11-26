# 038 Team arena fights (3 vs 3, defender picks in a dialog, same version required): spec

- Status: done
- Created: 2026-11-25
- Target version: 0.11.0
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md) | needs [037](../037-companion-roster-every-catch-its-own-companion-one-active-frozen-needs/spec.md)

## Goal
Every arena fight is 3 against 3. The challenger picks a team when challenging, and the defender sees it in full and picks a counter team in a dialog when accepting. Both players must run the same GuildGames version.

## Requirements
- R1: A team has exactly 3 different roster companions, picked per fight. There is no standing team, and the guild record does not carry it. A player with fewer than 3 companions can't challenge or accept and is told how many are missing.
- R2: The challenger picks 3 in order and the wager in a team dialog. The challenge carries the 3 fighter snapshots.
- R3: Accepting (and sending a counter offer) opens the same dialog for the defender:
  - The challenger's 3 are shown in full, in order: name, type, level, all stats, ability and buffs.
  - The defender picks 3 from their whole roster, in order, and sees a win chance for the current pick.
- R4: The fight runs in sequence:
  - The first fighter of each side fights. The winner of a round stays in with its remaining health and everything else running: shield, damage over time, stun, focus, ability cadence and action gauge. It continues "as if nothing happened" against the next fighter, who enters fresh.
  - The fight ends when one side has no fighter left.
  - A round that reaches the action limit is won by the higher health share, and the loser is out.
  - The result is deterministic from the two teams and the fight id.
- R5: The replay and the result show both teams: who is in, who is down, the current duel and the remaining health.
- R6: Rewards:
  - The wager and side bets go on the team result, as now.
  - Each companion that entered gets participation XP, plus extra XP for every opponent it knocked out.
  - The companion records count rounds won and lost. The player's arena record counts team fights won and lost.
- R7: Arena buffs work on the whole team (each of the 3 snapshots) and use one charge per fight.
- R8: Version gate:
  - The arena section of the guild record carries the sender's addon version `ver`.
  - Challenge, Answer, Counter and AnswerCounter are refused (`"version"`) unless both players run exactly the same version.
  - The UI greys out the button and names both versions ("X runs 0.11.0, you run 0.11.1: both need the same version").
  - Fight records carry `ver`. Records with a different version are never settled; their wagers are refunded.
- R9: The training dummy fields a team of 3 generated fighters, so team fights can be tried alone.
- R10: The old one-against-one challenges still open at the upgrade are void. Paid wagers are refunded once.

## Non-goals
- Support for older clients (beta; the user decided this, Q10). Instead they are refused clearly (R8).
- Saved team presets.
- A type strength chart (possible later; the dialog shows the information the defender needs to counter).
- Changing the order mid-fight or swapping fighters manually.

## Design
- `Core/Minigames/Arena.lua`:
  - `Arena.Team(uids)` builds 3 fighter snapshots and checks that they are 3, different and owned.
  - `Arena.TeamFight(teamA, teamB, id)` reuses the duel step from `Arena.Fight`, which is refactored into a `duel(state, random)` that keeps the side state between rounds. Events gain `{k="enter", s, slot}` and `{k="out", s, slot}`.
  - `Arena.Fight` stays as a single duel inside it.
  - `Arena.WinChance` gets a team form (fewer samples if it is slow; measured in T3).
  - `Challenge`, `Answer` and `Counter` take a team (uids) instead of reading the active companion.
  - Wire: challenge `ch[id].t = {f,f,f}`, answer `an[id].t`, counter `co[id].t`, and `ver` on the section.
  - `SanitizeSection` takes exactly 3 sanitized fighters and drops entries with a single `f`.
- Rewards in `Arena.Settle`: per uid via `Arena.Progress` (from 037).
- `Arena.VersionMatch(records, opponent)` compares `records[opponent].arena.ver` with `addon.VERSION`. This works like ProfessionShare's member builds (`Channel.PeerVersions`, the HELLO `ver` tag), but is kept in the record, so it also works for offline challenges.
- `UI/TeamDialog.lua` (new):
  - The left side shows the opponent's team, or empty while challenging.
  - The right side shows the roster list with 3 numbered slots, the win chance and the wager.
  - Confirm and Cancel buttons.
  - It opens from Challenge, Accept and Counter in `UI/ArenaView.lua`.
- `UI/ArenaView.lua`: the fight details and replay show the team strip (3 icons per side, greyed when down).
- Protocol: `PROTOCOL_MINOR` 5 -> 6. This is additive for the rest of the record; the arena entries change shape and older clients drop them.
- Schema: unchanged by 038 (3, from 037). R10 runs as a one-time cleanup in `Arena.SanitizePersisted`.

## Tasks
- [x] T1 (M): Duel refactor and `TeamFight` with carry-over state. Verify: test_team_arena "the round winner keeps its health, shield and damage over time"; "the same teams and id give the same result"; the existing test_arena fights still pass unchanged.
- [x] T2 (S): `Arena.Team` checks (3, different, owned, alive). Verify: "a team needs exactly 3 different own companions".
- [x] T3 (M): Challenge, Answer, Counter and AnswerCounter with teams, buffs on all 3, team WinChance (timing measured). Verify: "a team challenge and answer settle with one buff charge each".
- [x] T4 (M): Settle rewards per companion (participation and knockout XP, round records), player record per fight, side bets. Verify: "rewards go to every companion that entered".
- [x] T5 (S): Version gate: `ver` in the section, refusals, settle skip and refund. Verify: "different versions can't challenge or accept".
- [x] T6 (S): Sanitizer: exactly 3 fighters, garbage, old single-`f` entries void and refunded once. Verify: "peer teams with 2, 4 or garbage fighters are dropped"; "an old 1v1 challenge is refunded once".
- [x] T7 (S): Dummy team. Verify: "the dummy fields 3 fighters".
- [x] T8 (L): `UI/TeamDialog.lua` plus the ArenaView hooks (challenge, accept, counter) and the team strip in the details and replay. Verify: simulator shots, then in-game.
- [x] T9 (S): Locale, README, CHANGELOG, `docs/protocol.md` (1.6 arena teams, `ver`). Verify: tests green.

## Review Focus
1. RF1: A peer sends a team with repeats, 2 or 4 fighters, or huge stats -> dropped or clamped by `SanitizeFighter`, so both clients compute the same fight (T6).
2. RF2: Determinism: both clients replay the same events. The carried state (gauge, dot, focus, stun) is included in the seed path, and the order of `pairs` is never used (T1).
3. RF3: A companion in an open team is released, dies or is switched before the fight settles -> the snapshot still fights; rewards for a uid that no longer exists are skipped without errors (T4).
4. RF4: A version mismatch arises after a challenge was sent (one player updates) -> the fight is not settled, and the wager is refunded on both sides (T5).
5. RF5: The team WinChance (100 samples × up to 5 rounds) is too slow for the dialog -> it is measured, and the sample count is cut or the result cached per pick (T3).

## Cross-cutting checklist
- [x] Protocol: minor 1.6. Arena entries change shape (`t` replaces `f`) and the section gains `ver`. Older clients drop the new entries and are refused by the version gate.
- [x] Stored data: no schema change (3 comes from 037). The 1v1 leftovers are cleaned up once (R10).
- [x] Trust model: peer teams go through `SanitizeFighter` per slot with an exact count of 3. `ver` goes through `Channel.SanitizeVersionTag`-style rules and is escaped before display.
- [x] Localization: only ids and numbers are sent. The dialog texts go into deDE.
- [x] Load order: `UI/TeamDialog.lua` comes after `UI/ArenaView.lua` helpers, before the Window that opens it (TOC plus the dev TOC generator).
- [x] Packaging: one new UI file, already covered by the existing globs (to be checked in package.ps1).
- [x] Tests: new `tests/test_team_arena.lua` (adversarial: wrong counts, version mismatch, a released companion, old entries).
- [x] Docs: README, CHANGELOG, `docs/protocol.md`, doc.md.

## Decisions (user answers and design choices, newest last)
- 2026-11-25: Exactly 3 per side. The team is defined per fight, not stored and not in the guild record (user, Q6).
- 2026-11-25: The round winner carries its remaining health and running cooldowns and effects into the next round "as if nothing happened" (user, Q7).
- 2026-11-25: The defender sees everything about the challenger's team and picks from their own whole roster (user, Q8). Interpretation: "full roster" means the challenger's 3 in full detail plus all of the defender's own companions to pick from.
- 2026-11-25: Rewards and buffs were left to me (user, Q9):
  - participation plus knockout XP per companion
  - the wager on the team result
  - buffs on all 3, one charge per fight
- 2026-11-25: Older versions are not supported. Both players need exactly the same addon version, or fights can't be requested or accepted. The pattern follows ProfessionShare's version comparison (user, Q10).
- 2026-11-25: Every arena fight is a team fight. The 1v1 mode goes, and old open 1v1 challenges are refunded (design choice that follows from "exactly 3").

- 2026-11-25: DEVIATION: there is no separate `TeamFight`; `Arena.Fight` takes teams (a single fighter is a team of one and fights exactly the old duel). The team dialog hides the Fights page while it is open (accept, counter). Old one-against-one leftovers: my open challenges and counter offers are refunded once (`legacyRefund`); the stake of a one-against-one challenge I had accepted is not known locally and is not refunded (limit in doc.md).

## Open questions
- none (the "full roster" interpretation above is to be confirmed when the plan is reviewed)

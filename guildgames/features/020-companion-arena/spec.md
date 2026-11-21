# 020 Companion arena: spec

- Status: verifying
- Created: 2026-11-21
- Target version: GuildGames 0.3.0 (protocol 1.2, schema 2)
- Owner: claude (user: "create a fully new async battle system for the companion")
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
Guild members' companions fight each other in a hands-off, deterministic auto battle that is challenged, accepted or
declined asynchronously, with trainable stats, an arena level, win/loss records, a wager between the two fighters and
side bets from the rest of the guild.

## Requirements
- R1 Fighter: a snapshot of my active companion: combat stats (`AzeCaught.CombatStats`: attack, defense, speed) plus
  vitality (health), each raised by **training** points and by the **arena level**; an ability from the creature type;
  hunger/thirst below the needy line weaken it (-10% attack), hearts add morale (+1% per heart, at most +10%).
- R2 Training: one session at a time per character, on one stat (attack, defense, speed, vitality). It costs gold
  (`TRAIN_COST` x (points + 1)) and `TRAIN_ENERGY` energy, and finishes after `TRAIN_SECONDS` of active time; then the
  stat gains one point (at most `MAXIMUM_TRAINING` per stat). Training is kept per NPC (switching back keeps it).
- R3 Arena level: XP per fight (win `XP_WIN`, loss `XP_LOSS`); level n needs `XP_PER_LEVEL` x n XP more; each level adds
  `LEVEL_BONUS` (3%) to every stat. Kept per NPC with the NPC's own wins and losses.
- R4 Battle: deterministic from the two snapshots and the fight id (Park-Miller RNG), so every client computes the same
  fight. Speed fills an action gauge (who acts, how often); every 3rd action is the ability; damage =
  attack^2 / (attack + defense) x (0.9..1.1); crit (speed based, x1.5); dodge (speed difference, 5..25%). Abilities by
  creature type: beast Rend (bleed), demon Fel Fire (burn), undead Drain (heals half), mechanical Barrier (shield),
  humanoid Focus (next hit crits), elemental Surge (x1.8), dragonkin Breath (ignores half the defense), giant Smash
  (stuns one action), others Strike (x1.3). Ends at 0 health or after `MAXIMUM_ACTIONS`; then the higher health share
  wins. A compact event log is returned for the replay.
- R5 Challenge (async): I challenge a guild member who has a companion, with a wager 0..`MAXIMUM_WAGER`; my stake leaves
  my pool at once. The challenge is in my record (`arena.ch`) until answered or `CHALLENGE_TTL` (24 h) passed (refund).
- R6 Answer: the challenged player accepts (pays the same wager; their fighter snapshot goes into their record
  `arena.an`) or declines. Only the named opponent's answer counts; a decline or expiry refunds the challenger.
- R7 Fight time: `BET_WINDOW` (5 min) after the accept the fight is decided. Each fighter settles only themselves: the
  winner gets both stakes; W/L and XP go to the NPC's arena entry and the record's arena totals (`w`, `l`).
- R8 Side bets: any other guild member may bet on one side while the fight is open (accepted, before fight time), one
  bet per fight, `MINIMUM_BET`..`MAXIMUM_BET`. Fixed odds from the win chance at bet time (`Arena.Odds`: 0.95 / chance,
  1.1..10x), stored with the bet; a right bet pays stake x odds after the fight. Bets are in the bettor's record
  (`arena.bt`) so the guild sees them.
- R9 History: my last `MAXIMUM_HISTORY` fights are kept locally; the guild view shows each member's arena W/L.
- R10 UI: an "Arena" view in the AZEcaught panel: my fighter (arena level, XP bar, W/L, four stats with train buttons,
  training progress), the fight list (incoming: Accept/Decline; open: bet on either side with the odds; finished: result
  and Watch), in the Guild view one fight icon on another member's selected pet that opens a challenge modal in steps
  (matchup, wager, confirm, sent), an animated replay (two models, health bars, floating damage, shake on hit, the
  winner's burst).
- R12 Dev build: a fake opponent (`/ggd arena dummy`, memory only, accepts my challenges) and a fake incoming
  challenge (`/ggd arena request [gold]`) to test alone.
- R11 Notices: chat lines for a new challenge, an answer, a fight result and a bet result (once each).

## Non-goals
- No real gold (the addon's bookkeeping pool). No live input in a fight (hands-off by design).
- No proof against a guild member who edits their saved data (trust model: guild members are trusted).

## Design
- `Core/Minigames/Arena.lua` (new, pure): fighters, training, XP/levels, battle, odds, the `arena` record section
  (build, sanitize), challenge/answer/bet/settle over all records, local state `db.caught.arena`.
- `Core/Data/Games.lua`: `SetSection` also takes `"arena"`; `Sanitize` keeps a valid `arena` section (dropped alone).
- `Core/Game/Catcher.lua` (tick): runs `Arena.Tick` (training, expiry, settlement, notices) and publishes.
- `UI/ArenaView.lua` (new): the arena view and the replay; `UI/AzeCaughtPanel.lua`: view button, challenge box.
- Record section `arena = { w, l, ch = { [id] = {to, at, wg, f} }, an = { [id] = {ok, at, f?} }, bt = { [id] = {s, c, o, at} } }`,
  `id = "<challenger>#<at>"`; fighter `f = {npc, n, cls, disp, ty, al, atk, def, spd, vit, ab}`.
- Local `db.caught.arena = { npcs = { [npc] = {xp, w, l, tr = {atk, def, spd, vit}} }, training = {stat, npc, done},
  settled = {[key] = true}, history = {...} }`.

## Tasks
- [x] T1 (L): Arena.lua: fighter, training, levels, battle, odds. Verify: tests/test_arena.lua
- [x] T2 (L): record section + state machine (challenge, answer, bet, expiry, settlement). Verify: tests/test_arena.lua
- [x] T3 (M): Games/Store/Catcher integration, protocol 1.2. Verify: record round trip, test_load
- [x] T4 (L): UI arena view, challenge box, replay. Verify: test_load builds it; in game
- [x] T5 (S): docs, deDE, changelog. Verify: locale test

## Review Focus
1. RF1 Every client computes the same winner: no `math.random`, integer-rounded math, the stored snapshots. Pinned by T1.
2. RF2 Money never doubles: each stake leaves once, each settlement pays once (`settled`), a decline/expiry refunds once. Pinned by T2.
3. RF3 Garbage sections (huge stats, bad names) are dropped alone and never pay. Pinned by T2/T3.
4. RF4 Only the challenged player's answer counts. Pinned by T2.
5. RF5 No bet on my own fight or after the fight time. Pinned by T2.

## Cross-cutting checklist
- [x] Protocol: additive minor 1.1 -> 1.2 (new optional record section; 1.1 peers drop it by allow-list).
- [x] Stored data: no schema bump: `db.caught.arena` is additive and sanitized on load; an older build drops it.
- [x] Trust model: sections sanitized by allow-list with bounds; names via IsSafeName; NPC names escaped in the UI;
  every client computes the result itself and pays only itself.
- [x] Localization: only ids/numbers sent; texts through `addon.Text`, deDE added.
- [x] Load order: Arena.lua after AzeCaught.lua; ArenaView.lua before AzeCaughtPanel.lua.
- [x] Packaging: new files under Core/ and UI/ (already whitelisted).
- [x] Tests: `tests/test_arena.lua` (determinism, money, adversarial sections, answers by others, late bets).
- [x] Docs: README, CHANGELOG, protocol.md, doc.md.

## Decisions
- 2026-11-21 User: "create a fully new async battle system for the companion - use the stats system and level system and
  make them trainable - keep track of wins and loss - let them bet - let them bet against who is winning let the person
  who has been requested accept or decline the fight. Implement depth but fully hands off auto battler", then "dont stop
  till the fighting system is fully implement". No questions possible, so Claude decided:
  - async through the record sync (a new optional section), not new message types: works while offline, reuses the
    guild gate and validation.
  - the battle is computed on every client from the stored snapshots: nobody has to trust a reported result.
  - side bets with fixed odds from the computed win chance (each bettor settles alone), not a pool (a pool needs every
    client to see the same bets).
  - fight time 5 min after the accept (so the guild can bet); challenges expire after 24 h.
  - training: gold + energy + 10 min active time per point; arena levels from XP give +3% per level; kept per NPC.
  - losing costs only the wager; no injuries or lost hearts.
- 2026-11-21 Claude (balance): a first matrix showed a 70% first-mover edge in mirror matches and Smash/Barrier winning
  80-90%; fixed with a random gauge head start and the multipliers in `Arena.MULTIPLIER` (each ability ~1.6 hits),
  Barrier 10% of max health, Smash stuns 50%; pinned by "abilities are balanced".
- 2026-11-21 Claude: a challenge not answered after 24 h "lapses" (no answer possible) but is refunded only after 24 h
  more, so an answer that syncs late still makes the fight happen instead of a refund on one side only.

- 2026-11-21 User: "the gilde -> fight needs a little rework - all the button seem to be overlapping what we would need
  is a multilevel modal when clicking on an the pet of another guild mate then the dialog needs to be only visible and a
  single fighting icon should start the modal. Also add a custom dev version command to add a "fake" enemy and also a
  fake "fight request command"". Claude decided: a click (not hover) selects a pet; the fight icon sits on the preview
  model and shows only for another member's pet; the modal has 3 steps + "sent"; the dummy lives in `Games.simulated`
  (never stored or sent, like `/ggd games sim`); Settle never refunds a challenge whose fight was already settled
  (a vanished record, e.g. the dummy after a reload, must not pay twice).

## Open questions
- Tuning (costs, XP, odds bounds) after playing (needs: user).

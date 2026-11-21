# Companion arena

Status: built, verifying | Since version: GuildGames 0.3.0 (unreleased) | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
Your AZEcaught companion fights other guild members' companions. You challenge someone (with an optional wager), they
accept or decline whenever they are online, and five minutes after the accept the fight is decided on its own: a
hands-off auto battle driven by the companions' stats, arena level, training, hearts, needs and creature-type ability.
The rest of the guild can bet on either side in those five minutes. Wins, losses and XP are kept per companion.

## How to use
- **Guild** view: point at a member's row, enter a wager in gold (0 = just for fun), press **Challenge <name>**.
- **Arena** view, **Fighter** page: your companion's arena level and XP, wins and losses, the four stats (Attack,
  Defense, Speed, Vitality) and **Train** per stat (tooltip: cost, energy, time), the running training and its ability.
- **Arena** view, **Fights** page: incoming challenges (**Accept** / **Decline**), open fights (bet N gold on either
  side at the shown odds), finished fights (**Watch** the replay: both models, health bars, floating damage, shakes,
  the winner's burst; **Skip** jumps to the end).
- Chat tells you about a new challenge, an answer, your fight's result, a bet's result and finished training.
- `/gg arena` (or `/gg caught arena`) opens the view.

## How it works
- **Fighter** (`Arena.Fighter`): attack/defense/speed from `AzeCaught.CombatStats` (level, rarity, creature type, a
  fixed per-NPC spread), vitality = (attack + defense) / 2; each x (1 + 4% per training point) x (1 + 3% per arena
  level above 1) x morale (hearts, -10..+10%); attack -10% while hungry or thirsty. Health = vitality x 8.
- **Battle** (`Arena.Fight`, deterministic from both snapshots and the fight id; Park-Miller RNG, no `math.random`):
  an action gauge filled by speed (random head start 0..25), every 3rd action is the ability, damage =
  attack^2 / (attack + defense) x 0.9..1.1, crit (speed share, 5..30%, x1.5), dodge (5..25%). Abilities: Rend (bleed
  3 turns), Fel Fire (burn 2 turns), Drain (heals half), Barrier (absorbs 10% of max health), Focus (next hit crits),
  Surge (x1.7), Breath (x1.2, half armor), Smash (50% stun), Strike (x1.6). Balanced so each wins 47..55% against all
  others with equal stats (pinned by a test). At most 80 actions, then the higher health share wins.
- **Training**: 50s x (points + 1), 15 energy, 10 min of play time; +1 point (at most 25 per stat); one session at a
  time. **Levels**: win 40 XP, loss 15 XP; level n -> n + 1 needs n x 50 XP; at most level 50.
- **Async flow over the record sync** (no new message types; protocol 1.2 adds the optional record section `arena`):
  `arena = { w, l, ch = {[id] = {to, at, wg, f}}, an = {[id] = {ok, at, f?}}, bt = {[id] = {s, c, o, at}} }`,
  id = `<challenger>#<time>`. A challenge lives in the challenger's record, the answer in the challenged player's
  record, a bet in the bettor's record. Only the named opponent's answer within 24 h counts. Every client computes
  the fight from the two snapshots and settles only its own money, once (`settled`).
- **Money** (the addon's pool, no real gold): the wager leaves at the challenge / accept; the winner gets both stakes;
  a decline refunds at once, no answer refunds after 24 h + 24 h grace (a late-synced answer still counts). Bets:
  fixed odds 0.95 / win chance (1.1x..10x), computed from 40 simulated fights when the bet is placed.
- **Local data** (`db.caught.arena`): per NPC `{xp, w, l, tr}`, the running training, my `ch`/`an`/`bt`, `settled`,
  `noticed`, the last 30 fights; re-validated on load; `/ggd caught reset` clears it.
- **Modules**: `Core/Minigames/Arena.lua` (pure), `Core/Game/Catcher.lua` (tick every 5 s, chat, publish),
  `UI/ArenaView.lua` (view + replay), `UI/AzeCaughtPanel.lua` (tab, challenge box, arena W/L in the guild preview),
  `Core/Data/Games.lua` (section validation, `SetSection("arena")`).

## Localization
All texts through `addon.Text` (enUS keys, deDE translated). Only ids, numbers and NPC names (client text) are sent.

## Limits and known issues
- Results are computed, not proven: a guild member who edits their saved data can fake a strong fighter (trust model).
- If the challenged player accepts and goes offline before the challenger's client saw the answer, the challenger only
  sees it when they meet again; after 48 h without a visible answer the challenger is refunded, so the two pools can
  disagree in that rare case.
- 1.1 clients (0.2.0) drop the arena section: they can't be challenged and don't see fights.
- Tuning (costs, XP, odds) is a first pass.

## Changelog line
- AZEcaught arena: challenge guild members' companions to hands-off auto battles with wagers, train stats, level up, and let the guild bet on the winner.

# 037 Companion roster

Status: verifying (the in-game checks in [verify](verify.md) are open).

## What it does for the player
- Every catch becomes its own companion. Two wolves are two companions, each with its own hunger, thirst, affection,
  energy, hearts, arena XP, wins/losses and training.
- Collection > Caught is the roster: one row per companion ("A n" is its arena level, then its NPC level).
- One companion is active. **Make companion** switches at no cost; the old one rests with everything frozen (no
  needs, no death) and continues exactly where it stopped when it comes back. A running training session is cancelled
  (no refund; the dialog warns first). Nobody runs away anymore.
- **Release** lets one companion go for good (asks first).
- The guild still sees only the active companion.

## How it works
- `db.caught.roster[uid]` (uids `u1`, `u2`, ...) holds every companion; `db.caught.activeID` names the active one and
  `caught.active` points to it. Arena progress is `companion.ar = { xp, w, l, tr }` (`Arena.Progress`).
- `AzeCaught.Reconcile` keeps the roster in step with `collection[npc].caught` (adds fresh companions, drops surplus
  resting ones, keeps the active one). `Select(uid | npcID)`, `Release(uid)`, `Roster()`, `Companion(uid)`.
- Frozen: only the active companion ticks; on switching back `since` and `streakAt` move on by the resting time.
- Training is `arena.training = { stat, uid, done }`; `Arena.CancelTraining` on a switch or release.
- Schema 3. Old data (no roster) is moved in `AzeCaught.SanitizePersisted`: the active companion keeps its state,
  every other catch becomes a fresh companion, the old per-NPC arena progress goes to the active one (same NPC) or
  the first of that NPC, a running training stays with the active one.
- A technical cap of 1000 companions; at the cap the rope refuses ("Your roster is full").

## Limits
- Resting companions show no bars in the roster list (only name and levels).
- Older addon versions refuse the schema 3 saved data ("newer").

## Verification
See [verify.md](verify.md).

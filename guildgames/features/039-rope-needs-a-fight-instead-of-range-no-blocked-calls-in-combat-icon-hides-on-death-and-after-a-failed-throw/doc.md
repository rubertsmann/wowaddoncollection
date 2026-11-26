# 039 Rope needs a fight instead of range: documentation

## What it does
- The rope and the traps need the enemy to be fighting you (you are on its threat list). Before, they needed 28 yards,
  checked with `CheckInteractDistance`, which the client forbids for addons in combat: every nameplate update in a fight
  made the client block GuildGames ("reserved for the Blizzard UI").
- The rope icon is greyed out (and says why in its tooltip and on a click) while the enemy is not fighting you.
- The icon and the catch-item bag hide on a dead enemy (dead flag, or health 0) and after a failed throw (escaped, too
  slow) for as long as that enemy cannot be thrown at again; Second Chance brings it back.

## How it works
- `Api.UnitSnapshot` carries `fighting = Api.IsFightingMe(unit)` (`UnitThreatSituation`), nil when the client does not say.
- `AzeCaught.Throw` / `TrapCatch` refuse `nofight` when `fighting == false`; nil is allowed.
- `AzeCaught.Tried(guid)`: rolled, or thrown without an armed throw. Used by `Catcher.IconHiddenReason` and `CatchItems.Target`.
- `UNIT_THREAT_LIST_UPDATE` refreshes the icon, so it gets its colour when the fight starts.

## Limits
- A pet that tanks: until you hit the enemy yourself you may not be on its threat list, so the icon stays greyed.
- No distance rule any more.

## Verification
See [verify.md](verify.md).

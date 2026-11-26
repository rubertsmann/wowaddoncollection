# 039 Rope needs a fight instead of range (no blocked calls in combat), icon hides on death and after a failed throw: spec

- Status: verifying
- Created: 2026-11-26
- Target version: 0.11.1 (released 2026-11-26)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
The rope and the traps no longer call the protected range check (it made the client block GuildGames in every fight);
they need a fight with the NPC instead, and the rope icon shows that state and goes away when it cannot be used again.

## Background (evidence)
SavedVariables of 2026-11-25: 90 `caught.blocked` entries (24 live, 48+ dev copy, 21:40-21:42), all `combat=true`,
`function=UNKNOWN()`, every stack ending in `read()` -> `pcall(func, ...)` (`Core/Game/Api.lua:143`). The only protected
function going through `read()` is `CheckInteractDistance` (`Api.InRopeRange`), called by `Api.UnitSnapshot` for every
nameplate update. A `pcall` does not stop a block.

## Requirements
- R1: No GuildGames code calls `CheckInteractDistance` (no snapshot field, no throw/trap check, not in `/gg dump`).
- R2: A throw and a trap need the NPC to be fighting the player (player on its threat list); refused with reason
  `nofight` and the text "It is not fighting you: attack it first." when the client says it is not. When the client does
  not say (nil), the throw is allowed (same rule as tapped).
- R3: The rope icon is shown greyed out (desaturated, dimmed) while the NPC is not fighting the player; a click gives
  the R2 refusal; the tooltip says why.
- R4: The rope icon and the catch-item bag hide on a dead NPC, also when the dead flag is hidden but the health reads 0.
- R5: The rope icon and the bag hide after a throw that failed (escaped, too slow), for as long as that NPC cannot be
  thrown at again (also after the 60 s `rolled` memory ended); with the Second Chance charm the icon comes back.

## Non-goals
- No new range rule (the client gives no allowed distance check in combat).
- No change to the blocked-action logger (its stack is cut short; separate fix).

## Design
- `Core/Game/Api.lua` (changed): `InRopeRange` removed; snapshot field `fighting = Api.IsFightingMe(unit)`;
  `UnitDump` drops `interactRange4`.
- `Core/Minigames/AzeCaught.lua` (changed): `Throw` / `TrapCatch` refuse `nofight` when `target.fighting == false`
  (instead of `range`); new `AzeCaught.Tried(guid)` = rolled, or thrown without an armed throw.
- `Core/Game/Catcher.lua` (changed): passes `fighting`; refusal text; `IconHiddenReason` hides on `health == 0` and on
  `AzeCaught.Tried`; `StyleIcon` greys the icon when `snapshot.fighting == false`; tooltip line.
- `UI/CatchItems.lua` (changed): `Target()` uses `AzeCaught.Tried` and `health == 0`.
- `Locales/deDE.lua`: the new text; the range text removed.
- Data / message shape: none.

## Tasks
- [x] T1 (S): AzeCaught `nofight` refusal + `Tried`. Verify: tests/test_azecaught.lua, tests/test_items.lua
- [x] T2 (S): Api: drop CheckInteractDistance, add `fighting`. Verify: grep + test_load
- [x] T3 (M): Catcher icon: grey when not fighting, hide on health 0 / tried; CatchItems same. Verify: test for IconHiddenReason
- [x] T4 (S): locale, CHANGELOG, doc.md. Verify: locale test

## Review Focus
1. RF1: threat unknown (nil) -> throw allowed, icon not greyed. Pinned by: T1 test
2. RF2: Second Chance after a too-slow throw -> not `Tried`, icon back. Pinned by: T1 test
3. RF3: armed throw (thrown + throws) -> not `Tried`, net icon stays. Pinned by: T1 test
4. RF4: pet tanks, player never hit it -> player may not be on the threat list -> greyed (accepted: attack it yourself).

## Cross-cutting checklist
- [x] Protocol: unchanged (nothing sent changes)
- [x] Stored data: unchanged (schema 3)
- [x] Trust model: n/a, local only
- [x] Localization: one new key in deDE, range key removed
- [x] Load order: unchanged
- [x] Packaging: unchanged
- [x] Tests: test_azecaught / test_items cases
- [x] Docs: CHANGELOG (Unreleased), README rope rule, doc.md

## Decisions
- 2026-11-26: "in a fight" means the NPC has the player on its threat list (`UnitThreatSituation`), already read in combat
  without blocks. (user: replace the range check with a combat check)
- 2026-11-26: traps need a fight too ("every call"); before they worked at full health without a fight.
- 2026-11-26: greyed icon stays clickable and explains the refusal, instead of being hidden.

## Open questions
- none

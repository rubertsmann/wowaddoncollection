# B001 Magic trap used up without a message

- Status: reported
- Severity: S2
- Reported: 2026-11-28
- Found in: 0.15.x, reported while verifying feature 034
- Fixed in: -
- Links: [log](log.md)

## Report
- Who saw it: a guild member (told the user)
- Build / version: live 0.15.x
- Where: unknown
- What happened (their words, via the user): "a magic trap had been used without a message anywhere"
- Expected: a used trap prints "{item}: you caught {name}! (+{gold})" in chat; a refused trap keeps the item and shows the refusal (feature 034)
- How often: once reported

## Reproduction
- Steps: not reproduced yet
- Offline repro: none yet

## Hypotheses (not shown yet)
- H1: `guildgames/Core/Game/Catcher.lua` `Catcher.UseTrap`: `addon.Items.Use` consumes the trap, then
  `Catcher.PlayRopeEffect(unit)` runs **before** the chat line; an error in the effect (or in `ChatSafe` / `money`)
  leaves the trap gone and nothing printed.
- H2: the Inventory tab path (`UI/ShopView.lua`, trap branch / `usedElsewhere`) uses a trap without a target.

## Root cause
not found yet

## Fix
- Change: <files and what changed>
- Regression test: <test name; FAIL before, pass after>
- Protocol / schema: <unchanged | decision>
- CHANGELOG: <"Fixed: ..." line under Unreleased>

## Verification
| Check | How | Level | Evidence | Result | Date |
|---|---|---|---|---|---|
| regression test | `luajit tests/run.lua` | OFFLINE | <output line> | | |
| reported symptom gone | in game: use a trap on a normal enemy; chat line shown | NOT-VERIFIED | needs the user | | |

## Open questions
- How did they use the trap: target bag icon, Inventory tab, or target-frame mode? (needs: reporter)
- Their `/gg caught log 20 trap` output right after it happens (needs: reporter)

## Accepted gaps
- none yet

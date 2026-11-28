# B002 Big creatures cut off at the right edge

- Status: reported
- Severity: S3
- Reported: 2026-11-28
- Found in: 0.15.x, in-game check of feature 043
- Fixed in: -
- Links: [log](log.md)

## Report
- Who saw it: the user
- Build / version: 0.15.x
- Where: Survivor and/or Companion Dash (not stated which), with a really big creature
- What happened (their words): "really big creatures are still cut off at the right side"
- Expected: every model fits its box (feature 043 R1)
- How often: with really big creatures

## Reproduction
- Steps: make a very big creature the active companion (or have big monsters in Dash), open the game
- Offline repro: none yet (043's framing test only checks the height fit)

## Hypotheses (not shown yet)
- H1: the 043 fit scales the camera by model **height** only (x1.15, padded frames); a wide model's width or
  horizontal offset is not fitted, which matches a cut on one side. Files: `UI/CompanionModel.lua`,
  `UI/SurvivorArena.lua`, `UI/RunnerView.lua`.

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
| reported symptom gone | in game: same creature in Survivor and Dash, nothing cut off | NOT-VERIFIED | needs the user | | |

## Open questions
- Survivor, Companion Dash, or both? Which creature? (needs: user)
- The "survivor companion was framed" line from `/gg caught log 5 model` (needs: user)

## Accepted gaps
- none yet

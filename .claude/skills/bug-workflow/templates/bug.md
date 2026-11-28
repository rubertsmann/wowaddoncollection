# {{ID}} {{TITLE}}

- Status: reported
- Severity: {{SEVERITY}}
- Reported: {{DATE}}
- Found in: <version, and the feature id if found while verifying one>
- Fixed in: -
- Links: [log](log.md)

## Report
- Who saw it: <role only: the user | a guild member>
- Build / version: <live x.y.z | dev>
- Where: <game/tab, zone type, solo/group, in combat?>
- What happened (their words): "<quote>"
- Expected: <what the spec/doc/README promises>
- How often: <once | always | sometimes>

## Reproduction
- Steps: <exact steps, or "not reproduced yet">
- Offline repro: <test name, or "none yet">

## Hypotheses (not shown yet)
- H1: <suspect `file:line`> because <reason>

## Root cause
<`file:line`: one sentence of mechanism, or "not found yet">

## Fix
- Change: <files and what changed>
- Regression test: <test name; FAIL before, pass after>
- Protocol / schema: <unchanged | decision>
- CHANGELOG: <"Fixed: ..." line under Unreleased>

## Verification
| Check | How | Level | Evidence | Result | Date |
|---|---|---|---|---|---|
| regression test | `luajit tests/run.lua` | OFFLINE | <output line> | | |
| reported symptom gone | <in-game steps> | NOT-VERIFIED | needs the user | | |

## Open questions
- <question> (needs: user | reporter | game | second player)

## Accepted gaps
- none yet

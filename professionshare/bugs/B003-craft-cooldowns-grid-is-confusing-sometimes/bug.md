# B003 Craft cooldowns grid is confusing sometimes

- Status: reported
- Severity: S3
- Reported: 2026-11-28
- Found in: 1.8.0, status review of feature 028
- Fixed in: -
- Links: [log](log.md)

## Report
- Who saw it: the user
- Build / version: live 1.8.0
- Where: Misc Items > Cooldowns grid
- What happened (their words): "works but confusing sometimes"
- Expected: the grid shows at a glance which character's craft cooldown is ready and when the others end (feature 028)
- How often: sometimes

## Reproduction
- Steps: <exact steps, or "not reproduced yet">
- Offline repro: <test name, or "none yet">

## Hypotheses (not shown yet)
- none yet: first find out what is confusing

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
| reported symptom gone | user looks at the grid again | NOT-VERIFIED | needs the user | | |

## Open questions
- What is confusing: wrong or stale times, a cooldown missing until the profession is opened, the tile colours/glow, which character a tile belongs to, sorting? A screenshot of a confusing moment helps most. (needs: user)

## Accepted gaps
- none yet

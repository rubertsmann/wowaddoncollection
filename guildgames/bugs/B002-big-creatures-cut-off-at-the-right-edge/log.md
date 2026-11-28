# B002 Big creatures cut off at the right edge: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <REPORT|TRIAGE|REPRO|HYPOTHESIS|ROOTCAUSE|FIX|TEST|VERIFY|BLOCKED|CLOSED|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-28 10:31 | REPORT | Bug created
- Did: scaffolded `bugs/B002-big-creatures-cut-off-at-the-right-edge/` from the templates
- Result: bug.md has an empty report
- Evidence: n/a
- Next: fill the Report section from the user's words, then hunt (code path, journal, offline repro)

## 2026-11-28 10:31 | TRIAGE | report filled
- Did: report and hypotheses written from the user's status review of feature 043
- Result: status reported; root cause not shown yet
- Evidence: user report 2026-11-28
- Next: answer the open questions in bug.md, then an offline repro for H1

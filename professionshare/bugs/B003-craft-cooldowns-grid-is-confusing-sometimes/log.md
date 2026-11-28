# B003 Craft cooldowns grid is confusing sometimes: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <REPORT|TRIAGE|REPRO|HYPOTHESIS|ROOTCAUSE|FIX|TEST|VERIFY|BLOCKED|CLOSED|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-28 10:37 | REPORT | Bug created
- Did: scaffolded `bugs/B003-craft-cooldowns-grid-is-confusing-sometimes/` from the templates
- Result: bug.md has an empty report
- Evidence: n/a
- Next: fill the Report section from the user's words, then hunt (code path, journal, offline repro)

## 2026-11-28 10:37 | TRIAGE | report filled
- Did: report written from the user's status review of feature 028
- Result: status reported; what is confusing is not known yet
- Evidence: user: "028 works but confusing sometimes" (2026-11-28)
- Next: ask the user what exactly is confusing (screenshot), then decide bug fix vs feature change

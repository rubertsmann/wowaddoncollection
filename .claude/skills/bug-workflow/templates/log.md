# {{ID}} {{TITLE}}: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <REPORT|TRIAGE|REPRO|HYPOTHESIS|ROOTCAUSE|FIX|TEST|VERIFY|BLOCKED|CLOSED|NOTE> | <short title>` then Did / Result / Evidence / Next.

## {{NOW}} | REPORT | Bug created
- Did: scaffolded `bugs/{{ID}}-{{SLUG}}/` from the templates
- Result: bug.md has an empty report
- Evidence: n/a
- Next: fill the Report section from the user's words, then hunt (code path, journal, offline repro)

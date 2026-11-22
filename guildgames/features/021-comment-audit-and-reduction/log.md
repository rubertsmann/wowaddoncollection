# 021 Comment audit and reduction: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-22 12:56 | PLAN | Feature created
- Did: scaffolded `features/021-comment-audit-and-reduction/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-22 13:01 | BUILD | T1-T3 policy, audit tool, libguildsync pass
- Did: docs/comment-policy.md, tools/comment-audit.lua (provenance/path/member/param checks); fixed orphaned or wrong
  annotations it found (guildgames Catcher.lua iconFor, AzeCaught.lua Care, ArenaView.lua fighterLine, Window.lua
  mouseOver; professionshare tests/test_core.lua Names.ProfessionKey). Read every comment of libguildsync against code.
- Result: wrong comments fixed: Locale.lua header (RegisterStrings, not Register), Addon.lua trace order (newest at the
  bottom, not first), Trace.lua header (incomplete transfers are "in" entries), Channel.lua out-statuses (+dropped),
  Utility.lua CanonicalName (realm-free case), accent table (Latin Extended-A, not Cyrillic), SortedKeys comment moved to
  its function; provenance and real names removed from comments; empty "control" banner moved to its section.
  No MINOR bump: comments only (decision: the MINOR rule is about behaviour; recorded here).
- Evidence: libguildsync 37 passed, 0 failed; guildgames 137 passed, 0 failed; professionshare 234 passed, 0 failed;
  comment-audit libguildsync: 19 files, 965 comments, 0 findings
- Next: T4 guildgames pass, starting with Core/Minigames/AzeCaught.lua

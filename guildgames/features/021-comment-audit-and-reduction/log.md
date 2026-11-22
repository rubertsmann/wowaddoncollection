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

## 2026-11-22 13:12 | BUILD | T4 guildgames pass (pilot + every file)
- Did: read every comment of guildgames Core/, UI/, tools/coinflip.lua and tests/ against its code (UI files through a
  comment-plus-context listing). Pilot refactor: AzeCaught.Tick's commented sections and NoteFound's eviction block
  became named local functions (e9ec3da). Dead HOSTILE_FLAG removed in its own commit (f4882c1).
- Result: about 40 wrong or stale comments fixed (see commits 15f78e0, 707627d, f1ed871, fb0c5cb, d6a91a0), e.g. the
  combat log named as a source on a client that forbids it, ProfessionShare's minimap angles in GuildGames' Window,
  the coin flip axis, Survivor's weapon list and factors, misplaced doc blocks (UnitDump, UI.Widgets, pool, iconFor,
  Care), stale state/record class fields, the test clock's date. Provenance gone from non-test code.
- Evidence: luajit tests/run.lua -> 137 passed, 0 failed; comment-audit --code-only on every comment commit -> 0 file(s)
  with code changes; comment-audit guildgames -> 0 findings outside tests
- Next: T5 professionshare pass (Core/Base, Net, Debug, Data, Game, View, UI, tests)

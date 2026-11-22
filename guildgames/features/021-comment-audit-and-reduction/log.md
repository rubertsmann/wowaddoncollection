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

## 2026-11-22 13:20 | BUILD | T5-T7 professionshare, small addons, scripts, lint
- Did: read every comment of professionshare (Core, UI, dev probe, tests), fpvcigarette, foreverbetteruiplus and all
  tools/*.ps1 and make_textures.py against the code; added tests/test_comments.lua (guildgames, professionshare,
  libguildsync) and inline tests (fpvcigarette, foreverbetteruiplus) that run comment-audit --strict; linked the policy
  from both coding-conventions.md and both feature-workflow skills.
- Result: about 30 more wrong or stale comments fixed (2472122, 26b71d6, 3902a18, 3f7326c, d85c5a7); dead Link removed
  from guildgames/tools/deploy.ps1 (c99e945). Comment volume: text -2.2%, line count flat (see doc.md Limits).
- Evidence: guildgames 138 passed, 0 failed; professionshare 235 passed, 0 failed; libguildsync 38 passed, 0 failed;
  fpvcigarette 13 tests, 0 failed; foreverbetteruiplus 8 tests, 0 failed. Planted provenance line ->
  "guildgames/Core/Base/Log.lua:17: [provenance] user 2026-11-22", 137 passed, 1 failed (reverted).
- Next: user decision on the volume target (accept, or a second pass of name-instead-of-comment refactors); in-game
  check of the AzeCaught.Tick refactor (verify.md checklist); then status done.

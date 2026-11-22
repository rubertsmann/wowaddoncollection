# 021 Comment audit and reduction: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work (master 1ad4469): guildgames 137 passed, professionshare 234 passed, libguildsync 37 passed,
fpvcigarette 12 tests, foreverbetteruiplus 7 tests, all 0 failed.
Result after work: guildgames 138 passed, professionshare 235 passed, libguildsync 38 passed, fpvcigarette 13 tests,
foreverbetteruiplus 8 tests, all 0 failed (the +1 in each is the new comment lint).

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence (output line, file, screenshot) | Result | Date |
|---|---|---|---|---|---|---|
| R1 | Written comment policy | `docs/comment-policy.md`; linked from both `docs/coding-conventions.md` and the feature-workflow skills | READ-ONLY | the files | ok | 2026-11-22 |
| R2 | Audit tool finds provenance, dead paths, dead `Module.Name`, `---@param` mismatches | ran on all five addons; it found the orphaned annotations fixed in 14e9558 and a planted provenance line | OFFLINE | `guildgames/Core/Base/Log.lua:17: [provenance] user 2026-11-22` (planted, reverted) | ok | 2026-11-22 |
| R3 | Every comment read against its code; wrong ones corrected | full read of every non-vendored Lua file (UI files through a comment-plus-context listing), tests and the tools scripts; about 70 wrong or stale comments fixed (commit messages list them) | READ-ONLY | commits 14e9558..c99e945 | ok (review, not executable) | 2026-11-22 |
| R4 | No provenance in non-test code | `comment-audit --strict` per addon | OFFLINE | `comment-audit guildgames: 45 files, 3018 comments, 0 findings` (and the same 0 for the other four) | ok | 2026-11-22 |
| R5 | Restating comments removed, long write-ups shortened | module headers of Init/Locale/Log (both addons), AzeCaught, Games, Catcher shortened; AzeCaught.Tick sections became named functions | READ-ONLY | e9ec3da, 707627d, 2472122 | partly: comment volume fell only ~2% (see doc.md) | 2026-11-22 |
| R6 | No behaviour change | every comment commit checked with `comment-audit --code-only HEAD` before commit; all suites after every commit | OFFLINE | `comment-audit --code-only HEAD: 0 file(s) with code changes`; suites as above | ok | 2026-11-22 |
| R7 | Audit `--strict` in every suite | `tests/test_comments.lua` (guildgames, professionshare, libguildsync), inline test in fpvcigarette and foreverbetteruiplus `tests/run.lua` | OFFLINE | suites fail on the planted line: `137 passed, 1 failed` | ok | 2026-11-22 |
| RF1 | an edit that touches code | `--code-only` compares code with comments and whitespace removed | OFFLINE | planted `local planted = 1` -> `CODE CHANGED: libguildsync/LibGuildSync/Core.lua` | ok | 2026-11-22 |
| RF2 | an annotation on the wrong function | audit `param` check | OFFLINE | found Catcher iconFor, AzeCaught Care, ArenaView fighterLine, Window mouseOver | ok | 2026-11-22 |
| RF3 | a comment that is right while the CODE is wrong | reported, fixed in its own commit | READ-ONLY | dead `HOSTILE_FLAG` (f4882c1), dead `Link` in deploy.ps1 (c99e945); no logic bug found | ok | 2026-11-22 |

The two code-changing commits (e9ec3da refactor, f4882c1 / c99e945 dead code) are covered by the unchanged suites;
the refactor was not exercised in the game client.

## In-game checklist (things only the user can do)
- [ ] GuildGames dev build: keep a companion for a few minutes (needs decay, a care action, a zone change). Expected: the
  same journal lines as before (`/gg caught log`), no Lua error. Covers the AzeCaught.Tick refactor e9ec3da.

## Accepted gaps
- R5 volume target (40-60% fewer comment lines from the plan) not met; see doc.md "Limits". Needs the user's decision.

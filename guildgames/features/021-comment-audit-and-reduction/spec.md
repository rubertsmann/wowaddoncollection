# 021 Comment audit and reduction: spec

- Status: done
- Created: 2026-11-22
- Target version: none (no behaviour change; ships with each addon's next release)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md) | policy: [docs/comment-policy.md](../../../docs/comment-policy.md)

## Goal
Every code comment in the monorepo is verified against the code; wrong ones are corrected, history and noise are
pruned, and the policy plus an audit tool keep it that way.

## Requirements
- R1: A written comment policy (keep / remove / prefer a name / never rename) shared by all addons.
- R2: `tools/comment-audit.lua` finds provenance markers, dead paths, dead `Module.Name` references and `---@param`
  names that are not parameters.
- R3: Every comment in every non-vendored Lua file of guildgames, libguildsync, professionshare, fpvcigarette and
  foreverbetteruiplus has been read against its code; wrong comments are corrected.
- R4: Provenance (who/when, feature/requirement/task ids) is removed from non-test code.
- R5: Restating comments are removed; long module write-ups are shortened.
- R6: No behaviour change: every addon's offline suite passes after every commit.
- R7: The audit runs `--strict` clean and is wired into each addon's offline suite.

## Non-goals
- Renaming public constants or anything that leaves the code (see policy "Never rename").
- Vendored code (`Libs/`), locale tables, `features/`, `review/`, `eval/`, `dist/`.
- Logic changes. A comment that reveals a code bug is reported and fixed in its own commit.

## Design
- Files: `docs/comment-policy.md` (new), `tools/comment-audit.lua` (new), comments in every addon source file, one
  line in each addon's `docs/coding-conventions.md` pointing at the policy, a lint test per addon suite.
- Data shape change: none. Message shape change: none.

## Tasks
- [x] T1 (S): policy. Verify: file exists, linked from conventions docs.
- [x] T2 (M): audit tool. Verify: runs on all five addons; findings reviewed by hand (false positives removed).
- [x] T3 (L): libguildsync pass. Verify: its suite + every consumer's suite.
- [x] T4 (L): guildgames pass (pilot: Core/Minigames/AzeCaught.lua first). Verify: `luajit tests/run.lua`.
- [x] T5 (L): professionshare pass. Verify: `luajit tests/run.lua`.
- [x] T6 (S): fpvcigarette + foreverbetteruiplus pass. Verify: their suites.
- [x] T7 (S): audit `--strict` lint in each suite. Verify: suites fail on a planted provenance comment.

## Review Focus
1. RF1: a comment edit that touches code (a trailing comment removed together with code) -> caught by the suites and by
   reviewing `git diff --word-diff` for non-comment changes.
2. RF2: an annotation that moved to the wrong function -> `param` check of the audit.
3. RF3: a comment that disagrees with the code because the CODE is wrong -> reported, not "fixed" in the comment.

## Cross-cutting checklist
- [x] Protocol: unchanged (comments only).
- [x] Stored data: unchanged.
- [x] Trust model: n/a.
- [x] Localization: n/a (Locales/ excluded; no strings change).
- [x] Load order: unchanged.
- [x] Packaging: `tools/` and `docs/` at the repo root are not packaged.
- [x] Tests: audit lint per suite (T7): tests/test_comments.lua and the inline tests.
- [x] Docs: policy, conventions links, workflow skills, doc.md.

## Decisions
- 2026-11-22: provenance and feature/requirement ids leave non-test code entirely; tests may keep requirement ids
  (they name what they pin). Why: the user asked for fewer comments; history lives in git and features/.
- 2026-11-22: existing public constants keep their names (unit comments stay); only new constants carry units in the
  name. Why: renames ripple through UI, tests and string lookups (`AzeCaught[care.price]`) for no behaviour gain.
- 2026-11-22: lua-language-server is not installed; the audit's own `param` check stands in for `--check`.

## Open questions
- none

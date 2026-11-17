---
name: feature-workflow
description: Plan, document and verify a new TalentShare feature (or a non-trivial change) with one fixed folder structure and log format under features/. Use when the user asks to add, plan, design, implement, document, verify or "finish" a feature, or asks what the state of a feature is. Also use to resume an unfinished feature.
---

# Feature workflow (plan -> build -> verify -> document)

Every feature lives in **one folder** with **fixed files**, so anyone (you after a context reset, the user, a reviewer) can read the state in under a minute. Never keep state only in chat.

```
features/
  INDEX.md                      one row per feature: id, title, status, version, link   (read this first)
  <NNN>-<slug>/
    spec.md                     PLAN: goal, requirements, design, tasks (checkboxes), test plan, risks, decisions
    log.md                      APPEND-ONLY journal, fixed entry format (below)
    verify.md                   VERIFICATION MATRIX: requirement -> how -> level -> evidence -> result
    doc.md                      FINAL DOCUMENTATION: what it does, how to use it, data/protocol, limits
    evidence/                   screenshots, saved-variable excerpts, command output (optional; no real names, see rules)
```

Statuses (INDEX.md and the `Status:` line in spec.md, keep both in sync): `planned` -> `in-progress` -> `verifying` -> `done` | `abandoned`.

## Start a feature
1. Read `features/INDEX.md` (does it already exist or overlap?), `docs/status.md`, `review/*.md` (standing findings), `README.md` trust model.
2. Scaffold (creates folder, copies templates, fills id/date, adds the INDEX row, writes the first log entry):
   ```
   powershell -File .claude/skills/feature-workflow/scripts/new-feature.ps1 -Name "Localization layer"
   ```
   If PowerShell is unavailable, copy `templates/*.md` by hand and keep the exact file names.
3. Fill `spec.md` before touching code (Phase 1). Ask the user only about decisions that change the outcome; record every answer under "Decisions".

## Phase 1: Plan (`spec.md`)
- Goal in one sentence, requirements as a numbered list (`R1`, `R2`, ...), explicit non-goals.
- Design: files touched (exact paths), new modules, data shape changes, message shape changes. Keep logic in the **pure modules** (Util, Store, Orders, Codec, Sync, Model) so it is testable offline; WoW calls only in `Core/Game/Api.lua`.
- Tasks as checkboxes `T1..Tn`, each small, independently finishable and verifiable, with its own test/verify line and a complexity `S/M/L`.
- Run the **cross-cutting checklist** (spec.md has it; answer every line, "n/a" with a reason is fine):
  protocol version, SavedVariables schema + migration, trust model, localization (no display strings stored/sent), TOC load order, packaging (`.pkgmeta`, `tools/package.ps1`), tests, docs.
- Review Focus: the 3-5 failure modes a happy-path test would miss, each mapped to a task/test (e.g. empty scan, garbage message, mixed-language peers).
- Do not start Phase 2 until the user has not objected to the plan or has answered the open questions. If the user already said "implement everything", proceed and log the assumption.

## Phase 2: Build (log as you go)
- Work task by task. After each task: tick the box in `spec.md`, append a log entry, commit if the user has asked for commits (message `feat(<slug>): ...`, with the Co-Authored-By trailer the harness gives). Never push or tag unless asked.
- Tests first for pure logic (`tests/test_<slug>.lua`, register in `tests/run.lua` if needed). Run `luajit tests/run.lua` and paste the summary line into the log, not just "tests pass".
- Anything that changes message shape / stored shape needs a `PROTOCOL` / `Store.SCHEMA` decision written down in spec.md "Decisions" before the code (see `review/version-compatibility.md`).
- Deviations from the spec are logged (`DEVIATION`) and spec.md is updated in the same step. The spec must always describe what is true now.

## Phase 3: Verify (`verify.md`)
One row per requirement `R*` and per Review Focus item. Each row has exactly one **level**:
| Level | Meaning | Who/what can set it |
|---|---|---|
| `OFFLINE` | proven by `luajit tests/run.lua` (name the test) | you, with the output line |
| `IN-GAME` | proven in the WoW client (slash command output, screenshot, SavedVariables file) | only with evidence the user supplied or that you read from disk; name the file/screenshot |
| `MULTI-CLIENT` | proven with two real guild members | only with evidence from the user |
| `READ-ONLY` | reasoned from code, nothing executed | honest label, never counts as verified |
| `NOT-VERIFIED` | not checked | say what is needed and from whom |

Rules: never write `IN-GAME` for something only the offline suite covered. Unknown stays `NOT-VERIFIED`. A feature may only become `done` when every requirement is `OFFLINE`, `IN-GAME` or `MULTI-CLIENT`, or the user explicitly accepts the remaining `NOT-VERIFIED` rows (record who accepted and when). Run `review-talentshare` on the change before `done` if it touches the network, the store or the display of peer text.

Things that need the user (ask once, with exact steps, then log it as `BLOCKED`): starting the game, `/console scriptErrors 1`, slash commands and screenshots, a second guild member, CurseForge actions.

## Phase 4: Document (`doc.md` + shared docs)
- `doc.md`: what the feature does for the player, how to use it (commands/UI), how it works (data shape, messages), limits and known issues, localization notes, how it was verified (link `verify.md`).
- Update, in the same step: `README.md` (user-visible behaviour), `CHANGELOG.md` (create it if missing; one line per feature under the version), `docs/status.md` (verification state), `docs/api-findings.md` if a client API fact was learned. Bump `## Version:` in the TOC only when releasing, and then also check `.pkgmeta`.
- Set status `done` in INDEX.md and spec.md, with the commit hash(es) in INDEX.md.

## Log format (`log.md`, append only; never edit or delete old entries, add a correction entry instead)
Get the time from the system (`Get-Date -Format "yyyy-MM-dd HH:mm"`), never guess it.
```
## 2026-11-16 14:05 | BUILD | T3 profession ids in Store
- Did: <what changed, files with paths>
- Result: <outcome in one line>
- Evidence: <command + the exact output line, or file path of a screenshot>
- Next: <next concrete step>
```
`PHASE` is one of `PLAN`, `DECISION`, `BUILD`, `TEST`, `VERIFY`, `DOC`, `DEVIATION`, `BLOCKED`, `DONE`, `NOTE`. One entry per meaningful step; a `BLOCKED` entry states exactly what is needed and from whom. The newest entry goes at the **bottom**; the last entry must always say what to do next, so a fresh session can resume from `log.md` alone.

## Resuming
Read `features/INDEX.md`, then the feature's `log.md` (last 3 entries), `spec.md` task checkboxes and `verify.md`. Continue at the "Next" of the last entry. Do not redo ticked tasks; re-run the offline suite first to confirm the baseline.

## Rules
- One source of truth per fact: requirements in spec.md, evidence in verify.md, history in log.md, final text in doc.md. Link, do not copy.
- No secrets, tokens, real character or realm names in any file or evidence (blur or replace them). `features/` is dev-only; it must stay in `.pkgmeta` ignore.
- Be exact and short; tables over prose; paths as `file:line` where useful.
- Report outcomes faithfully: failing tests, skipped steps and unverified rows are written down, not smoothed over.

## Project quick reference
Lua 5.1 addon for WoW Forever (interface 16001). Tests: `luajit tests/run.lua` (LuaJIT at `%LOCALAPPDATA%\Programs\LuaJIT\bin`). Deploy: `powershell tools/deploy.ps1`. Package: `powershell tools/package.ps1`. In game: `/ts version|scan|dump|comm|hello|chars|debug`. Pure modules vs client-only modules, wire protocol and trust model: see `.claude/skills/review-talentshare/SKILL.md`.

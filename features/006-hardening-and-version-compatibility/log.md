# 006 Hardening and version compatibility: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-16 10:36 | PLAN | Feature created
- Did: scaffolded `features/006-hardening-and-version-compatibility/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-16 10:41 | PLAN | Spec written
- Did: filled spec.md (R1-R14, T1-T9, RF1-RF7, decisions); copied `review/` and `.claude/skills/review-talentshare/` from the main checkout into this worktree (they were untracked there); worktree `.claude/worktrees/fix-package-zip` on branch `fix/package-zip-paths`; baseline `luajit tests/run.lua` = 59 passed, 0 failed
- Result: plan ready; no task ticked yet (an early draft pre-ticked them by mistake and was reset before any code)
- Evidence: features/006-hardening-and-version-compatibility/spec.md
- Next: T1 write tests first in tests/test_hardening.lua, then util helpers and parser change

## 2026-11-16 10:48 | BUILD | T1-T5 core changes
- Did: `Core/Util.lua` (IsFinite, SafeInt, StripControl, CleanString, IsSafeName, Esc; Debug.Log escapes), `Core/Codec.lua` (non-finite rejection, CHUNK/MAX_PARTS/MAX_ENCODED defined once, Header/ParseHeader/Compat), new `Core/Guard.lua` (+ TOC entry after Codec), `Core/Comm.lua` (gate first, header, session salt, roster cache, notices, `/ts comm` fields), `Core/Store.lua` (SCHEMA 2, Migrate, SanitizePersisted, SanitizeChar, SanitizeCatalogEntry, PutCatalog sanitizes, Init returns sv + status), `Core/Orders.lua` (Sanitize exported, bounds, names, control chars), `Core/Sync.lua` (rev bound, SNAP allow-list, catalog ids restricted), `Core/Model.lua` (escapes), `Core/Events.lua` (status handling, notice), `Core/Init.lua` (PROTO_MAJOR 2 / MINOR 0, version from metadata), locales (4 notices)
- Result: compiles; the 59 pre-existing tests still passed before new tests were added
- Evidence: `luajit tests/run.lua` -> `59 passed, 0 failed`
- Next: tests, then docs

## 2026-11-16 10:48 | TEST | tests/test_hardening.lua + harness updates
- Did: 30 new tests (RF1-RF7); `tests/run.lua` harness now sets PROTO_MAJOR/MINOR and loads Guard and Comm; `test_core`, `test_sync`, `test_soak` updated to use `ns.PROTOCOL` instead of a literal 1 (three older tests were silently passing for the wrong reason: messages with `v = 1` were dropped as the wrong version)
- Result: first run 84 passed / 3 failed. Failures were real: Init(nil) reported "reset" instead of "ok", locale codes in saved profNames were not charset-checked, workflow not yet updated. All fixed.
- Evidence: `luajit tests/run.lua` -> `87 passed, 0 failed`
- Next: mutation check, self-review

## 2026-11-16 10:48 | TEST | Mutation check
- Did: broke each protection individually (gate, parser inf check, catalog id restriction, note escaping, downgrade guard, foreign-major rejection) and ran the suite
- Result: every mutation made at least one test fail (3, 1, 1, 1, 1, 2 failing); files restored
- Evidence: after restore `luajit tests/run.lua` -> `89 passed, 0 failed` (see verify.md)
- Next: self-review against the review-talentshare checklist

## 2026-11-16 10:48 | DEVIATION | Clock horizon found in self-review
- Did: while reviewing noticed that bounding timestamps by `now + 1 day` would delete ALL saved orders/records on load if the server time were not yet available (reads 0). Added `Store.Horizon()` (unbounded below 1e9), used by SanitizeChar, Orders.Sanitize and the HELLO rev check; new test `store: an unsynced clock (server time 0) never wipes saved data...`; bound tests now use a realistic clock (`h.ns({ now = 1.8e9 })`). Spec Decisions updated.
- Result: suite green
- Evidence: `luajit tests/run.lua` -> `89 passed, 0 failed`
- Next: docs

## 2026-11-16 10:48 | DOC | Docs, hygiene, review correction
- Did: `docs/protocol.md`, `docs/vendored-libs.md`, CHANGELOG (0.3.0 unreleased), README (trust model + compatibility), `docs/status.md`, `.gitignore` (screens-debug/), `release.yml` (v* tags, tag/TOC check, token scoped to the packager step), review files marked with status; review skill facts refreshed. CORRECTION: my earlier review claimed LibDeflate had a local modification at line 2956; that comment is upstream's own, now stated in `docs/vendored-libs.md` and `review/security-and-gaps.md`. Package script run: 23 files, all TOC files present, no backslash names.
- Result: documentation matches the code (README/protocol claims about roster fail-closed behaviour right after login are READ-ONLY)
- Evidence: `powershell tools/package.ps1` -> `built ...TalentShare-0.2.0.zip (23 files)`
- Next: user runs the in-game checklist in verify.md (needs the game and ideally a second guild member); then decide on commit/merge. Nothing is committed.

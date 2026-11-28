---
name: bug-workflow
description: Use when a bug, error, wrong behaviour or player report comes up for any addon of the wowaddons monorepo (GuildGames, ProfessionShare, LibGuildSync, ...): a Lua error, "it did X without a message", something cut off or missing, a failed in-game check, a journal/SavedVariables line that looks wrong, or when asked to hunt, triage, track, list, fix or close bugs or issues, or what the state of a bug is.
---

# Bug workflow (report -> reproduce -> root cause -> fix -> verify)

Sister of `feature-workflow`: same monorepo layout, same log format, same verification levels. Bugs live in their own
folders so a report never gets lost in chat and a fresh session can resume from the files alone.

**Bug or feature?** The code does something other than its spec/doc/README says, errors, loses data or money, or a
player is confused by missing feedback -> **bug** (this skill). New or changed behaviour nobody promised -> feature
(`feature-workflow`). A bug found while verifying a feature: open the bug here, link both ways (bug `Found in:` the
feature id; the feature's verify.md row says "moved to B<NNN>").

```
<addon>/bugs/
  INDEX.md                     one row per bug: id, title, severity, status, found in, fixed in, link   (read this first)
  B<NNN>-<slug>/
    bug.md                     report, repro, root cause, fix, regression test, verification (one file, sections fixed)
    log.md                     APPEND-ONLY journal, same format as features (phases below)
    evidence/                  journal excerpts, SavedVariables excerpts, screenshots (no real names)
```

Ids `B001`, `B002`, ... are unique across the monorepo (the script scans every `<addon>/bugs`). `bugs/` is dev-only:
it must be in each addon's `.pkgmeta` ignore list; `tools/package.ps1` ships an allow-list, so it never ships.

## Statuses (INDEX.md and the `Status:` line in bug.md, keep both in sync)
`reported` -> `confirmed` (reproduced or root cause shown in code) -> `fixing` -> `verifying` (fix built, OFFLINE green,
in-game check open) -> `fixed` | `wontfix` | `duplicate` (of B<NNN>) | `cannot-reproduce`.

Severity: `S1` data/money loss, Lua error that breaks the addon, blocked action in combat | `S2` feature wrong or
silent (e.g. an item used up without a message) | `S3` cosmetic (cut off, misaligned, wrong colour).

## 1. Report (status `reported`)
```
powershell -File .claude/skills/bug-workflow/scripts/new-bug.ps1 -Name "Magic trap used up without a message" -Root guildgames -Severity S2
```
Fill the **Report** section of bug.md at once, from the user's own words (quote them), even if half is unknown:
who saw it (role only: "the user", "a guild member"), build/version, where (zone type, which game/tab, solo/group,
in combat?), what happened, what was expected, how often. Unknowns go under **Open questions** with who can answer.
Ask the user only the questions whose answer changes where you look; log the rest as open.

## 2. Hunt and reproduce (target: `confirmed`)
Use `superpowers:systematic-debugging`: no fix before the root cause is shown. Where to look, cheapest first:
1. The code path end to end: find every caller (Grep), read the success path and every early return; note the order of
   side effects (state changed / item consumed **before** the feedback line is printed is a classic silent bug).
2. The addon's own journal and dumps (GuildGames `/gg caught log <n> <filter>`, e.g. `model` for every load and pose of a
   3D model view (`UI/ModelView.lua`, journal area `caught.model.<area>`), dev `/ggd ...`; ProfessionShare
   `/ps debug`, `/ps export`), and the SavedVariables the user can send. Copy only the relevant lines into `evidence/`,
   names replaced.
3. An offline reproduction: a failing test in the addon's suite (`luajit tests/run.lua`) with stubs that force the
   reported condition (a throwing effect, a missing frame, a secret value, a big model). Paste the FAIL line in the log.
4. The wow-ui-sim simulator (if it is set up on this machine; it is not part of the repo) for layout bugs; it counts
   as SIM, never IN-GAME.
5. Only then ask the user for an in-game repro, with exact steps and the command whose output you need (`BLOCKED`).

Write **Root cause** as `file:line` + one sentence of mechanism. A suspect that is not yet shown stays under
**Hypotheses** and the status stays `reported`.

## 3. Fix (`fixing`)
- The regression test exists and fails **before** the fix (log the FAIL line), passes after (log the summary line).
  If no offline test can express it, say why in bug.md and name the in-game check instead.
- Smallest fix at the root cause; no unrelated refactors. A fix that changes message or stored shape needs the
  protocol/schema decision written in bug.md first (same rules as features, `<addon>/docs/protocol.md`).
- Code comments never carry bug ids, dates or "user said" notes (`docs/comment-policy.md`); history lives here and in git.
- Add a line to the addon's `CHANGELOG.md` under `## Unreleased` ("Fixed: ..."), in player language for the release notes.
- Commit only when the user asks: `fix(<addon>): <what> (B<NNN>)` with the harness's Co-Authored-By trailer.

## 4. Verify and close
Fill the **Verification** table with the same levels as features: `OFFLINE` (test name + output line), `SIM`,
`IN-GAME` / `MULTI-CLIENT` (only with evidence from the user or from disk), `READ-ONLY`, `NOT-VERIFIED`.
- `fixed` needs the regression test OFFLINE **and** the reported symptom gone at the level it was seen (an in-game
  report needs an in-game confirmation), or the user explicitly accepts the gap (who, when, quote).
- Set `Fixed in` (version) when it ships; the release skill turns the CHANGELOG line into the player notes.
- `wontfix` / `cannot-reproduce` / `duplicate` need one line of reason in bug.md and the log.

## Log format (`log.md`, append only, newest at the bottom)
Get the time from the system (`Get-Date -Format "yyyy-MM-dd HH:mm"`), never guess it.
```
## 2026-11-28 14:05 | ROOTCAUSE | trap consumed before the chat line
- Did: <what, files with paths>
- Result: <outcome in one line>
- Evidence: <command + exact output line, or evidence/ file>
- Next: <next concrete step>
```
Phases: `REPORT`, `TRIAGE`, `REPRO`, `HYPOTHESIS`, `ROOTCAUSE`, `FIX`, `TEST`, `VERIFY`, `BLOCKED`, `CLOSED`, `NOTE`.
The last entry always says what to do next. Corrections are new entries, never edits.

## Listing and resuming
- "What bugs are open?": read every `<addon>/bugs/INDEX.md`; report open rows by severity, then status, with what each
  one waits for (the last log entry's `Next`).
- Resume: INDEX row -> bug.md (Status, Root cause, Open questions) -> last 3 log entries -> continue at `Next`.
  Re-run the offline suite first.

## Rules
- One source of truth per fact: the report and the fix in bug.md, history in log.md, evidence in `evidence/`.
- No secrets, real character, realm or player names anywhere (reporters by role). No local paths.
- Report outcomes faithfully: a fix without the in-game confirmation is `verifying`, not `fixed`.

# 025 Reputation list with faction hints: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-24 09:18 | PLAN | Feature created
- Did: scaffolded `features/025-reputation-list-with-faction-hints/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-24 09:20 | PLAN | spec written
- Did: filled spec.md (R1-R9, RF1-RF5, T1-T9, cross-cutting checklist, decisions from the conversation)
- Result: user said "go ahead implement it"; assumptions logged under Decisions
- Evidence: spec.md
- Next: T1 shared search matcher

## 2026-11-24 09:22 | DECISION | hints as en/de text, no item ids shipped
- Did: item ids found online could not be checked against Forever; a wrong id would show a wrong item
- Result: data file supports `items`, ships none; update skill adds them after an in-game check
- Evidence: spec.md Decisions
- Next: build

## 2026-11-24 09:30 | BUILD | T1-T8
- Did: Model.SearchWords/MatchesWords (recipe search uses them); Core/Data/FactionHints.lua (static data); Core/Data/Reputation.lua;
  Store schema 8 (rep table, migration 7, clean, reset, prune, canonical names, sanitize); Sync record kind rep (protocol 2.6);
  Api.ScanReputation/FactionName/StandingLabel; Events UPDATE_FACTION + login scan + retry + /ps rep; Diagnostics lines;
  MiscTables mode reputation; Window filter dropdown, row fill, hint tooltip, detail text; deDE strings;
  .claude/skills/update-faction-hints/SKILL.md; tests test_reputation, test_reputation_model, test_reputation_api, test_load
- Result: all offline tests pass
- Evidence: `luajit tests/run.lua` -> 294 passed, 0 failed (baseline 269)
- Next: docs

## 2026-11-24 09:34 | DOC | README, CHANGELOG, protocol.md section 14, status.md, doc.md, verify.md
- Did: documented the feature; dev TOC regenerated with tools/deploy.ps1
- Result: status verifying; in-game rows NOT-VERIFIED
- Evidence: verify.md
- Next: BLOCKED on the user: in-game checklist in verify.md (`/psd rep` output first: API and faction ids on Forever)

## 2026-11-24 09:45 | BUILD | click on a player name whispers
- Did: user asked that clicking the names starts a whisper. UI/Table.lua Table.SetCellClick (invisible button over a
  cell's text, only as wide as the name; hidden when the column is hidden or the row is reused); UI/Window.lua Reputation
  rows use it for the Player column (not on my own rows); tooltip line and deDE string updated
- Result: offline suite passes; the click itself is not verifiable offline
- Evidence: `luajit tests/run.lua` -> 294 passed, 0 failed
- Next: BLOCKED on the user: in-game checklist in verify.md (incl. the new name-click row)

## 2026-11-24 10:10 | VERIFY | first in-game scan (dev build, Horde character)
- Did: user reloaded; read the stored rep record from WTF/.../SavedVariables/ProfessionShare-Dev.lua (schema 8)
- Result: GetFactionInfoByID works on Forever; 12 factions stored with plausible standings and bar sizes. Bug: Stormpike
  Guard (730) and League of Arathor (509), Alliance-only, stored as Hated 0/36000 on a Horde character
- Evidence: ProfessionShare-Dev.lua rep record (character name not copied here)
- Next: fix

## 2026-11-24 10:12 | BUILD | skip the other side's factions
- Did: FactionHints `side` for Alliance/Horde-only factions (cities, battleground factions, Wintersaber Trainers);
  Api.ScanReputation skips the other side (UnitFactionGroup) and also treats Hated 0 as untouched; new api test
- Result: the next scan drops 730/509 from the record (a level change, shared at once)
- Evidence: `luajit tests/run.lua` -> 295 passed, 0 failed
- Next: user /reload, `/psd rep` no longer lists 730/509 as standings; rest of the in-game checklist

## 2026-11-24 10:20 | VERIFY | in-game check by the user
- Did: user ran the in-game checklist in the dev build after the side fix
- Result: user: "everything works fine in that feature" (list, filter, search, hints tooltip, name click, /psd rep)
- Evidence: user statement in the session
- Next: still NOT-VERIFIED: progress sharing over time and two members on 1.4.0 syncing (MULTI-CLIENT); then status done

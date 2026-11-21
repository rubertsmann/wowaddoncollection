# 008 Sync diagnostics: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-16 15:28 | PLAN | Feature created
- Did: scaffolded `features/008-sync-diagnostics/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-16 15:39 | PLAN | Analysis of the 0.4.0 sync failure
- Did: read Comm/Sync/Codec/Guard/Store/Util/Events/Orders in full; wrote review/sync-0.4.0-diagnosis.md
- Result: every working path is a GUILD broadcast, every failing path a WHISPER round trip; five name-string comparisons on that path; two real bugs (B1 WhisperTarget trusts Ambiguate for my own realm, B2 identity captured before PLAYER_LOGIN)
- Evidence: READ-ONLY (code + user symptom); baseline `luajit tests/run.lua` -> 134 passed, 0 failed
- Next: build the trace, decisions, tab and export; fix B1/B2 only

## 2026-11-16 15:39 | BUILD | T1-T6 trace, decisions, identity check, Debug tab, export, B1/B2 fixes
- Did: new Core/Trace.lua, Core/Diag.lua, tests/test_diagnostics.lua; changed Core/Comm.lua, Sync.lua, Store.lua, Api.lua, Events.lua, Util.lua, UI/Window.lua, Locales/deDE.lua, TalentShare.toc, tests/run.lua, tests/test_load.lua, tests/test_whisper_target.lua; ran tools/deploy.ps1 (dev TOC regenerated)
- Result: all requirements built; no protocol or schema change
- Evidence: `luajit tests/run.lua` -> 150 passed, 0 failed
- Next: user runs the in-game checklist in verify.md, then two members export (review/sync-0.4.0-diagnosis.md section 5); then decide R1-R6 from the reports

## 2026-11-16 16:09 | DECISION | Implement the recommended changes now
- Did: user asked to continue and implement; superseded the "no fix before export" decision (spec Decisions)
- Result: R1, R2, R3, R5, R6 in scope; R4 out (scalability)
- Evidence: user message "continue and implement it."
- Next: build T8-T10

## 2026-11-16 16:09 | BUILD | T8-T10 canonical names, retry over GUILD, order name snapshot (protocol 2.2)
- Did: Core/Util.lua (Canon, IsMyRealm, LearnMyRealm, LearnFromRoster, RealmAliases), Core/Api.lua (roster learning + Canon), Core/Store.lua (Recanon), Core/Comm.lua (LearnFromEcho on GUILD only, Recanon, HELLO every 15 min), Core/Events.lua (Recanon at login), Core/Sync.lua (rewritten pull logic: _pull/_retry/_answer, canonical comparisons, canonOrder), Core/Orders.lua + Core/Model.lua + UI/Window.lua (name/loc), Core/Init.lua (PROTO_MINOR 2), Core/Trace.lua (via in summary), Core/Diag.lua; tests/test_canon.lua; docs/protocol.md section 8, CHANGELOG, review section 8, docs/status.md
- Result: all built; mutation check: sending the retry by whisper instead of GUILD -> 2 tests FAIL, restored -> pass
- Evidence: `luajit tests/run.lua` -> 159 passed, 0 failed
- Next: user restarts the game with the dev build (no TOC change since the last deploy), runs verify.md in-game checklist; release 0.4.1 to the guild (bump TOC Version), then two members confirm recipes/items sync or send exports

## 2026-11-16 16:36 | BUILD | Name check table (Debug tab, /ts ident, export)
- Did: Core/Diag.lua IdentityRows/IdentityContext/FormatIdentityRow/StatusLabel; Core/Comm.lua remembers raw senders (seen, lastEcho); UI/Window.lua Debug tab toggle "Name check" with columns Status/Method/Value/Expected/Behaviour (location + full behaviour in tooltip); deDE strings; test `name check: statuses for agreeing, normalized and broken name sources`
- Result: one row per name source (method, location, value, expected, behaviour, status ok/normalized/problem/info/unknown)
- Evidence: `luajit tests/run.lua` -> 160 passed, 0 failed
- Next: in game: Debug tab -> Name check (or /ts ident); send the table with the export

## 2026-11-16 16:42 | VERIFY | First in-game export: root cause found (surnames)
- Did: read the user's /ts export (dev build, one member, 58-member guild)
- Result: UnitName("player") = "Drakk", "Nuk"; roster and chat sender = "Drakk Nuk"; realm "CAMWOW EU4 Realm 5 PvE". The surname is part of the identity; my key "Drakk-<realm>" matched no other source; my own echo was treated as another player
- Evidence: export lines "UnitName: Drakk realm=Nuk", "roster sample (raw): Drakk Nuk, ...", "<- GUILD Drakk Nuk-... (raw Drakk Nuk) HELLO", "me in cached roster: NO"; recorded in docs/api-findings.md
- Next: fix identity

## 2026-11-16 16:42 | BUILD | Surname identity
- Did: Api.MyBaseName ("First Surname" from UnitName's 2nd value), Util.NoteMyFullName / SetRosterNames / Canon completes unambiguous bare first names; roster index refresh triggers Recanon; IdentityInfo finds my roster entry by full name; name check rows updated; VERSION no longer "-dev-dev"; tests/test_forever_names.lua (6) from the export values
- Result: me = "Drakk Nuk-CAMWOWEU4Realm5PvE"; in roster; echo recognised; 0.4.0 keys migrate
- Evidence: `luajit tests/run.lua` -> 166 passed, 0 failed; mutation (surname detection off) -> 4 FAIL, restored -> pass
- Next: user /reload (no TOC change), Debug tab -> Name check: expect no PROBLEM rows; then a second member on the same build: /ts hello, both export

## 2026-11-16 16:44 | VERIFY | Second export: identity fixed in game; mixed 0.4.0/0.4.1 guild
- Did: read the second export; added Util.LegacyName + Sync.AskNames (requests carry "First-Realm" too); test `forever: requests also carry the 0.4.0 first-name form ...`; ran the real 0.4.0 Sync (git 7c0a09b) against 0.4.1 offline with Forever names
- Result: in game all name-check rows OK, me in roster, echo recognised, old keys migrated (char, offers, order requester). No peer traffic: the dev build uses prefix TShareDev, the guild runs live TShare. Offline interop: 0.4.1 holds the 0.4.0 member's record, 0.4.0 holds the 0.4.1 member's record
- Evidence: export "me in cached roster: yes (cached roster 58 names)", all [OK]; interop script output "0.4.1 holds Mira: 200", "0.4.0 holds Drakk: 100"; `luajit tests/run.lua` -> 167 passed, 0 failed
- Next: bump TOC to 0.4.1, package, install as live for 2+ members (or two members on the dev build), /ts hello, check Recipes/Available tabs; exports if not

## 2026-11-16 21:27 | VERIFY | Live 0.4.1 export: guild spans several realms
- Did: read the user's /ts export (live build, 4 updated/old members online)
- Result: peers ask for "Drakk Nuk-CAMWOWEU4Realm3PvE", "...Realm1PvE", "Drakk Nuk-CAMWOWEU5Realm3PvE"; I am "...Realm5PvE": 41 WANT + 33 WANTO ignored as name mismatch; characters held 1. Orders arrive (no name compare). Roster/senders carry no realm, whispers to bare names arrive
- Evidence: trace lines "asked for Drakk Nuk-CAMWOWEU4Realm3PvE but I am Drakk Nuk-CAMWOWEU4Realm5PvE (name mismatch)"; order keys Tam-CAMWOWEU4Realm1PvE, Orin-CAMWOWEU4Realm3PvE
- Next: realm-free identity

## 2026-11-16 21:27 | BUILD | Realm-free identity, 0.4.2
- Did: Util.RealmFree (surname known or roster without realm suffixes) makes every realm "mine" in IsMyRealm/Canon/WhisperTarget; Util.IsRealmSpelling keeps the old check for surname detection; Sync answers whispers with my record under the asked name (0.4.0 compares exactly) and adds "First-<peer realm>" to requests (peer realm learned from its WANT names); name check row; version 0.4.2
- Result: tests/test_forever_names.lua +2 tests from the export values
- Evidence: `luajit tests/run.lua` -> 169 passed, 0 failed (5 runs); mutation RealmFree=false -> 3 FAIL, asAsked off -> 1 FAIL
- Next: live test with two members on different realms; both export

## 2026-11-16 21:31 | BUILD | Reset peer data on version change
- Did: user report "switching versions sometimes breaks the UI; only /ts clean confirm + reload fixes it". Store.ResetPeerData (peer chars/offers, their catalog entries, hidden, trace; keeps mine + orders) runs at PLAYER_LOGIN after Recanon when db.version differs from the TOC version
- Result: tests/test_version_reset.lua
- Evidence: see test run below; the exact UI breakage was not reproduced (no screenshot/export of the broken state)
- Next: if it happens again after 0.4.2, /ts export in the broken state

## 2026-11-16 22:05 | VERIFY | Live 0.4.2 in the guild
- Did: release 0.4.2 used by about 6 guild members on several realms
- Result: user reports that recipe, recipe item and order sync work as expected
- Evidence: user report (no export attached)
- Next: merge release/0.4.2 to master, tag v0.4.2; review-talentshare run before marking 008 done

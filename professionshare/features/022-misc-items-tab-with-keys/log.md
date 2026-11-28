# 022 Misc items tab with keys: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-23 20:37 | PLAN | Feature created
- Did: scaffolded `features/022-misc-items-tab-with-keys/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-23 20:49 | PLAN | Spec written, user decisions recorded
- Did: filled `spec.md` (R1-R8, T1-T8, RF1-RF5, cross-cutting checklist). Researched keys: item class 13 (Key) is the grouped flag; curated allow/deny lists for entry items outside class 13 and instance-only keys. Sources: warcrafttavern.com "wow-classic-keys-and-attunements", warcraft.wiki.gg "Instance_attunement_(Classic)".
- Result: user chose Attunements as the third mode, "who holds it" for keys (+ maybe a party/raid portrait icon -> R8 stretch), own record pulled on change for sync.
- Evidence: spec.md "Decisions"
- Next: user confirms the plan (deDE label "Sonstiges", stretch R8), then T1 `Core/Data/Access.lua` + `tests/test_access.lua`

## 2026-11-23 20:58 | DECISION | Table rework added, implement everything
- Did: user asked to "rework the table view to be more inline with the recipe but having for each type different columns which different column configurations - implement it". Added R9/T9 to spec.md.
- Result: proceed with T1-T6, T8, T9 without a further plan review (user said implement)
- Evidence: spec.md "Decisions"
- Next: T1 Access.lua

## 2026-11-23 21:02 | BUILD | T1-T3 access record, store schema 6, sync kind
- Did: new `Core/Data/Access.lua`; `Core/Data/Store.lua` (schema 6, `access` table in init/sanitize/clean/reset/prune/canonicalize, migration 5); `Core/Net/Sync.lua` record kind `access` (arev/WANTA/ACCESS); `Core/Base/Init.lua` protocol 2.4; TOCs + `tests/run.lua`; new `tests/test_access.lua`; `tests/test_hardening.lua` 015 test no longer pins 2.3/5 (pins moved to test_access).
- Result: all green
- Evidence: `luajit tests/run.lua` -> 249 passed, 0 failed
- Next: T4 scan API

## 2026-11-23 21:05 | BUILD | T4 Api.ScanAccess, events, /ps access
- Did: `Core/Game/Api.lua` `Api.QuestDone`, `Api.ScanAccess` (bags, KEYRING_CONTAINER if present, bank while open; attunements from quests + item count); `Core/Game/Events.lua` access scan inside the debounced item scan, `QUEST_TURNED_IN`, `ACCESS_CHANGED` -> HELLO, `/ps access [scan]`; 2 tests in `tests/test_items_api.lua`.
- Result: green
- Evidence: `luajit tests/run.lua` -> 251 passed, 0 failed
- Next: T5/T9 model and column tables

## 2026-11-23 21:10 | BUILD | T5, T6, T9 model rows, ColumnTable, Misc Items tab
- Did: `Core/View/ColumnTable.lua` (generic, from RecipeTable), `Core/View/RecipeTable.lua` on top of it (API unchanged), `Core/View/MiscTables.lua` (modes, per-mode columns/sort settings), `Core/View/Model.lua` (`BuildKeyRows`, `BuildAttunementRows`, `KeyContact`), `UI/Window.lua` (tab "Misc Items", mode dropdown, Columns menu, header + table list, per-mode fill and detail text, "Whisper a holder"), `UI/Table.lua` (header label function), `Locales/deDE.lua` (new strings; "Available", "{n} dib(s)" removed as unused), `Core/Debug/Diagnostics.lua` (access in export); `tests/test_access_model.lua`, mode switching in `tests/test_load.lua`.
- Result: one bug found by test_load and fixed: during a mode switch the relayout redrew the previous mode's rows with the new fill function; rows now carry their mode.
- Evidence: `luajit tests/run.lua` -> 257 passed, 0 failed (three runs; one order-dependent assertion fixed)
- Next: docs

## 2026-11-23 21:14 | DEVIATION | R8 deferred, "online first" dropped
- Did: R8 (party/raid portrait icon, user: "maybe") not built; R2 "online first" removed (no online state is kept). spec.md updated.
- Result: R8 row NOT-VERIFIED / deferred in verify.md
- Evidence: spec.md "Decisions"
- Next: build R8 after the lists are checked in game, if the user still wants it

## 2026-11-23 21:16 | DOC | Docs updated, status verifying
- Did: doc.md, verify.md, README.md, CHANGELOG.md (Unreleased), docs/protocol.md (section 12, schema table), docs/status.md, INDEX.md.
- Result: offline proven; in-game checklist in verify.md open
- Evidence: verify.md
- Next: user runs the in-game checklist in verify.md (`/ps access scan` output first: key ring, quest API, ids); then R8 decision

## 2026-11-23 21:24 | BUILD | Dev buttons: fake keys, fake Naxxramas
- Did: user asked for two Debug-tab buttons hidden in the live build: one adding Naxxramas, one adding fake keys of a fake other member. `UI/DevProbe.lua` `DevProbe.AddFakeKeys` (6 keys + mc/ony on "Fake Keyholder") and `DevProbe.AddFakeNaxxramas` (naxx attunement on the same record), `/ps fakekeys`, `/ps fakenaxx` (dev only); `UI/Window.lua` two buttons in the dev-only block of the Debug tab (second row, left of "Fake request"); `Core/Data/Store.lua` access prune honours `Store.keptNames`; deDE strings; tests in `test_load.lua` (both identities: commands only in dev) and `test_access.lua` (kept from prune).
- Result: the fake record is local only (only my own access record is ever sent) and survives the roster prune; it is dropped by a version change or `/ps clean`. Decision: Naxxramas goes to the fake member, not my own record, so nothing fake reaches the guild.
- Evidence: `luajit tests/run.lua` -> 257 passed, 0 failed
- Next: in game (dev build): Debug tab -> "Fake keys" and "Fake Naxxramas", then Misc Items -> Keys / Attunements; then the verify.md checklist

## 2026-11-23 21:31 | NOTE | Released in 1.2.0
- Did: user: "looks fine commit push and release a new version". Version 1.2.0 (TOC, Dev TOC, Init fallback), CHANGELOG, RELEASE_NOTES, release commit + tag `professionshare/v1.2.0`.
- Result: status stays `verifying` (in-game checklist open)
- Evidence: `luajit tests/run.lua` -> 257 passed, 0 failed
- Next: user runs the in-game checklist in verify.md

## 2026-11-24 21:35 | VERIFY | Key ids from the guild's real records; dev key probe
- Did: read the live SavedVariables: six members' access records hold 6893, 7146, 11000, 18249 (listed) and 277507, 267089 (Forever items, not listed, no instance); every location seen is "keyring" or "bank" (key ring exists on Forever); every attunement is false for every member. Added `DevProbe.KeyProbe` (Dev tools -> Probes -> "Keys and attunements", `/psd keyprobe [itemID ...]`): name, item class, key yes/no, listed instance, holders, attunement quest answers -> devChecks.keyProbe. Fixed the Access.KEYS comment that claimed an in-game check.
- Result: user reports a Dalaran dungeon key is missing its instance; which id it is needs the probe
- Evidence: `luajit tests/run.lua` -> 332 passed, 0 failed
- Next: user runs `/psd keyprobe 277507 267089` and /reload; map the Dalaran key in Access.KEYS + "Dalaran" instance name; then "show keys nobody holds"

## 2026-11-24 21:57 | BUILD | Dalaran key, rows for keys nobody holds
- Did: read devChecks.keyProbe (21:56:38): all 10 listed ids resolve on Forever, key ring and quest API present; 277507 = "Kanalisationsschlüssel von Dalaran", 267089 = "Lagerschlüssel von Krol'Dok". User: Dalaran is missing, the key opens the Dalaran instance -> `Access.KEYS[277507] = "dalaran"`, instance name "Dalaran" (deDE). User asked for all main keys also when nobody holds them -> `Model.BuildKeyRows` adds a row per `Access.KEYS` entry with 0 holders; `UI/Window.lua` greys those names. README, CHANGELOG (Unreleased), doc.md, verify.md.
- Result: Keys list = held keys + every listed key; whisper stays disabled for 0 holders
- Evidence: `luajit tests/run.lua` -> 332 passed, 0 failed
- Next: user /reloads and looks at Misc Items -> Keys; decide what 267089 opens; attunement quest ids still unconfirmed (no member attuned yet)

## 2026-11-24 22:16 | DECISION | Forever's other keys stay unlisted for now
- Did: dev key scan (devChecks.keyScan 22:11:52): 150 class Key items in ids 1-300000; tooltips of the Forever keys name no instance except 277136 ("Vord'anaargefängnis in den Tiefengrabhügeln"). User: Krol'Dok and the others are not known yet (maybe a future raid).
- Result: list unchanged (10 classic keys + Dalaran); unlisted keys appear without instance once held; `/psd keyscan` re-checks when new content opens
- Evidence: spec.md Decisions; `luajit tests/run.lua` -> 332 passed, 0 failed
- Next: user looks at Misc Items -> Keys after /reload; commit when asked

## 2026-11-28 09:53 | DONE | confirmed in game; portrait icon split out
- Did: user: "ps 22 seems to working"
- Result: status done; R8/T7 moved to feature 054
- Evidence: user 2026-11-28
- Next: 054

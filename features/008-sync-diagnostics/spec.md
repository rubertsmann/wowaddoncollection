# 008 Sync diagnostics: spec

- Status: verifying
- Created: 2026-11-16
- Target version: 0.4.1
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md) | analysis: [review/sync-0.4.0-diagnosis.md](../../review/sync-0.4.0-diagnosis.md)

## Goal
Make every sync message and every sync decision visible in game and exportable, so the 0.4.0 failure (orders sync,
recipes and recipe items do not) can be pinned to its exact cause from one session; fix the bugs found on the way.

## Requirements
- R1: Every addon message sent and received is recorded (time, direction, channel, peer, type, size, summary, status, reason), bounded and persisted across /reload.
- R2: Every inbound message carries the decision Sync took, including name mismatches, sender/record mismatches, "not newer", and gate rejections with the roster's spelling of the sender.
- R3: Outbound status reflects the client's `SendAddonMessage` result (named), too-big and queue-full drops.
- R4: Local events that break sync are recorded: identity not in roster (plus one chat warning), records removed by a roster prune, incomplete multi-chunk transfers, identity change after login.
- R5: A Debug tab lists the trace (scrollable, newest first, filters, live status line, Send HELLO, Clear, Export).
- R6: `/ts export` (and the tab button) shows one copyable report: identity sources, transport state, records held, orders with name source, trace, debug log.
- R7 (bug B2): the sync identity is never a previously played character (no start before PLAYER_LOGIN, `me` read at use time).
- R8 (bug B1): addon whispers to a same-realm player use the character name even if `Ambiguate` returns the full name.
- R9 (analysis R1/R2): one canonical key per player for every spelling of my realm (client, roster, chat sender); stored data re-keyed on login and when a spelling is learned; whisper target strips every known spelling.
- R10 (analysis R3/R6): an unanswered WANT/WANTO is retried on GUILD (`via = "GUILD"`) and answered on GUILD, deduplicated per rev; given up after 3 tries until the next HELLO at least 60 s later (first draft: 10 min, reverted after a soak-test flake); HELLO every 15 min.
- R11 (analysis R5): orders carry the recipe name snapshot, shown when the viewer has no catalog entry.

## Non-goals
- Analysis R4 (catalog split): scalability, not this bug.
- Realms of OTHER members spelled differently in a way no source reveals (cross-realm guilds): reached only through the GUILD retry.

## Design
- Files: `Core/Trace.lua` (new, pure), `Core/Diag.lua` (new, report + `/ts ident`, `/ts export`), `Core/Comm.lua` (trace hooks,
  result decoding, `ready` gate, `CheckIdentity`, `InFlight`, `/ts trace`), `Core/Sync.lua` (`_me()`, `_note`, OnMessage returns
  status+reason), `Core/Store.lua` (`trace` key, prune trace), `Core/Api.lua` (`IdentityInfo`), `Core/Events.lua` (ready flag,
  name rebuild after 3 s), `Core/Util.lua` (WhisperTarget order), `UI/Window.lua` (Debug tab, export window), `Locales/deDE.lua`.
- Data shape: new `db.trace` (ring of <= 400 tables), sanitized on load.
- Message shape (protocol 2.2, additive): `via` on WANT/WANTO; optional `name`/`loc` on orders.
- Canonical names: `Util.Canon`, `Util.LearnMyRealm`, `Util.LearnFromRoster` (pure), `Store.Recanon`, `Comm.LearnFromEcho` / `Comm.Recanon`, `Api.GetGuildRoster` learns before canonicalizing.

## Tasks
- [x] T1 (S): Trace module + persisted ring. Verify: `trace: ring is capped...`, `trace: persisted ring is sanitized...`
- [x] T2 (M): Sync decisions + lazy identity. Verify: `sync: every handled message reports a decision`, `...name mismatch`, `...identity is read at use time`
- [x] T3 (M): Comm tracing in/out, result codes, gate reasons, incomplete transfers, ready gate, identity check. Verify: `comm: *`, `identity: *`
- [x] T4 (S): Report + `/ts export`, `/ts ident`, `/ts trace`. Verify: `export: the report holds ...`
- [x] T5 (M): Debug tab + export window. Verify: `load: all TOC files run ...` (debug tab + export window built)
- [x] T6 (S): WhisperTarget own-realm first. Verify: `whisper: my own realm is stripped even when Ambiguate returns the full name`
- [x] T8 (M): canonical names + re-key + echo/roster learning. Verify: `canon: *` tests
- [x] T9 (M): retry on GUILD, GUILD answer dedupe, periodic HELLO. Verify: `retry: *` tests (mutation-checked: sending the retry by whisper makes 2 tests fail)
- [x] T10 (S): order name snapshot. Verify: `orders: the recipe name travels with the order ...`
- [ ] T7: in-game export from two members (verify.md checklist)

## Review Focus
1. RF1: peer-controlled strings (names, summaries) in the tab, tooltip and export -> escaped with `Util.Esc`. Pinned by: code (`debugLine`, tooltip, `ShowExport`); READ-ONLY.
2. RF2: a rejected multi-chunk message must not flood the trace -> one entry per (sender, reason) per 30 s. Pinned by: `comm: a whisper rejected by the gate ...`
3. RF3: trace growth -> ring capped at 400, persisted ring sanitized. Pinned by: T1 tests.
4. RF4: tracing must never break transport -> all hooks inside existing pcalls or plain table writes; Sync without `env.me` function still works (tests use strings).
5. RF5: a forged "echo" must not teach a realm spelling -> only GUILD (server-filtered) and only with this session's id salt and my character name. Pinned by: `canon: my own GUILD echo teaches ...`
6. RF6: two old keys collapsing into one must not lose the newer record -> newer rev / newer claim wins. Pinned by: `canon: stored data is re-keyed ...`
7. RF7: GUILD answers must not multiply with the number of askers -> one per rev per 60 s. Pinned by: `retry: with every whisper lost ...` (2 GUILD requests, 1 SNAP)

## Cross-cutting checklist
- [x] Protocol: 2.2, additive (`via`, order `name`/`loc`); 2.1 peers ignore both and keep syncing (docs/protocol.md section 8).
- [x] Stored data: schema stays 3; `trace` is an additive key, defaulted in `fresh`, sanitized on load, emptied by `/ts clean`.
- [x] Trust model: unchanged gate; trace stores peer strings raw and escapes at display; export escaped.
- [x] Localization: new UI strings through `L`, deDE added; trace content is technical English by design (for the author).
- [x] Load order: `Core/Trace.lua` after `Core/Util.lua` (Store uses it on load), `Core/Diag.lua` after `Core/Comm.lua`; dev TOC regenerated.
- [x] Packaging: new files under `Core/`, already packaged.
- [x] Tests: `tests/test_diagnostics.lua` (15), `tests/test_canon.lua` (9), `tests/test_whisper_target.lua` (+1), `tests/test_load.lua` (debug tab, export window).
- [x] Docs: README commands, CHANGELOG, docs/status.md, doc.md, review/sync-0.4.0-diagnosis.md.

## Decisions
- 2026-11-16: No fix for the name-form mismatch before evidence: the exact spellings decide how a canonical key must normalise (systematic debugging: no fix without root cause).
- 2026-11-16: B1 (WhisperTarget) and B2 (stale identity) fixed now: both are wrong by reading the code, independent of the export, and covered by tests.
- 2026-11-16: Trace English-only and unlocalised: it is evidence for the author, pasted across clients of different languages.
- 2026-11-16: No schema bump for `db.trace` (additive, older builds ignore it).
- 2026-11-16: User asked to implement the recommended changes before an export ("continue and implement it"). The first decision above is superseded: R1 was built to cover every spelling difference the code can meet (fold case/spaces/apostrophes/hyphens, learn from roster and own echo) rather than one guessed difference; R3 makes sync independent of the whisper path, so the fix does not depend on which point actually failed. R4 left out (not this bug).
- 2026-11-16: Protocol minor 2.1 -> 2.2 (additive fields); schema stays 3 (names re-keyed in place, shape unchanged).

## Open questions
- What exact strings do `CHAT_MSG_ADDON` sender, `GetGuildRosterInfo` and `GetNormalizedRealmName` give on Forever? (needs: two-member export)
- Are addon WHISPERs delivered on Forever at all? (needs: two-member export; sync no longer depends on it)

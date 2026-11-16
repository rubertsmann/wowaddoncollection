# 006 Hardening and version compatibility: spec

- Status: verifying
- Created: 2026-11-16
- Target version: 0.3.0 (TOC bumped to 0.3.0 at merge, tag v0.3.0)
- Owner: claude (requested by user)
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)
- Source findings: `review/security-and-gaps.md` (S1-S6), `review/version-compatibility.md` (V1-V8, R1-R6)

## Goal
Only compatible TalentShare versions exchange data (and users are told when they are not), stored data is migrated or protected across versions, and untrusted input (non-guild senders, malformed or hostile peer data) can no longer reach the store or the UI unchecked.

## Requirements
Trust model (unchanged, README): guild members are trusted; order forgery by a member is accepted and NOT addressed here.
- R1 (S1): addon messages are processed only if `channel == "GUILD"`, or `channel == "WHISPER"` from a sender in the cached guild roster. Everything else is dropped before any parsing or buffering.
- R2 (R1/V1/V3): every chunk header carries `major.minor` of the wire protocol. A chunk with a different major is dropped before buffering; the viewer gets ONE chat hint per session ("newer version in your guild" / "older version that cannot sync"). Legacy headers (0.1/0.2 clients) are recognised as "older".
- R3 (R2/V2): `PROTO_MAJOR` must match exactly; `PROTO_MINOR` differences interoperate (additive-only rule documented in `docs/protocol.md`). A newer minor is noticed (hint) but not rejected.
- R4 (V6): message ids contain a random per-session salt so a `/reload` cannot collide with stale reassembly buffers.
- R5 (V7): transport limits are defined once (`Codec.CHUNK`, `Codec.MAX_PARTS`, `Codec.MAX_ENCODED = CHUNK * MAX_PARTS`); no second constant that can drift.
- R6 (S3): network numbers must be finite; `rev`, `createdAt`, `closedAt`, claim `t` are bounded to `[0, now + 1 day]`; counts, ids, ranks, levels are integers in sane ranges.
- R7 (S3): SNAP/ORDER/OPUSH data is rebuilt by allow-list copy (`Store.SanitizeChar`, `Store.SanitizeCatalogEntry`, `Orders.Sanitize`); unknown keys are dropped; every string is UTF-8, length-bounded and free of control characters; `icon` is a number or a safe texture path; names have no `|`.
- R8 (S3): catalog entries in a SNAP are accepted only for recipe ids the sender itself knows.
- R9 (S2): every peer-originated string shown by the UI is escaped (`|` -> `||`) in the view-model; item ids used in hyperlinks are bounded integers.
- R10 (V4/R3): `Store.Init` runs `Store.Migrate`: schema older -> stepwise migration (1 -> 2 re-sanitizes persisted `chars`, `catalog`, `orders`, drops invalid records); schema newer than this build -> saved data is left untouched on disk, the session runs on a throwaway DB, and the user is told once. Non-table saved data is replaced by an empty DB.
- R11 (V5/R4): one version source: the TOC `## Version`; `ns.BASE_VERSION` is read from addon metadata at runtime. A test pins TOC vs CHANGELOG; the release workflow refuses a tag that does not match the TOC.
- R12 (S4/S6): release workflow hygiene: trigger on `v*` tags only, token scoped to the packager step, tag/TOC check; `screens-debug/` ignored by git.
- R13 (V8/R5): adversarial regression tests exist for R1-R10 (listed under Review Focus).
- R14 (S5/R6): docs: `docs/protocol.md` (wire format, compatibility rules, schema policy), `docs/vendored-libs.md` (provenance), CHANGELOG, README compatibility section, `docs/status.md`, review files marked.

## Non-goals
- Authenticating or restricting guild members (order forgery stays accepted).
- Hardening against inflate bombs from guild members (LibDeflate has no output limit; non-guild senders are now gated out).
- Stripping the CLI part of the vendored LibDeflate, pinning actions to commit SHAs (needs network lookup; listed in `review/`).
- Gating `ns.Debug.Log` behind a flag.

## Design
- `Core/Init.lua` (changed): `ns.PROTO_MAJOR = 2`, `ns.PROTO_MINOR = 0`, `ns.PROTOCOL = ns.PROTO_MAJOR` (alias, still used in the payload `v` check); `ns.BASE_VERSION` from addon metadata (`C_AddOns.GetAddOnMetadata` or `GetAddOnMetadata`).
- `Core/Util.lua` (changed): `IsFinite`, `SafeInt(v, lo, hi)`, `CleanString(s, maxBytes)` (UTF-8, no control chars, bounded or nil), `Esc(s)` (`|` -> `||`), `IsSafeName`.
- `Core/Codec.lua` (changed): parser rejects non-finite numbers; `Codec.CHUNK`, `MAX_PARTS`, `MAX_ENCODED`; `Codec.Header(id, idx, total)` / `Codec.ParseHeader(text)` (new `maj.min|id|idx|total|part`; also recognises the legacy `id|idx|total|part`); `Codec.Compat(maj, min)` -> `"ok" | "newer-minor" | "newer" | "older"`.
- `Core/Guard.lua` (new, pure, loaded before Comm): `Guard.Accept(channel, sender, roster)` -> `true | false, reason`; `Guard.NewHints()` / `Guard.Note(hints, kind, sender)` (once-per-session incompatibility notices, bounded).
- `Core/Comm.lua` (changed): uses Guard before anything else; header via Codec; per-session salt in ids; roster cache refreshed on every roster read; hint printing through `ns.L`; `/ts comm` shows incompatible peer counts.
- `Core/Store.lua` (changed): `SCHEMA = 2`; `Migrate`, `SanitizeChar`, `SanitizeCatalogEntry`; `ValidateChar` / `ValidateCatalogEntry` stay as boolean wrappers; `PutChar`/`PutCatalog` keep the first-writer rule; `Init` returns `sv, status` (`"ok" | "migrated" | "newer" | "reset"`).
- `Core/Orders.lua` (changed): `Orders.Sanitize` exported; numeric bounds, name charset, note control-char strip; `closedBy` validated.
- `Core/Sync.lua` (changed): `_onSNAP` sanitizes the char, restricts catalog ids to the sender's recipes, stores only clean copies.
- `Core/Model.lua` (changed): peer strings escaped in view-models (`name`, `profession`, `professionName`, crafter `name`, reagent `name`, `requester`, `claimers`, `note`).
- `Core/Events.lua` (changed): assign `_G[SVNAME]` only when status is not `"newer"`; print warnings.
- `Locales/enUS.lua`, `Locales/deDE.lua` (changed): new notices.
- `.github/workflows/release.yml`, `.gitignore` (changed). New: `docs/protocol.md`, `docs/vendored-libs.md`, `tests/test_hardening.lua`.
- Data shape change: none for the wire records themselves; stored data is re-sanitized (schema 2).
- Message shape change: **chunk header** only (`maj.min|` prefix). Payload shape unchanged apart from `v` now meaning the major (2).

## Tasks
- [x] T1 (S): util helpers (`IsFinite`, `SafeInt`, `CleanString`, `Esc`) + parser rejects non-finite. Verify: `test_hardening` util/codec tests
- [x] T2 (M): `Codec.Header/ParseHeader/Compat`, limits, `Core/Guard.lua`; wire into `Comm` (gate, header, salt, hints). Verify: guard/header/compat tests
- [x] T3 (M): `Store.Sanitize*`, `Orders.Sanitize` hardening, `Sync._onSNAP` allow-list + catalog restriction. Verify: sanitize/adversarial tests
- [x] T4 (S): Model escapes peer strings. Verify: model escape test
- [x] T5 (M): `Store.Migrate` + downgrade guard, `Events` wiring, notices. Verify: migration tests
- [x] T6 (S): version source: metadata read, tests, release workflow tag check. Verify: test + workflow review
- [x] T7 (S): hygiene (`.gitignore`, workflow scope), docs (`protocol.md`, `vendored-libs.md`, CHANGELOG, README, status, review files)
- [x] T8 (S): update existing tests/harness for the new protocol; full suite green
- [ ] T9 (S): self-review with `review-talentshare` (done) + `verify.md`/`doc.md`/INDEX (done); stays open until the in-game rows in verify.md are run by the user

## Review Focus (failure modes a happy-path test would miss)
1. RF1: a WHISPER WANT from a character not in the roster -> no SNAP is sent and nothing is stored. Pinned by: T2 guard test + Comm gate test
2. RF2: chunk with major 3 (newer) or legacy header -> no buffer created, one hint only, no error. Pinned by: T2
3. RF3: `n1e999;` / negative or future timestamps in ORDER/SNAP -> rejected, store unchanged. Pinned by: T1, T3
4. RF4: SNAP with catalog ids the sender does not know, or reagent `name` = table, icon = table -> entries dropped, UI model still builds. Pinned by: T3
5. RF5: `|cffff0000|Hitem:1|h[x]|h|r` in a note / name -> displayed as literal text. Pinned by: T4
6. RF6: saved data with `schema = 99` -> file untouched, session works, user told; schema 1 with garbage records -> garbage dropped, valid kept. Pinned by: T5
7. RF7: two clients, one with a different minor -> they still sync; different major -> they do not. Pinned by: T2 (two-peer bus test)

## Cross-cutting checklist
- [x] Protocol: BUMP major 1 -> 2 (chunk header change). Reason: version must be readable before inflate; no deployed users (CurseForge project not yet approved, 0.1.0/0.2.0 never installed by others). 0.1/0.2 clients ignore the new header; 0.3 clients notice legacy headers and hint.
- [x] Stored data: `Store.SCHEMA` 1 -> 2; migration 1 -> 2 re-sanitizes persisted records; newer-than-known schema is never overwritten.
- [x] Trust model: allow-list sanitizer for all peer data; peer strings escaped in view-models; non-guild senders rejected.
- [x] Localization: four new notices go through `ns.L` (English key + deDE translation); no display strings are stored or sent.
- [x] Load order: `Core/Guard.lua` after `Codec.lua`, before `Comm.lua`; TOC and `tests/run.lua` harness updated; `test_load` checks the TOC.
- [x] Packaging: new file is under `Core/` (shipped); `.pkgmeta` / `tools/package.ps1` need no change (`review`, `features`, `.claude` already ignored).
- [x] Tests: `tests/test_hardening.lua`; adversarial cases = RF1-RF7.
- [x] Docs: README, CHANGELOG, docs/status.md, doc.md (T7/T9).

## Decisions (user answers and design choices, newest last)
- 2026-11-16: guild members are trusted, so order tampering is out of scope (user).
- 2026-11-16: implement all recommendations from `review/security-and-gaps.md` and `review/version-compatibility.md` on branch `fix/package-zip-paths` in its worktree (user).
- 2026-11-16: bump wire major to 2 now (chunk header gains `maj.min|`) because no one else runs a published build yet; later changes can then be additive minors.
- 2026-11-16: keep the addon-message prefix unchanged (`TShare`); the version lives in the header so every future client can still read it.
- 2026-11-16: schema 2 migration = re-sanitize persisted peer data (cheap, exercises the migration path); peer caches are never "migrated" by hand beyond that because they are re-fetchable.
- 2026-11-16: bounds window for timestamps is `now + 86400 s` (clock skew between guild members is small because both use `GetServerTime`).
- 2026-11-16: timestamps are only bounded above while the clock is usable (`Store.Horizon()` is unbounded below 1e9): a client whose server time is not available yet must never delete saved orders on load. Found while self-reviewing.
- 2026-11-16: review correction: the "Modified by LibDeflate" comment at `LibDeflate.lua:2956` is upstream's, not a local edit; `docs/vendored-libs.md` and `review/security-and-gaps.md` say so.
- 2026-11-16: not done: SHA-pinning of GitHub actions (needs network lookup), CLI strip of vendored LibDeflate, debug-log flag.

## Open questions
- In-game behaviour of the roster gate right after login (roster arrives a few seconds later; early whispers are dropped and re-requested by the next HELLO): needs game. Recorded as NOT-VERIFIED until observed.
- Two-client interop of the new header: needs a second guild member.

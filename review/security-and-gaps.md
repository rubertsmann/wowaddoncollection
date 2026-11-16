# Review: security, secrets and cross-cutting gaps

Date: 2026-11-16 · Scope: whole repo (working tree + all commits) · Status: **S1-S4, S6 and the validation gap implemented in feature 006** (`features/006-hardening-and-version-compatibility/`); see the status column below

**Threat model (agreed):** guild members are trusted. The README documents "no authentication beyond guild membership". Order tampering by guild members is therefore **accepted** and out of scope. Untrusted parties are: non-guild players who can whisper addon messages, and anything that reaches the UI as text.

## Secrets: clean
- No tokens, keys, PEM blocks or webhook URLs in the tree or in git history.
- Workflow uses `${{ secrets.CF_API_TOKEN }}` / `${{ secrets.GITHUB_TOKEN }}` only.
- No `loadstring` / `RunScript` / `setfenv` in addon code; `Core/Codec.lua` is a bounded hand-written serializer.

## Findings (in scope)

### S1. Non-guild senders are accepted (Medium) - FIXED in 006 (`Core/Guard.lua`, `Comm.OnAddonMessage`)
`Core/Comm.lua:89 OnAddonMessage` ignores `channel` and never checks the guild roster; WHISPER addon messages from anyone using the `TShare` prefix are processed.
- A stranger can send WANT and receive the full profession/recipe list, or inject SNAP/ORDER/OPUSH (injected orders are never roster-pruned).
- **Fix:** one gate at the top: `channel == "GUILD"`, or for WHISPER, `ns.Api.GetGuildRoster()[sender]`. Reply only to roster members. Add a test with a non-guild sender.

### S2. Peer text rendered with WoW escape sequences (Low-Medium) - FIXED in 006 (`Model` escapes, `Util.Esc`, sanitizers reject `|` in names)
`UI/Window.lua` ~145, 157, 266, 341-342 pass `note`, `requester`, claimer names, `profession` and recipe/reagent names to `SetText`/`format` unescaped. `|c..|r`, `|T..|t`, `|H..|h` render, enabling spoofed colours/status lines and injected textures/links (no protected actions).
- **Fix:** one `esc(s) = s:gsub("|", "||")` helper applied to every peer string at display time; also bound `profession` name length in `ValidateChar`.
- `GameTooltip:SetHyperlink("item:" .. itemID)` (`UI/Window.lua:290`) takes `itemID` from the peer-supplied catalog: validate it as a bounded integer.

### S3. Robustness against bad (not malicious) data (Low) - FIXED in 006 (non-finite and range checks, allow-list copies, catalog id restriction)
- `Codec.parse` accepts `n1e999;` (inf). Reject non-finite numbers on the parse side; clamp `rev`, `createdAt`, `closedAt`, claim `t` to a sane window.
- `ValidateCatalogEntry` does not check `icon`, `minSkill`, `produces`, `reagents[i].name`, or bounds on `itemID`/`count`. A bad value persists (catalog is first-writer-wins) and throws on every UI refresh until `TalentShareDB` is wiped. Whitelist-copy fields instead of storing the raw peer table, and restrict catalog IDs in a SNAP to the sender's own recipes.
- `Store.PutChar` / `PutCatalog` store the raw table, including unknown nested keys (SavedVariables bloat).

### S4. CI / supply chain (Low) - PARTLY FIXED in 006 (tag filter `v*`, token scoped to the step, tag/TOC check). OPEN: pin actions to commit SHAs (needs a network lookup); TOC has no `X-Curse-Project-ID` (not needed for manual uploads)
- Pin `BigWigsMods/packager@v2` and `actions/checkout@v4` to commit SHAs.
- Set `CF_API_TOKEN` only on the packager step, not workflow-wide.
- Trigger on `v*` tags, not `'**'`.
- TOC has no `X-Curse-Project-ID` yet (CurseForge upload will not work until added).

### S5. Vendored libs (Low) - DOCUMENTED in 006 (`docs/vendored-libs.md`); byte-identity with upstream still NOT verified
`Libs/LibDeflate` was copied from the installed Spoken addon, plus a CLI section (`io.open`) that is dead code in WoW. **Correction:** the first version of this review claimed a local modification at `LibDeflate.lua:2956`; that comment ("Modified by LibDeflate ... loadstring() lua api is no longer used") is upstream's own note about code it adapted, not an edit made here. Provenance and SHA-256 are now recorded; comparing with the upstream 1.0.2-release file needs network access. Stripping the CLI part was deliberately not done (keeps the file identical to upstream).

### S6. Repo hygiene (Low) - PARTLY FIXED in 006 (`screens-debug/` gitignored; `Debug.Log` now escapes `|`). OPEN: delete the empty `Neuer Ordner/`, decide on `icon.png`, gate the debug log behind a flag
- `screens-debug/` is untracked and not gitignored; the screenshot shows a character/realm name. Add to `.gitignore`.
- `Neuer Ordner/` (empty) can be deleted. `icon.png` is untracked: decide whether it ships.
- `ns.Debug.Log` persists 200 lines (sender names, error strings) in SavedVariables; gate behind a debug flag.

## Cross-cutting gaps
- **Validation is inconsistent:** `Orders.sanitize` rebuilds a clean record; `Store.PutChar` / `PutCatalog` keep the raw peer table. Use one allow-list sanitizer for all network input.
- **Inbound limits:** no per-sender cap on reassembly buffers (defence in depth only).
- **Version compatibility and migration:** see `review/version-compatibility.md` (largest structural gap).
- **Verification:** per `docs/status.md`, everything that touches the game client (Api, Scanner, Events, Comm transport, UI) was UNVERIFIED at the time of writing; docs/api-findings.md records the later probe results. Re-run the in-game checklist after each change in those files.
- **Tests:** add adversarial cases (non-guild sender, non-finite numbers, bad catalog fields, escape sequences in notes, foreign protocol).
- **Docs/release:** no CHANGELOG, SECURITY.md, or addon licence file; no checksum for the manual zip; no `docs/protocol.md`.

## Priority
1. S1 (single inbound gate) and the protocol header from `version-compatibility.md` R1, both before first release.
2. S2 (escape helper) and S3 (strict sanitizer).
3. S4-S6 housekeeping.

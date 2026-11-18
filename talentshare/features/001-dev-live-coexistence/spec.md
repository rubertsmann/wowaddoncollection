# 001 Dev live coexistence: spec

- Status: verifying
- Created: 2026-11-16
- Target version: 0.2.0 (dev builds report `0.2.0-dev`)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
The working copy of the repo installs as a separate addon `TalentShare-Dev` so it can run next to the live (CurseForge) `TalentShare` in one WoW install without any shared state.

## Requirements
- R1: Folder `AddOns\TalentShare-Dev` loads as its own addon (title "TalentShare (dev)", version `<ver>-dev`); the live `TalentShare` folder is untouched and loads independently.
- R2: No shared state: different SavedVariables (`TalentShareDevDB` vs `TalentShareDB`), addon-message prefix (`TShareDev` vs `TShare`), slash commands (`/tsd` vs `/ts`), global frame names, minimap button position and window offset.
- R3: Identity is derived in one place (`Core/Init.lua`) from the addon folder name; no other file hardcodes `TalentShare`, `TShare`, `/ts` or `TalentShareDB`.
- R4: `tools/deploy.ps1` links the working copy as `TalentShare-Dev` (generating `TalentShare-Dev.toc` from `TalentShare.toc`), removes the old `TalentShare` junction that points at this repo, and can install the live zip into `TalentShare` (`-InstallLive`) without ever overwriting a real folder unless `-Force`.
- R5: The release package is unaffected: it still contains only `TalentShare.toc` and live identity; the generated dev TOC is git-ignored and package-ignored.

## Non-goals
- Dev and live instances do NOT talk to each other (different prefix). Cross-version sync is tested with two live-prefix builds, not with this feature.
- No migration of data from `TalentShareDB` into `TalentShareDevDB`.

## Design
- `Core/Init.lua`: `ns.IS_DEV` (folder name contains "dev", case-insensitive), `ns.TITLE`, `ns.PREFIX`, `ns.SVNAME`, `ns.SLASH` (list), `ns.FRAME`, `ns.VERSION` (`-dev` suffix in dev).
- `Core/Events.lua`: SavedVariables through `_G[ns.SVNAME]`.
- `UI/Window.lua`: frame names from `ns.FRAME`, title from `ns.TITLE`, dev offsets.
- `tools/deploy.ps1`: params `-Live` is NOT needed; flags `-InstallLive`, `-Force`, `-WithProbe`.
- `.gitignore`, `.pkgmeta`: `TalentShare-Dev.toc`.
- `tests/test_identity.lua`: loads `Core/Init.lua` with ADDON = "TalentShare" and "TalentShare-Dev".

## Tasks
- [x] T1 (S): identity block in Init.lua + Events/Window use it. Verify: tests/test_identity.lua
- [x] T2 (S): deploy.ps1 generates dev TOC, links `TalentShare-Dev`, removes old junction, `-InstallLive`. Verify: run it, inspect AddOns folder
- [x] T3 (S): ignore files, README/docs. Verify: package.ps1 zip listing has no dev TOC
- [ ] T4 (S): in-game check by user: both addons listed, `/tsd version` and `/ts version` work

## Review Focus
1. RF1: Prefix longer than 16 chars silently fails to register -> test asserts <= 16 for both identities.
2. RF2: Removing the old junction must never delete repo files -> only remove when `LinkType == Junction` and use `rmdir`/`Remove-Item` on the link itself; verify repo intact after.
3. RF3: Live and dev both enabled must not both answer on one prefix -> distinct prefixes (test).

## Cross-cutting checklist
- [x] Protocol: unchanged (`ns.PROTOCOL = 1`); dev uses a different prefix so it never meets live traffic.
- [x] Stored data: `Store.SCHEMA` unchanged; dev has its own SavedVariables.
- [x] Trust model: n/a.
- [x] Localization: n/a (title strings only).
- [x] Load order: unchanged.
- [x] Packaging: `.pkgmeta` + `.gitignore` ignore `TalentShare-Dev.toc`; package.ps1 whitelist unchanged.
- [x] Tests: tests/test_identity.lua.
- [ ] Docs: README, docs/status.md, doc.md.

## Decisions
- 2026-11-16: user asked to "rename the working version to -dev so I can keep both"; chosen: separate addon folder + generated TOC (junction keeps live-edit + /reload) instead of a copy.
- 2026-11-16: dev gets its own prefix, so dev<->live sync is intentionally impossible (avoids both versions answering the same traffic).

## Open questions
- none

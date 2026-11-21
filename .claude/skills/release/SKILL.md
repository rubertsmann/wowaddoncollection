---
name: release
description: Release an addon of the wowaddons monorepo (ProfessionShare, GuildGames, ...): version bump, notes, tests, commit, tag, push, zip, CurseForge upload. Use when the user asks to release, ship, publish or "create a new version" of an addon, or to upload one to CurseForge.
---

# Releasing an addon

Monorepo `wowaddons/` (remote `wowaddoncollection`, branch `master`). Each addon is a folder
(`professionshare`, `guildgames`); `libguildsync` is a library embedded through the `Libs/LibGuildSync` links and has no
release of its own. A request to release counts as the request to commit, tag, push and upload that release; nothing
else (unrelated working-tree changes) goes into it unless the user says so.

## Pick the version
- Read `<addon>/CHANGELOG.md` "## Unreleased" and `git log <addon>/v<last>..HEAD -- <addon> libguildsync` (a library
  change ships in every addon that embeds it: mention it for each).
- Semver from what changed: fix only -> patch, new feature or protocol minor -> minor. Protocol/schema changes need the
  decisions written in the feature's spec (see `docs/protocol.md` of the addon).
- Nothing unreleased -> say so and stop.

## Steps (in order)
1. **Version, all places** (they must agree):
   - `<addon>/<Name>.toc` `## Version: X.Y.Z`
   - `<addon>/<Name>-Dev.toc` `## Version: X.Y.Z-dev` (generated and gitignored: edit it anyway, so the dev build shows it)
   - `<addon>/Core/Base/Init.lua` `fallbackVersion = "X.Y.Z"`
2. **Developer changelog:** `## Unreleased` -> `## X.Y.Z (YYYY-MM-DD, protocol P, schema S[, LibGuildSync MINOR M])`
   (date from the system, never guessed).
3. **Player notes:** a new section at the TOP of `<addon>/RELEASE_NOTES.md`: `# <Name> X.Y.Z`, then
   `**English:**` and `**Deutsch:**` paragraphs in plain player language (what changes for them, whether everyone
   must update). No internals, no MINOR/protocol numbers, no real character or realm names. This section is the
   CurseForge changelog.
4. **Tests:** `export PATH="$PATH:$(cygpath "$LOCALAPPDATA")/Programs/LuaJIT/bin"`, then `luajit tests/run.lua` in the
   addon folder AND in `libguildsync` when it changed. Quote the "N passed, 0 failed" line. A failure stops the release.
5. **Commit** only the release files plus the reviewed changes: `release(<addon>): X.Y.Z (<short summary>)`, trailer
   `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Stage paths explicitly (never `git add -A`).
6. **Tag** (lightweight, prefixed): `git tag <addon>/vX.Y.Z`, then `git push origin master <addon>/vX.Y.Z`.
7. **Zip:** `powershell -File <addon>/tools/package.ps1` on the release commit -> `<addon>/dist/<Name>-X.Y.Z.zip`.
   Check: one top-level `<Name>/` folder, TOC says `X.Y.Z`, no `tests/`, `features/`, `-Dev.toc` entries, LibGuildSync
   files present (the link is followed). NEVER run package.ps1 on unreleased work: it overwrites the zip of the
   current TOC version.
8. **CurseForge:** from the repo root
   `powershell -File tools/upload-curseforge.ps1 -Addon <addon> -DryRun`, check project, file, game version and notes,
   then the same without `-DryRun`. Report the file id it prints. Settings: `<addon>/tools/curseforge.json`
   (ProfessionShare 1809735, GuildGames 1815339; game version `1.60.1` = WoW Forever). Token: `.cursforge-token` /
   `.curseforge-token` in the repo root (gitignored) or `$env:CF_API_TOKEN`; never read, print or commit it.
   The script does not check for an existing upload: never upload the same version twice (look at the project page
   or ask). Skip this step only when the user says "no CurseForge".

## Report
Commit hash and subject, tag pushed, zip path and the checks done, test lines, CurseForge file id (or why skipped),
and what was NOT verified (in-game behaviour unless the user confirmed it). Mention other addons with unreleased work.

## Never
- Push or tag without a release request; force-push; skip hooks.
- Put the token, real character or realm names into any committed file.
- Upload a zip built from anything but the tagged release commit.

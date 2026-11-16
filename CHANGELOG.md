# Changelog

## 0.3.1
- **Build flag:** one definition in `Core/Init.lua` (`ns.BUILD`, TOC `## X-Build: dev` or a folder name containing "dev"); the comms prefix, SavedVariables, frame names and slash commands of the dev build are all derived from it, so a dev build and the live addon never share data or addon messages. `tools/deploy.ps1` and `tools/package.ps1` now verify the generated dev TOC and the shipped live TOC; a TOC that saves a different global than the build uses is reported.
- Dev client no longer fails with a chain of nil-index errors when its generated TOC is stale: one message names the missing modules and the fix (`tools/deploy.ps1`, then restart the game).
- Tests: build-flag and TOC-invariant tests, stale dev TOC detection.
- Wire protocol (2.0) and SavedVariables schema (2) unchanged.

## 0.3.0
- **Protocol 2.0 (breaking, intentional):** every chunk header now carries `major.minor`, so incompatible versions are detected before anything is buffered and the player gets ONE notice (newer / older version in the guild). Same major with a different minor still syncs. 0.1/0.2 builds cannot sync with 0.3. See `docs/protocol.md`.
- **Inbound gate:** only `GUILD` messages and whispers from guild-roster members are processed; non-guild players can no longer request your recipes or inject data.
- **Strict input validation:** all peer and saved data is rebuilt by allow-list copy (finite numbers, bounded ids and timestamps, UTF-8 strings without control characters, safe icons); catalog entries are accepted only for recipes the sender knows.
- **Display safety:** peer text (notes, names) is escaped so `|c`/`|T`/`|H` codes show as literal text.
- **SavedVariables schema 2:** persisted data is re-validated on load; data written by a NEWER addon is left untouched (session runs unsaved, one notice) instead of being overwritten.
- One version source (TOC; read at runtime); release workflow now triggers on `v*` tags, checks the tag against the TOC version and scopes the CurseForge token to the packager step.
- Packaging: `tools/package.ps1` writes forward-slash zip entries (Windows PowerShell's `Compress-Archive` wrote backslashes) and verifies the zip.
- Docs: `docs/protocol.md`, `docs/vendored-libs.md`. Details: `features/006-hardening-and-version-compatibility/doc.md`.

## 0.2.0 (never released on its own; included in 0.3.0)
- Localization: UI in English/German, profession/recipe names resolved per viewer (mixed-language guilds merge), case/accent-insensitive search, UTF-8-safe order notes (fixes requests with long multi-byte notes doing nothing). See `features/002-localization-layer/doc.md`.
- Profession icons in the Recipes tab: one click per profession (a secure button, like the macro `/cast <profession>`) reads its recipes instead of cycling through the pages of the profession menu; new recipes are picked up automatically. See `features/005-profession-scan-buttons/doc.md`. (An automatic scan was tried and removed: the game blocks addons from opening professions.)
- `/ts clean confirm` wipes all locally stored data (cached guild data, recipes, orders). See `features/004-clean-command/doc.md`.
- Dev builds install side by side as `TalentShare-Dev` (own data, prefix and `/tsd`). See `features/001-dev-live-coexistence/doc.md`.
- Wire format and SavedVariables schema unchanged (additive fields only): interoperates with 0.1.0.

## 0.1.0
- First version: profession/recipe sharing over the guild addon channel, recipe browser, shared order board.

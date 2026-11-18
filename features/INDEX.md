# Features

One row per feature. Status: planned, in-progress, verifying, done, abandoned. Workflow: .claude/skills/feature-workflow/SKILL.md
"verifying" = built and proven OFFLINE, in-game checklist in the feature's `verify.md` still open. Releases: v0.3.0, v0.3.1, v0.3.2 (tags on GitHub); 0.2.0 was never released alone.

| ID | Feature | Status | Version | Commits | Folder |
|---|---|---|---|---|---|
| 001 | Dev live coexistence | verifying | 0.3.0 (build flag: 0.3.1) | ede5a33, 91b5f67 | [001-dev-live-coexistence](001-dev-live-coexistence/spec.md) |
| 002 | Localization layer | verifying | 0.3.0 | abdb5c3, 9ad54bd | [002-localization-layer](002-localization-layer/spec.md) |
| 003 | Auto profession scan | abandoned (see 005) | - | 6e660a1, 34049a3, 38b7798 (removed in fca0b5a) | [003-auto-profession-scan](003-auto-profession-scan/spec.md) |
| 004 | Clean command | verifying | 0.3.0 | b9534c6 | [004-clean-command](004-clean-command/spec.md) |
| 005 | Profession scan buttons | verifying | 0.3.0 | fca0b5a, be8b731, c9e7a52, 475765f | [005-profession-scan-buttons](005-profession-scan-buttons/spec.md) |
| 006 | Hardening and version compatibility | verifying | 0.3.0 (protocol 2.0, schema 2), fixes 0.3.1, 0.3.2 | fc21757, 9b76d90, d43333b, 91b5f67, 5261868 | [006-hardening-and-version-compatibility](006-hardening-and-version-compatibility/spec.md) |
| 007 | Recipe items board | verifying | 0.4.0 (protocol 2.1, schema 3) | 61eff86 | [007-recipe-items-board](007-recipe-items-board/spec.md) |
| 008 | Sync diagnostics and name/retry fixes | verifying | 0.4.2 (protocol 2.2, schema 3) | - | [008-sync-diagnostics](008-sync-diagnostics/spec.md) |
| 009 | Craft and whisper from lists | verifying | 0.5.0 (UI only) | - | [009-craft-and-whisper-from-lists](009-craft-and-whisper-from-lists/spec.md) |
| 010 | Order notifications | verifying | 0.5.0 (UI + local settings) | - | [010-order-notifications](010-order-notifications/spec.md) |
| 011 | Item categories and text search | verifying | 0.5.0 (UI + local cache) | - | [011-item-categories-and-text-search](011-item-categories-and-text-search/spec.md) |
| 012 | Helper consolidation | verifying | next (internal refactor) | - | [012-helper-consolidation](012-helper-consolidation/spec.md) |
| 013 | Naming types and logging overhaul | verifying | next (internal refactor) | - | [013-naming-types-and-logging-overhaul](013-naming-types-and-logging-overhaul/spec.md) |
| 014 | Guild game base (coin flip) | verifying (moved to GuildGames by 015) | 0.6.0 (protocol 2.3, schema 4) | - | [014-guild-game-base](014-guild-game-base/spec.md) |
| 015 | Games extraction and shared sync library | verifying | 0.7.0 (protocol 2.3, schema 5); GuildGames 0.1.0; LibGuildSync-1.0 minor 1 | - | [015-games-extraction-and-shared-sync-library](015-games-extraction-and-shared-sync-library/spec.md) |
| 016 | Recipe table columns and resizable window | verifying | 0.7.0 (UI + local settings) | - | [016-recipe-table-columns-and-resizable-window](016-recipe-table-columns-and-resizable-window/spec.md) |

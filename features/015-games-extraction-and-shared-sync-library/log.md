# 015 Games extraction and shared sync library: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-18 13:47 | PLAN | Feature created
- Did: scaffolded `features/015-games-extraction-and-shared-sync-library/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-18 13:55 | DECISION | user answers: embedded lib, transport + record sync, fresh start, GuildGames + LibGuildSync
- Did: asked the 4 outcome-changing questions; wrote spec.md (R1-R7, T1-T8, RF1-RF5, decisions)
- Result: plan fixed; v0.6.0 is tagged (games shipped), so TalentShare needs schema 5 to drop games data
- Evidence: `git tag` lists v0.6.0; spec.md "Decisions"
- Next: T1 create wowaddons/libguildsync with Core registry + pure modules and its own test runner

## 2026-11-18 14:40 | BUILD | T1-T3 LibGuildSync-1.0 repo with Core, Utility, Log, Trace, Codec, Guard, Locale, Events, Sync, Guild, Channel, Widgets
- Did: created `wowaddons/libguildsync` (LibGuildSync/*.lua + LibGuildSync.xml, Libs/LibStub + LibDeflate for tests, tests/run.lua, test_core/test_sync/test_channel). Utility generated from TalentShare's file (state moved into `Utility.names` so it survives an upgrade; `Me` removed). Sync = TalentShare's pull/retry logic generalised to registered record kinds + hello hooks + custom handlers. Channel = Communication's transport with closures bound per channel, one shared token bucket + driver frame for all channels.
- Result: library suite green; TalentShare untouched so far
- Evidence: `luajit tests/run.lua` (libguildsync) -> `27 passed, 0 failed`; talentshare baseline -> `254 passed, 0 failed`
- Next: T4+T5 together (the Sync adapter is written without games, so doing them apart would mean writing the games kind twice): embed the lib (junction Libs/LibGuildSync), TOC, adapters for Utility/Log/Trace/Locale/Codec/Guard/Sync/Communication/Api/Events/Window, remove games

## 2026-11-18 15:35 | BUILD | T4+T5 TalentShare runs on LibGuildSync, games removed
- Did: Libs/LibGuildSync = junction to ../libguildsync/LibGuildSync (git-ignored), TOC loads LibGuildSync.xml after LibDeflate. Adapters: Core/Base/Utility.lua (lib Utility + own Me), Log.lua, Debug/Trace.lua (own Summarize), Locale.lua (lib Locale + professions), Net/Codec.lua (protocol read from addon.PROTOCOL_* at use time), Guard.lua, Sync.lua (char/offers kinds, orders hello hook, OPUSH/ORDER handlers; keeps sync.wanted/wantedOffers), Communication.lua (= lib Channel + notices, Store hooks, slash commands), Game/Api.lua (roster/identity -> lib Guild), Game/Events.lua (lib Events bus), UI/Window.lua (lib Widgets). Removed: Core/Play/*, UI/GamesTab.lua, UI/SlotMachine.lua, UI/Animate.lua, Model games section, DevProbe anim/game, deDE games strings, tools/coinflip.lua, games tests (copied to ../guildgames first). Store.SCHEMA 5 (migration 4 drops games + ui.lastStakeCopper/lastSlotStakeCopper/gamesScope/gameKey).
- Result: wire format unchanged except no grev/WANTG/GAMES; 0.6 peers' games messages are dropped as unknown types
- Evidence: `luajit tests/run.lua` -> `211 passed, 0 failed` (was 254 incl. 43+ games tests). Rewrote 4 source-text tests as behaviour tests (prefix, whisper target, codec version alias); new tests "015: ... schema 5" and "015: a 0.6 peer's games messages are ignored" (RF3)
- Next: T6 GuildGames addon from the copied files

## 2026-11-18 16:40 | BUILD | T6 GuildGames addon
- Did: new repo `wowaddons/guildgames`: GuildGames.toc, Core/Init.lua (identity, prefix GGames/GGamesDev, protocol 1.0, /gg /ggd), Core/Library.lua (Utility+Me, Log, Trace, Locale, Codec, Guard, Events from LibGuildSync), Core/Store.lua (schema 1, newer -> read-only, canonicalize, prune, clean), Core/Api.lua, Core/Games.lua + CoinFlip.lua + Slots.lua (moved), Core/Model.lua (games section of TalentShare's Model), Core/Sync.lua (games kind), Core/Communication.lua (Channel), Core/Events.lua, Locales (games strings + new notices), UI/Window.lua (own dialog), UI/GamesTab.lua + SlotMachine.lua + Animate.lua (moved), UI/DevProbe.lua (anim probe + sim), tools/coinflip.lua, docs/protocol.md, README, CHANGELOG
- Result: the moved games tests pass unchanged in substance (only the order board was removed from the test peer and the schema number fixed); new load/store/locale tests
- Evidence: `luajit tests/run.lua` (guildgames) -> `51 passed, 0 failed`; `luajit tools/coinflip.lua T 2000` -> `record ... valid for peers: true`
- Next: T7 tools

## 2026-11-18 16:55 | BUILD | T7 tools: deploy links the library, package ships its real files
- Did: talentshare tools/deploy.ps1 creates the junction Libs\LibGuildSync -> ..\libguildsync\LibGuildSync; tools/package.ps1 walks junctions itself (Windows PowerShell 5.1 -Recurse does not follow them; the first run caught it), checks every LibGuildSync.xml file is in the zip, and takes -ZipVersion for test builds. guildgames tools derived from them (deploy linked AddOns\GuildGames-Dev).
- Result: both zips carry the library. NOTE: two failed test runs of package.ps1 (before -ZipVersion worked: PowerShell variables are case-insensitive, `$Version` = `$version`) overwrote the local dist/TalentShare-0.6.0.zip; it was rebuilt from the v0.6.0 tag with that tag's own package.ps1 (36 files, GamesTab inside, no LibGuildSync)
- Evidence: `built ...\GuildGames-0.1.0.zip (36 files)`; `built ...\TalentShare-0.7.0-test.zip (43 files)` with Libs/LibGuildSync/*.lua (test zip deleted afterwards)
- Next: T8 docs

## 2026-11-18 17:10 | DOC | T8 docs and verification matrix
- Did: doc.md, verify.md (OFFLINE rows pass; in-game and two-member rows NOT-VERIFIED with a checklist), spec (tasks ticked, status verifying, message-name deviation), INDEX (015 verifying, 014 marked moved), docs/status.md, docs/protocol.md (header, schema table 3-5, section 9 moved note), README (games -> GuildGames, Libs/LibGuildSync row, test prerequisite), CHANGELOG 0.7.0 (unreleased). libguildsync README/CHANGELOG, guildgames README/CHANGELOG/docs/protocol.md. git init in guildgames and libguildsync (nothing committed).
- Result: feature is `verifying`; nothing committed (no commit was asked for)
- Evidence: talentshare `211 passed, 0 failed`; guildgames `51 passed, 0 failed`; libguildsync `27 passed, 0 failed`
- Next: user runs the in-game checklist in verify.md; then commit (three repos), version bump TalentShare to 0.7.0 at release, package both

## 2026-11-18 14:40 | BUILD | in-game bug fix (Window.lua setButtonLabel) + GuildGames minimap button
- Did: user report `UI/Window.lua:1128: attempt to call a nil value` on opening /tsd: the Craft button (secure template, built by hand) still used the local `setButtonLabel` that T4 removed with the other helpers. Restored it as an alias of `Widgets.SetButtonLabel`. New test in both addons' test_load: reads each file's bytecode (`luajit -bl`) and fails on any unknown lowercase global (the stubbed load test could not see it: stub widgets answer every method); checked that it fails on the old file. User asked for a GuildGames minimap icon: TalentShare's minimap button moved into the library as `Widgets.CreateMinimapButton` (TalentShare uses it, badge unchanged); GuildGames builds a coin button at PLAYER_LOGIN (default angle 185, dev 165; TalentShare 215/245), angle saved in `GuildGamesDB.ui.minimapAngle`, two new deDE strings.
- Result: library MINOR stays 1 (nothing has been released with it yet)
- Evidence: scan without the fix -> `unknown globals (missing local?): UI/Window.lua: setButtonLabel`; libguildsync `27 passed, 0 failed`; talentshare `212 passed, 0 failed`; guildgames `52 passed, 0 failed`
- Next: user: /reload, open /tsd (Orders tab Craft button) and check the GuildGames coin on the minimap; then the verify.md checklist

## 2026-11-18 14:55 | VERIFY | user: both dev addons work in game after the fix
- Did: recorded the user's report in verify.md (R1 and R6 basic rows -> IN-GAME)
- Result: still open: two-member sync (GuildGames leaderboard; TalentShare 0.7 with 0.6.0 members)
- Evidence: user message "seems to be working now fine"
- Next: second-member test; then commit the three repos, bump TalentShare to 0.7.0, package both addons

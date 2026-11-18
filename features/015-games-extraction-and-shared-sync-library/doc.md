# Games extraction and shared sync library

Status: verifying | Since version: TalentShare 0.7.0 (unreleased), GuildGames 0.1.0, LibGuildSync-1.0 minor 1 | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
- The coin flip and the slot machine (feature 014) left TalentShare and became the addon **GuildGames**
  (`wowaddons/guildgames`, `/gg`). Rules, animations and leaderboards are unchanged.
- What both addons need lives once, in the embedded library **LibGuildSync-1.0** (`wowaddons/libguildsync`).
  That covers the transport, the record-pull protocol engine, player names, log, trace, codec, guild gate, locale, events,
  window helpers and the roster/identity calls.
- TalentShare keeps its wire format. 0.6.0 members keep syncing recipes, orders and items with 0.7.0.

## How to use
- Players: install GuildGames for the games. TalentShare 0.7.0 no longer has a Games tab. Results from 0.6.0 are not
  carried over (fresh start).
- Developers: clone `libguildsync` next to the addon repos, then run `powershell tools/deploy.ps1` in each addon. It
  links `Libs\LibGuildSync` and the dev addon folder and generates the dev TOC. Restart the game.
  `tools/package.ps1` puts the library's real files into the zip.

## How it works
- **Library loading:** `LibGuildSync.xml` lists the files. `Core.lua` registers with LibStub, and each other file
  registers through `lib:Module(name, MINOR)`. A newer copy upgrades the module tables in place; equal or older copies
  are skipped. Instances (Log, Trace, Codec, Locale, Events, Sync, Channel) are per addon, and their functions look up
  the module code at call time.
- **Shared on purpose:** `Utility`'s realm and surname knowledge (it describes the player), `Channel.shared` (one send
  token bucket and one driver frame for every prefix, because the server throttles per player), `Guard`, `Guild` and
  `Widgets`.
- **Sync engine:** an addon registers record kinds (`helloField`, `requestType`, `answerType`, `recordField`,
  `heldRevision`, `myRecord`, `sanitize`, `store`, optional `answer`), HELLO hooks and custom handlers. TalentShare
  registers `char` (rev/WANT/SNAP + catalog), `offers` (orev/WANTO/OFFERS), the orders digest hook and OPUSH/ORDER.
  GuildGames registers `games` (grev/WANTG/GAMES).
- **Data:** TalentShare `Store.SCHEMA` 5. Migration 4 -> 5 deletes `games` and `ui.lastStakeCopper`, `lastSlotStakeCopper`,
  `gamesScope` and `gameKey`. GuildGames schema 1 (`GuildGamesDB`: games, ui, debug, trace, me).
- **Protocols:** TalentShare 2.3 (unchanged minor; it no longer sends `grev`, and drops `WANTG`/`GAMES` as unknown).
  GuildGames 1.0 on prefix `GGames`, keeping 0.6's message names (guildgames `docs/protocol.md`).

## Limits and known issues
- Not verified in game yet (see verify.md checklist): both addons together, two-member sync.
- The GitHub release workflow (`.pkgmeta`, inactive) does not fetch LibGuildSync. Build releases with `tools/package.ps1`.
- A library change needs a MINOR bump in every library file, then a re-package of every addon that ships it. The
  newest embedded copy wins at runtime.

## Changelog line
- Games moved to the GuildGames addon; comms and shared helpers are now the embedded LibGuildSync-1.0 (wire unchanged, schema 5).

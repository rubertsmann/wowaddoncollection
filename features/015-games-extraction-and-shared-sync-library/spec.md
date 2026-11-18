# 015 Games extraction and shared sync library: spec

- Status: verifying
- Created: 2026-11-18
- Target version: TalentShare 0.7.0, GuildGames 0.1.0, LibGuildSync-1.0 minor 1
- Owner: claude (user decisions below)
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
Move the guild games (coin flip, slot machine) out of TalentShare into their own addon **GuildGames**. The comms stack and
the other helpers both addons use become one embedded library, **LibGuildSync-1.0**.

## Requirements
- R1: The new repo `wowaddons/libguildsync` holds LibGuildSync-1.0, a LibStub library with several files that is embedded
  in each addon under `Libs/LibGuildSync`. Two embedded copies load safely: the newest minor wins, and an equal or older
  copy is skipped file by file.
- R2: The library provides the shared helpers: Utility (names, tables, untrusted input, UTF-8), Log and Trace instances,
  Codec instances (one protocol version per addon), Guard, Locale instances (Format/Plural), Events instances, Widgets (the
  window helpers) and Guild (roster and identity client calls).
- R3: The library provides the comms: **Channel** (one per addon prefix: chunking, a send token bucket shared by every
  channel, reassembly, the guild gate, the echo/realm learning, version hints, HELLO coalescing, roster/identity check,
  minute ticker) and **Sync**, a generic record-pull engine. Sync covers HELLO revisions -> request whisper -> record,
  GUILD retries (45/90/180 s), give-up reset, GUILD answer dedup, asked-name answers, the login reply budget, plus hooks
  for addon-specific HELLO fields and message types.
- R4: TalentShare runs on the library with an **unchanged wire format** (protocol 2.3 messages, prefix, header) and
  unchanged behaviour. Its existing offline suite still passes; only games tests move out.
- R5: TalentShare no longer contains games: no Games tab, no `grev`/`WANTG`/`GAMES`, no `Core/Play`, no games locale
  strings, no anim/game dev commands. Store schema 5 deletes `games` and the games UI keys (**fresh start**).
- R6: GuildGames (`wowaddons/guildgames`, slash `/gg`, dev `/ggd`) has the coin flip and slot machine with their
  animations and leaderboards, as in TalentShare 0.6.0. It uses its own SavedVariables (`GuildGamesDB` / `GuildGamesDevDB`),
  its own prefix (`GGames` / `GGamesDev`), protocol 1.0 (`HELLO {grev?, login?}`, `WANTG {names, via?}`, `GAMES {games}`), and syncs
  through LibGuildSync.
- R7: Each repo has an offline suite (`luajit tests/run.lua`) and `tools/deploy.ps1` / `tools/package.ps1`. The package
  embeds a real copy of the library, never a link.

## Non-goals
- No import of 0.6.0 game results (user chose a fresh start).
- No bridge to 0.6.0 peers' `GAMES` messages.
- No standalone library addon (user chose embedded).
- No new game features, and no change to the game rules or the animation.

## Design
### LibGuildSync (`wowaddons/libguildsync/LibGuildSync/`), loaded in this order by `LibGuildSync.xml`
| File | Content | Instance or shared |
|---|---|---|
| `Core.lua` | `LibStub:NewLibrary("LibGuildSync-1.0", MINOR)`; `lib:Module(name, minor)` upgrade guard | - |
| `Utility.lua` | TalentShare `Core/Base/Utility.lua` minus `Me` | shared (one player, one realm-alias state) |
| `Log.lua` | `Log.New{ entries = fn, title, isDevelopment }` | instance |
| `Trace.lua` | `Trace.New{ entries = fn, log, summarize }` | instance |
| `Codec.lua` | `Codec.Serialize/Deserialize` + `Codec.New{ major, minor }` | instance |
| `Guard.lua` | unchanged | shared |
| `Locale.lua` | `Locale.Format`, `Locale.Plural`, `Locale.New()` (Text, Register, SetInterfaceLanguage) | instance |
| `Events.lua` | `Events.New(log)` -> On/Fire | instance |
| `Sync.lua` | generic engine: `Sync.New(environment)`, `:AddRecordKind`, `:AddHelloHook`, `:AddHandler` | instance |
| `Guild.lua` | IsGuilded, RequestRoster, GetGuildRoster, MyBaseName, PlayerName, IdentityInformation | shared |
| `Channel.lua` | `Channel.New(options)`: TalentShare `Communication` transport part, closures (dot-call API kept) | instance + shared bucket/driver |
| `Widgets.lua` | CreateFontString, CreateButton, CreateScrollList, CreateSelectableRow, CreateDialogFrame, TimeAgo | shared |

- Each addon wires it as `addon.Utility = setmetatable({ Me = ... }, { __index = lib.Utility })`, `addon.Log = lib.Log.New(...)`,
  and so on, so the addon code keeps calling `addon.<Module>.<Function>`.
- TalentShare `Core/Net/Sync.lua` becomes an adapter: `Sync.New(environment)` builds the engine and registers `char`
  (WANT/SNAP), `offers` (WANTO/OFFERS), the orders HELLO hook (odig -> OPUSH) and the ORDER/OPUSH handlers. It keeps
  `sync.wanted`, `sync.wantedOffers`, `sync.pending` and `sync.statistics` (tests and Diagnostics read them).
- TalentShare `Core/Net/Communication.lua` = `lib.Channel.New{...}` plus the TalentShare parts: slash commands, Store
  hooks, localized notices.

### GuildGames (`wowaddons/guildgames/`)
`Core/Init.lua` (identity and build flag, as TalentShare), `Core/Store.lua` (schema 1: games, ui, debug, trace, me),
`Core/Games.lua` + `CoinFlip.lua` + `Slots.lua` (moved unchanged apart from the namespace), `Core/Model.lua` (MoneyText,
leaderboard rows), `Core/Api.lua` (random, sounds), `Core/Sync.lua` (games kind), `Core/Communication.lua`,
`Core/Events.lua`, `Locales/enUS.lua`/`deDE.lua`, `UI/Animate.lua`, `UI/Window.lua` (own window), `UI/GamesTab.lua`,
`UI/SlotMachine.lua`, `UI/DevProbe.lua` (anim probe, sim).

- Data shape change: TalentShare schema 4 -> 5 (drop `games`, `ui.lastStakeCopper`, `ui.lastSlotStakeCopper`,
  `ui.gamesScope`, `ui.gameKey`). GuildGames schema 1 = TalentShare's game record shape (docs: protocol.md section 9).
- Message shape change: TalentShare stops sending `grev` and stops handling `WANTG`/`GAMES` (a 0.6 peer's are
  dropped as "unknown message type"; its `grev` is ignored). The GuildGames protocol is new (above).

## Tasks
- [x] T1 (M): library repo: Core registry, Utility, Log, Trace, Codec, Guard, Locale, Events, with offline tests including the
  two-copies load test. Verify: `luajit tests/run.lua` in libguildsync.
- [x] T2 (L): library Sync engine, tests ported from TalentShare sync/canon/soak semantics. Verify: libguildsync suite.
- [x] T3 (L): library Channel, Guild, Widgets; Channel tests (chunking, gate, echo, retry on throttle, shared bucket).
  Verify: libguildsync suite.
- [x] T4 (L): TalentShare on the library (embed tooling, TOC, adapters), every non-games test unchanged and green.
  Verify: talentshare suite.
- [x] T5 (M): remove games from TalentShare (files, Sync kind, Store schema 5, Window tab, DevProbe, locales, tests).
  Verify: talentshare suite + new migration test.
- [x] T6 (L): GuildGames addon (scaffold, modules, window, moved games code and tests, sync tests over a fake bus).
  Verify: guildgames suite + load test.
- [x] T7 (S): tools for all three repos: embed (dev junction / package copy), deploy, package; `.pkgmeta`.
  Verify: run package.ps1 in both addons, inspect the zips.
- [x] T8 (S): docs: doc.md, READMEs, CHANGELOGs, docs/status.md, docs/protocol.md, INDEX. Verify: read-through.

## Review Focus (failure modes a happy-path test would miss)
1. RF1: Two addons embed different library minors, in either load order -> exactly one copy of each module is active, the
   newer one; state tables survive an upgrade in place. Pinned by: T1 (two-copies test).
2. RF2: Both addons send at once -> one shared token bucket, so together they never exceed the server's addon-message rate.
   Pinned by: T3.
3. RF3: TalentShare wire compatibility with 0.6.0 peers (HELLO/WANT/SNAP/OFFERS/ORDER/OPUSH byte-identical meaning; 0.6
   `grev`/`WANTG`/`GAMES` ignored without errors). Pinned by: T4/T5 (existing sync tests + a 0.6-peer test).
4. RF4: The library's shared Utility realm/name state is used by both addons -> no addon-specific identity leaks into it
   (`Me` stays per addon). Pinned by: T4/T6.
5. RF5: GuildGames before the guild roster loads, or outside a guild -> no sends, no errors (the same rule as TalentShare).
   Pinned by: T6.

## Cross-cutting checklist (answer every line; "n/a: reason" is fine)
- [x] Protocol: TalentShare stays at **2.3** (games messages are only removed; 2.3 peers understand everything 0.7 sends). GuildGames
  1.0 on a new prefix.
- [x] Stored data: TalentShare `Store.SCHEMA` 5 (drop games + games UI keys); GuildGames schema 1.
- [x] Trust model: unchanged; the games validation (Games.Sanitize) and the guild gate move as they are.
- [x] Localization: game strings move to GuildGames Locales; TalentShare's locale test covers what is left.
- [x] Load order: Libs (LibStub, LibDeflate, LibGuildSync.xml) first in both TOCs.
- [x] Packaging: package.ps1 copies `../libguildsync/LibGuildSync` into the zip; `Libs/LibGuildSync` is a dev junction and is git-ignored.
- [x] Tests: library suite (new), TalentShare suite (games tests moved), GuildGames suite (moved + new).
- [x] Docs: doc.md, READMEs, CHANGELOGs, status, protocol.

## Decisions (user answers and design choices, newest last)
- 2026-11-18: Library shipped **embedded via LibStub** (players install only the addons). (user)
- 2026-11-18: Library scope = **transport + generic record sync**; TalentShare's Sync is rebuilt on it with the same wire messages. (user)
- 2026-11-18: **Fresh start**: no import of 0.6.0 game results; TalentShare drops them in a migration. (user)
- 2026-11-18: Names: addon **GuildGames** (`wowaddons/guildgames`, `/gg`), library **LibGuildSync-1.0** (`wowaddons/libguildsync`). (user)
- 2026-11-18: TalentShare protocol stays 2.3: a minor bump would show 0.6 users a "newer version with extra features"
  notice although nothing was added. (claude)
- 2026-11-18: Library files list their load order in `LibGuildSync.xml`; each addon TOC loads that xml after LibStub and
  LibDeflate. Each file carries the library MINOR and registers with `lib:Module`; a test pins every file to Core's MINOR. (claude)
- 2026-11-18: Animate stays games-only (moved to GuildGames, not into the library): after the extraction TalentShare no
  longer uses it. (claude)

## Open questions
- In-game checks (both addons loaded together, two guild members) need: user, game, second player.
- 2026-11-18: DEVIATION from the first draft of R6: GuildGames keeps 0.6's message names (`grev`, `WANTG`, `GAMES`) instead
  of `rev`/`WANT`. The new prefix and protocol make the names free; keeping them leaves the moved sync tests and
  the protocol text valid. (claude)
- 2026-11-18: T4 and T5 were done as one step: the Sync adapter was written without the games kind. (claude)

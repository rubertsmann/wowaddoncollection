# LibGuildSync-1.0

Guild addon-message sync and the helpers around it, for WoW Forever (interface 16001) addons. It is embedded with
LibStub: each addon ships a copy under `Libs/LibGuildSync` and only the newest copy runs. Used by TalentShare and
GuildGames.

## Embedding
- The TOC loads, in this order: `Libs\LibStub\LibStub.lua`, `Libs\LibDeflate\LibDeflate.lua`,
  `Libs\LibGuildSync\LibGuildSync.xml`.
- In a working copy, `Libs\LibGuildSync` is a directory junction to `..\libguildsync\LibGuildSync`, created by each
  addon's `tools/deploy.ps1` and git-ignored. The addon's `tools/package.ps1` copies the real files into its zip and
  checks that every file listed in `LibGuildSync.xml` is there.
- Upgrade rule: `Core.lua` registers `LibGuildSync-1.0` with `MINOR`, and every other file registers its module through
  `lib:Module(name, MINOR)`. A newer copy upgrades each module table in place, so instances made earlier run the new
  code. An equal or older copy is skipped file by file. **Bump MINOR in every file on any change**
  (`tests/test_core.lua` checks that they match). Keep state that must survive an upgrade in fields (`x = x or {}`),
  never in file locals.

## Modules (`local lib = LibStub("LibGuildSync-1.0")`)
| Module | What | Shared or per addon |
|---|---|---|
| `Utility` | names and realms (canonical names, Forever surnames, whisper targets), tables, untrusted input, UTF-8, search keys | shared state: it belongs to the player |
| `Log.New{entries, title, isDevelopment}` | one line format `<time> LEVEL [area] message :: k=v`, repeat folding, Exception/Protected | per addon |
| `Trace.New{entries, log, summarize}` | network trace ring: one entry per message and its fate | per addon |
| `Codec.New{major, minor}` | safe serializer + LibDeflate + chunk header with the protocol version | per addon |
| `Guard` | inbound gate: GUILD, or WHISPER from a roster member; nothing else | shared |
| `Locale.New()` | `Text[...]` with fallback to the English key, `Format`, `Plural` | per addon |
| `Events.New(log)` | protected pub/sub | per addon |
| `Sync.New(environment)` | record-pull engine: HELLO revisions -> request by whisper -> record, retries on GUILD (45/90/180 s), give-up reset, GUILD answer dedup, asked-name answers, login reply budget; `AddRecordKind`, `AddHelloHook`, `AddHandler` | per addon |
| `Channel.New(options)` | transport for one prefix: chunking, reassembly, gate, echo/realm learning, HELLO coalescing, roster/identity check, minute ticker | per addon; **one send token bucket and one driver frame for all channels** |
| `Guild` | roster, my name (Forever "First Surname"), identity facts | shared |
| `Widgets` | plain-frame helpers: button, font string, scroll list, selectable row, dialog frame, TimeAgo | shared |
| `Addon` (MINOR 2) | `Setup(addon, addonName, options)`: build flag, version, title, prefix, SavedVariables, frame names, slash commands and dispatcher, Print; `AddDiagnosticCommands(addon)`: comm, hello, debug, trace | per addon (functions only) |

Trust model: guild members are trusted, everyone else is not. A peer can only author its own records (checked by
`Sync`), and every received record is rebuilt by the kind's own allow-list `sanitize`.

## Tests
`luajit tests/run.lua` (from the repo root). Each test loads a fresh library. The tests cover the upgrade rules, the
engine over a fake guild bus (lost whispers, give-up, forgery, login budget, hooks) and the channel (chunking, gate,
versions, the shared bucket across two prefixes, throttling, echo learning, HELLO coalescing). The addons' own suites run
their protocols on top of it.

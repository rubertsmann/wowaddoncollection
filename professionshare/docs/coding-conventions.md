# Coding conventions

How code in this addon is written. `tests/` enforce parts of it (load order, localization lint, build flag); the rest is
checked in review.

## Names

- **Full words, never abbreviations or single letters.** `characterRecord`, not `rec`; `message`, not `msg`;
  `index`, not `i`; `errorMessage`, not `err`. Allowed exceptions:
  - widely used acronyms: `UI`, `ID` (`recipeID`), `API`, `UTF8`;
  - real words: `ok` (pcall result), `me` (my own canonical name);
  - Lua and WoW globals (`_G`, `os`, `C_Item`, `GetItemInfo`, ...);
  - `_` for a value that is deliberately ignored.
- **Data that leaves the code keeps its short names.** Wire-protocol fields (`t`, `v`, `rev`, `odig`, `orev`, `char`,
  `qty`, ...), SavedVariables keys (`chars`, `profNames`, `db.me`, `debug`, trace entry fields `st`/`mt`/`ch`, ...) and
  the words players type (`/ps chars`, `/ps comm`) are a contract with other clients, saved files and players. Renaming
  them breaks compatibility, so they stay; each module that defines such a shape says so in its header and documents it
  with `---@class`.
- **The same thing has the same name in every module**, so related code is easy to find:

  | Concept | Name |
  |---|---|
  | addon table (`local addonName, addon = ...`) | `addon` |
  | `"Name-Realm"` key of a player | `playerName`, or its role: `sender`, `requester`, `crafter`, `owner`, `myName` |
  | character / offer record, catalog / trace entry | `characterRecord`, `offerRecord`, `catalogEntry`, `traceEntry` |
  | an order and the order board object | `order`, `orderBoard` |
  | protocol message and its type | `message`, `messageType` |
  | ids | `recipeID`, `itemID`, `orderID`, `skillLineID`, `transferID` |
  | a profession entry and its key | `profession`, `professionKey` (`canonicalKey` after `Names.ProfessionKey`) |
  | SavedVariables table / injected dependencies | `database` (`addon.db`), `savedVariables`, `environment` |
  | pcall results | `ok, errorMessage` |
  | rows built for the UI | `<thing>Row` (`recipeRow`, `orderRow`, `offerRow`) |
  | widgets | `<purpose><WidgetKind>` (`searchBox`, `craftButton`, `recipeCountText`) |

- Module tables carry the module's full name: `Utility`, `Communication`, `Diagnostics`, `Store`, ... Localized text is
  `addon.Text["English text"]` (aliased `local Text = addon.Text`).

## Module guards (`if addon.X then`)

Do not guard calls to other modules. The TOC fixes the load order, every module exists before any event or command
runs, and `tests/run.lua` loads the same modules in the same order. A missing module is a broken TOC: `Core/Game/Events.lua`
reports it once at load ("not loaded: ...") and `tests/test_load.lua` fails, so a guard would only hide the bug.

A check is right only when the thing can really be absent:
- a module that loads LATER is used while a file is still loading (top-level code, not functions called later);
- a code path the offline tests run reaches a client-only module the harness does not load (Api, Scanner, Events, UI),
  e.g. `Utility.Me` falling back to `Api` (pinned by tests/test_helpers.lua);
- a WoW client API that differs between game versions (`C_TradeSkillUI`, `Settings`, `C_Container`, ...);
- data that may not exist yet (`addon.db` before `ADDON_LOADED`, an optional field).

## Types

Lua has no static types. Every function that other code calls, and every non-trivial local function, has
[LuaLS](https://luals.github.io/wiki/annotations/) annotations (`---@param`, `---@return`), and every table shape that is
passed between modules has a `---@class` next to the code that owns it (`CharacterRecord` in Store.lua, `Order` in
Orders.lua, `TraceEntry` in Trace.lua, ...). With the "Lua" extension (sumneko / LuaLS) in VS Code these are checked while
typing.

## Logging (`Core/Base/Log.lua`)

There is no live debugger in the game client: the log is the evidence. Never `print` diagnostics or build log strings by
hand; use the one helper:

```lua
addon.Log.Error("communication.send", "the client refused an addon message", { reason = reason, channel = channel })
addon.Log.Warning("store.load", "dropped stored records that failed validation", { count = droppedCount })
addon.Log.Information("events.versionReset", "a new version dropped guild data; it is fetched again", { ... })
addon.Log.Debug("window.whisper", "a whisper was opened", { player = playerName, target = whisperTarget })
addon.Log.Exception("sync.message", "a message handler failed", errorMessage, { messageType = message.t })
local ok, result = addon.Log.Protected("events.itemScan", "the recipe item scan failed", addon.Api.ScanItems)
```

- Line format: `<date time> <LEVEL> [<area>] <message> :: key=value key=value` (keys sorted, values escaped and cut).
- `area` = `<module>.<operation>` (lower camelCase); grep for it to find the code that wrote the line.
- `message` = one sentence saying WHAT happened; values go into `details`, never into the sentence.
- Levels: **Error** a feature failed; **Warning** something unexpected was handled; **Information** a normal but
  noteworthy step; **Debug** detail for chasing one problem.
- A caught Lua error goes through `Log.Exception` (adds the stack, forwards to the game's error handler). Code that must
  not stop its caller when something throws uses `Log.Protected` instead of a bare `pcall`.
- A `pcall` that only probes whether a client API exists may stay bare, or log at Debug (`Api.lua` `tryCall`).
- Network messages additionally go to the network trace (`Core/Debug/Trace.lua`); the trace is about messages, the log
  about everything else.
- Read it with `/ps debug [lines]`, in the Debug tab export (`/ps export`), or in `WTF\...\SavedVariables\ProfessionShare.lua`
  after `/reload`.

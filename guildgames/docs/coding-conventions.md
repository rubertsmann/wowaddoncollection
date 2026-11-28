# Coding conventions

How code in this addon is written: the same rules as ProfessionShare (`../professionshare/docs/coding-conventions.md`), so code
reads the same in both addons. `tests/` enforce parts of it (load order, localization lint, module guards, the `ID`
spelling, build flag); the rest is checked in review.

## Folders

| Folder | Holds | WoW calls |
|---|---|---|
| `Core/Base/` | Init (identity, build flag, slash dispatch), Utility, Log, Locale | Init only (TOC metadata) |
| `Core/Debug/` | Trace (network trace) | no |
| `Core/Net/` | Codec, Guard, Sync (protocol), Communication (transport) | through LibGuildSync |
| `Core/Data/` | Store (SavedVariables, schema, migration), Games (game records), Wallet (money pool) | no |
| `Core/Minigames/` | CoinFlip, Slots, Survivor, AzeCaught: the rules of each game, pure Lua | no |
| `Core/View/` | Model: rows and texts for the UI, peer names escaped here | no |
| `Core/Game/` | Api (every client read), Catcher (AZEcaught's client side), Events (event bus + game events) | yes |
| `UI/` | Helpers (first), Animate, ModelView (every 3D model), Window, the game panels | yes |

Pure modules (everything but `Core/Game/`, `Core/Base/Init.lua` and `UI/`) are loaded by `tests/run.lua` and must not
call the client. Clocks and random numbers are parameters, so a bug report can be replayed offline.

## Names

- **Full words, never abbreviations or single letters.** `elapsedSeconds`, not `dt`; `progress`, not `t`;
  `npcInformation`, not `info`; `red, green, blue`, not `r, g, b`. Allowed: `UI`, `ID`, `API`, `UTF8`; `ok` (pcall
  result), `me`; Lua and WoW globals; `_` for an ignored value; `x`/`y` for screen and arena coordinates.
- **Ids end in `ID`**: `npcID`, `typeID`, `displayID`, `animationID` (ProfessionShare: `recipeID`, `itemID`). Pinned by
  tests/test_store_and_locale.lua.
- **Data that leaves the code keeps its short names.** Wire fields (`t`, `v`, `grev`, `games`, `names`, `via`), saved
  record fields (`rev`, `recent`, `npc`, `disp`, `lvl`, `cls`, `st`, `n`, ...), journal detail keys that bug reports are
  replayed from, and the words players type (`/gg caught`, `/gg debug`) are a contract with other clients, saved files
  and players.
- **The same thing has the same name in every module:**

  | Concept | Name |
  |---|---|
  | addon table (`local addonName, addon = ...`) | `addon` |
  | `"Name-Realm"` key of a player | `playerName`, or its role: `myName`, `owner`, `sender` |
  | a character's game record / one game's section of it | `gameRecord`, `section` |
  | a caught NPC: collection entry / the active one | `entry`, `companion` |
  | protocol message and its type | `message`, `messageType` |
  | SavedVariables table / injected dependencies | `database` (`addon.db`), `savedVariables`, `environment` |
  | pcall results | `ok, errorMessage` |
  | rows built for the UI | `<thing>Row` (`leaderboardRow`, `companionRow`); the NPC overlay: `npcView` |
  | widgets | `<purpose><WidgetKind>` (`flipButton`, `resultText`, `goldBox`) |

- Module tables carry the module's full name (`Store`, `AzeCaught`, `UIHelpers`). Localized text is
  `addon.Text["English text"]` (aliased `local Text = addon.Text`).

## One helper per job

Before writing a small helper, look here first:

| Need | Use |
|---|---|
| a number limited to a range | `addon.Utility.Clamp(value, lowest, highest)` (NaN -> lowest) |
| me / now | `addon.Utility.Me()`, `addon.Utility.Now()` |
| copper as coloured "1g 50s" | `addon.Model.MoneyText(copper)` |
| "1h 30m" / "2h" / "45m" / "-" | `addon.Model.Duration(seconds)` |
| "read-only" / "not enough money" refusal | `addon.Model.CommonRefusalText(refusal, myName)` (nil: word your own) |
| a sound by SOUNDKIT name | `addon.Api.PlaySoundNamed({ "NAME", "FALLBACK_NAME" })` |
| an icon that may be missing on this client | `addon.UIHelpers.SetTextureOr(texture, path, fallbackPathOrColor)` |
| window settings (`db.ui`, safe before load) | `addon.UIHelpers.Settings()` |
| a frame's level as a number | `addon.UIHelpers.FrameLevel(frame)` |
| a 3D creature on screen | `addon.ModelView.New(parent, options)` (see "3D models" below) |

A short local alias (`local money = addon.Model.MoneyText`) is fine; a second copy of the body is not.

## 3D models (`UI/ModelView.lua`)

Every creature model the player sees is a view made by `ModelView.New(parent, options)`, shaped like LibGuildSync's
`Channel.New`: one documented options class (`ModelViewOptions`), an object whose functions are bound to it and called
with a dot, state in plain fields.

```lua
local view = addon.ModelView.New(panel, { preset = "portrait", width = 104, height = 150, area = "preview" })
view.frame:SetPoint("TOPRIGHT", -2, -46)          -- the model frame: anchoring and Animate effects
view.Show({ npc = npcID, disp = displayID })      -- loads once per creature; nil clears
view.Play("attack", { restart = true, back = 0.45 })   -- an ANIMATION key, back to the idle pose after 0.45 s
view.Emote("pet", "care")                         -- an emote, then idle; no ambient emote meanwhile
view.Die(); view.Revive()                         -- the death once, then lying, until revived
```

- Poses and actions are keys of `ModelView.ANIMATION` (one catalogue, one pick rule `ModelView.Pick`: the first id the
  model has; the first when the client cannot tell; the last when it has none of them).
- `preset = "portrait"`: the look-at views (AZEcaught, arena, team dialog): DressUpModel, full body, turn and zoom.
  Game actors (Companion Dash, Survivor) use the default PlayerModel with `pad`, `fallback`, `afterLoad`.
- `companion = true`: the creature is a companion record: asleep pose while it sleeps, ambient emotes from
  `view.Tick()`, `view.Reload(reason)` when the panel shows. The max view and the mini view share this.
- `area` journals loads and poses as `caught.model.<area>` (`/gg caught log 20 model`); `quietPoses` keeps a busy view
  (the arena replay) to its loads.
- No other file calls model frame methods for a shown model; `tests/test_model_view.lua` lints it. The only
  exceptions are the functions with the hidden models that read a unit's look (`Catcher.CaptureDisplay` and its
  helpers, `Api.IdentityProbe`, `Api.GenderProbe`) and the dev probes in `UI/DevProbe.lua`. A view lives for the session:
  make it once per place (at Build time), not per call.

## Module guards (`if addon.X then`)

Do not guard calls to other modules. The TOC fixes the load order, every module exists before any event or command
runs, and `tests/run.lua` loads the same modules in the same order. A missing module is a broken TOC:
`Core/Game/Events.lua` reports it once at load ("not loaded: ...") and `tests/test_load.lua` fails, so a guard would
only hide the bug. The lint in tests/test_store_and_locale.lua lists the allowed exceptions:
- a module that loads LATER is used while a file is still loading (`Core/Base/Init.lua` hands an early blocked-action
  event to `addon.OnActionBlocked`, defined in Events.lua);
- a code path the offline tests run reaches a client-only module the harness does not load (`Utility.Me` falling back
  to `Api`, and to `Store` before `Store.Init`);
- a WoW client API that differs between game versions (`SOUNDKIT`, `C_AddOns`, `SetPortraitTexture`, ...);
- data that may not exist yet (`addon.db` before `ADDON_LOADED`, an optional field, a widget not built yet).

A test that loads only some UI files stubs the modules it leaves out (tests/test_games_ui.lua stubs `AzeCaughtPanel`);
the code does not guard for it.

## Types

Every function that other code calls, and every non-trivial local function, has
[LuaLS](https://luals.github.io/wiki/annotations/) annotations (`---@param`, `---@return`), and every table shape that is
passed between modules has a `---@class` next to the code that owns it (`GameRecord` in Games.lua, `SurvivorRun` in
Survivor.lua, `NpcInformation` in AzeCaught.lua, ...).

## Comments

The monorepo's [comment policy](../../docs/comment-policy.md): a comment says WHY (or a client fact, or a data
contract), never who asked or when, never a feature / requirement / task id (those live in `features/` and git). Names
carry the WHAT: prefer a named local function or local over a comment. `tests/test_comments.lua` runs
`tools/comment-audit.lua --strict` on this addon (provenance, dead paths, dead `Module.Name`, `---@param` mismatches).

## Logging (`Core/Base/Log.lua`)

There is no live debugger in the game client: the log is the evidence. Never `print` diagnostics or build log strings by
hand:

```lua
addon.Log.Error("communication.send", "the client refused an addon message", { reason = reason })
addon.Log.Warning("store.load", "dropped invalid saved records", { count = droppedCount })
addon.Log.Information("events.load", "addon loaded", { version = addon.VERSION })
addon.Log.Exception("sync.message", "a message handler failed", errorMessage, { messageType = message.t })
local ok = addon.Log.Protected("caught.start", "starting AZEcaught failed", addon.Catcher.Start)
```

- `area` = `<module>.<operation>` (lower camelCase); `message` = one sentence saying WHAT happened; values go into
  `details`.
- AZEcaught has its own ring, the journal: `addon.AzeCaught.Journal(level, area, message, details)` (area shown as
  `caught.<area>`; WARNING and ERROR lines are mirrored to the main log). Read it with `/gg caught log`.
- Network messages go to the network trace (`Core/Debug/Trace.lua`, `/gg trace`).
- Read the log with `/gg debug [lines]`, or in `WTF\...\SavedVariables\GuildGames.lua` after `/reload`.
- A slash command's output for the player goes through `addon.Print`; diagnostic commands answer in English on purpose.

## Adding a file

1. Put it in the folder its job belongs to (table above) and add it to `GuildGames.toc` after every module it uses at
   load time.
2. A pure module also goes into `Harness.PURE_FILES` in tests/run.lua (same order) and into the missing-modules list in
   `Core/Game/Events.lua`.
3. Run `powershell tools/deploy.ps1` (regenerates GuildGames-Dev.toc; tests/test_load.lua fails while it is stale), then
   restart the game: `/reload` does not re-read the TOC.

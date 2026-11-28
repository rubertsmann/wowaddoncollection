> **Historical (kept for reference):** the original TalentShare plan from the first night. Every task is done or was
> replaced; its checkboxes were never ticked. Current state: `features/INDEX.md` and `docs/status.md`.

# TalentShare Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A guild-only WoW Forever addon that records each character's professions, skill ranks and known recipes, shares them with online guild members, caches everyone's data locally, and shows a searchable recipe browser (with reagents) plus a shared crafting-order board (request / claim / done).

**Architecture:** Pure-Lua logic modules (Store, Codec, Sync, Orders) with no WoW dependencies so they run in an offline test harness under LuaJIT; a thin `Api` adapter isolates every WoW call that may differ on Forever; transport is AceComm over addon prefix `TShare` on the `GUILD` channel; all state lives in the `TalentShareDB` SavedVariable (no backend). UI is a single standalone window built from plain Blizzard frames.

**Tech Stack:** Lua 5.1 (WoW), LuaJIT for offline tests, vendored LibStub / CallbackHandler / ChatThrottleLib / AceComm-3.0 / LibSerialize / LibDeflate, PowerShell deploy script, BigWigs packager + GitHub Actions for CurseForge.

**Spec:** the user's requirements from this conversation (summarised under "Requirements" below); research notes in the conversation (interface 16001, addon-message limits). No separate spec file exists.

## Requirements (from the user)

1. Read **all** professions of the logged-in character: skill rank + all known recipes + each recipe's reagents.
2. Share with guild members; **cached data is enough** (offline members show last-seen data). No backend; data stored locally in SavedVariables.
3. Sync on login, when the user opens the window, and on level-up (also on profession/skill change).
4. Standalone window. Filter by profession; search; keep it simple. Show what each recipe needs.
5. **Order/demand system:** a member can request a recipe (qty, note); crafters can confirm "I'll craft this"; status of who confirmed what is globally visible to the guild.
6. Guild scope only. First release may be a manual install; CurseForge for easy install after.

## Global Constraints

- Target `## Interface: 16001` (Forever 1.60.1); confirm in T3 with `/dump select(4, GetBuildInfo())`. TOC filename = folder name = `TalentShare`.
- Addon message prefix: `TShare` (max 16 chars). Message limit 255 bytes, no NUL. Per-prefix throttle: burst 10, refill 1/s. All sends go through AceComm/ChatThrottleLib, never raw `SendAddonMessage` in loops.
- Lua is WoW's modified 5.1: no `goto`, `//`, bitwise operators (use `bit`), no `require`/`io`/`os`. Load order = TOC order.
- Time source is `GetServerTime()` (shared across guild), never `os.time()`.
- Combat log is unavailable; some values are "secret". This addon reads none of them, but guard `InCombatLockdown()` before touching protected frames (our window must not be protected).
- Trial/Veteran accounts cannot send addon messages: the addon must degrade to receive-only without errors.
- SavedVariable: `TalentShareDB`. Protocol version constant `ns.PROTOCOL = 1`.
- No external services. Libraries are vendored in `Libs/`.
- Complexity scale (agent working time): **S** < 1 h, **M** 1-3 h, **L** 3-6 h.

## Review Focus

Failure modes the requirements imply but a happy-path test would miss. Each is pinned by a test in the task named in brackets.

1. **RF1 – No guild / left guild:** `IsInGuild()` false → no sends, no errors, UI shows "Join a guild". Members who left the guild are pruned from the cache. [T11]
2. **RF2 – Empty or partial scan:** profession window opened but recipe list not loaded yet (`GetAllRecipeIDs` returns `{}` before first open) must not wipe the cached recipes; a *dropped* profession must be removed. [T7]
3. **RF3 – Login storm:** 300 members log in at once → HELLO replies are jittered and suppressed, per-prefix throttle never exceeded, no disconnect. [T10]
4. **RF4 – Concurrent claims:** two crafters claim the same order at the same time, or the requester/claimer is offline → merge is a commutative, idempotent union; no claim is lost; orders never "flip back". [T12]
5. **RF5 – Garbage / foreign messages:** malformed, oversized, wrong-protocol-version or self-sent messages are dropped silently without Lua errors; a peer cannot overwrite another character's record. [T9, T10]

## File Structure

```
talentshare/                      (repo root == addon root)
  TalentShare.toc
  Libs/                           vendored libs + Libs.xml            (T4)
  Core/Base/Init.lua                   namespace `ns`, slash command, version   (T1)
  Core/Base/Utility.lua                   small pure helpers                       (T2)
  Core/Data/Store.lua                  SavedVariables schema, pruning (pure)    (T5)
  Core/Game/Api.lua                    ALL WoW-version-specific calls           (T6)
  Core/Data/Scanner.lua                professions/recipes -> Store             (T7)
  Core/Game/Events.lua                 event wiring, debounce, level-up         (T8)
  Core/Net/Codec.lua                  serialize + compress + validate (pure)   (T9)
  Core/Net/Sync.lua                   protocol state machine (pure)            (T10)
  Core/Net/Communication.lua                   AceComm transport + guild gating         (T11)
  Core/Data/Orders.lua                 order model + merge (pure)               (T12)
  UI/Window.lua                   shell, slash, minimap button             (T14)
  UI/RecipeList.lua               filter/search/list                       (T15)
  UI/RecipeDetail.lua             reagents, crafters                       (T16)
  UI/OrdersTab.lua                order board                              (T17)
  tests/run.lua, tests/wowstubs.lua, tests/test_*.lua                       (T2+)
  dev/TalentShareProbe/           throw-away API probe addon               (T3)
  tools/deploy.ps1, tools/package.ps1                                       (T1, T18)
  docs/api-findings.md            probe results                            (T3)
  .pkgmeta, .github/workflows/release.yml                                   (T18)
```

Convention: every addon file starts `local ADDON, ns = ...`; offline tests load a file with `loadfile(path)("TalentShare", ns)`.

## Roles and how work is verified

- **Implementer** = `general-purpose` subagent on Sonnet (one task at a time, reads only its own task + Global Constraints).
- **Architect** = main session (Opus/Sonnet 5.5) for the two correctness-critical tasks (T10 Sync, T12 Orders merge) — do these inline, not delegated.
- **Tester** = Haiku subagent. Runs `luajit tests/run.lua`, or reads SavedVariables written by an in-game session, and **reports only counts/failing test names** (keeps the main context small).
- **USER GATE** = a step only the user can do (launch the game, click the UI, second character). Everything before a gate is verified offline; the gate is a short checklist so it takes minutes.
- In-game results are made machine-readable: `ns.Debug.Log(tag, ...)` appends to `TalentShareDB.debug` (ring buffer, 200 entries). After the user does `/reload` or logs out, the Tester reads `World of Warcraft\_forever_\WTF\Account\<ACCOUNT>\SavedVariables\TalentShareDB.lua` and asserts on it.

## Dependency graph

```
T1 ─┬─ T2 ─┬─ T5 ─┬─ T7 ─ T8 ──────────────┐
    │      │      │                         ├─ T11 ─ T13 ─┐
    ├─ T3 ─┴─ T6 ─┘   T9 ─ T10 ────────────┘             │
    ├─ T4 ── T9                T12 ─ T13                  ├─ T14 ─ T15 ─ T16 ─ T17 ─ T18 ─ T19
    └──────────────────────────────────────────────────────┘
```
T3, T4, T9, T12 can run in parallel once T1/T2 are done. UI tasks (T14+) need T5 and T11/T13 interfaces but can use fake data until sync is merged.

## Estimate summary

| # | Task | Agent | Size | Needs user gate |
|---|------|-------|------|-----------------|
| T1 | Scaffold + deploy + hello | Implementer | S | yes (login) |
| T2 | Offline test harness | Implementer | S | no |
| T3 | API probe addon + findings | Implementer + Tester | M | yes (open professions) |
| T4 | Vendor libraries | Implementer | S | yes (login) |
| T5 | Store (SavedVariables schema) | Implementer | S | no |
| T6 | Api adapter | Implementer | M | yes (verify) |
| T7 | Scanner | Implementer | M | yes |
| T8 | Event wiring + triggers | Implementer | S | yes |
| T9 | Codec | Implementer | S | no |
| T10 | Sync protocol (pure) | Architect | L | no |
| T11 | Comm transport + guild | Implementer | M | yes (2 chars) |
| T12 | Orders model + merge | Architect | M | no |
| T13 | Orders sync | Implementer | M | yes (2 chars) |
| T14 | Window shell | Implementer | M | yes |
| T15 | Recipe browser | Implementer | L | yes |
| T16 | Recipe detail + reagents | Implementer | M | yes |
| T17 | Orders UI | Implementer | L | yes |
| T18 | Packaging + release | Implementer | M | yes |
| T19 | Soak + hardening | Tester + Implementer | M | yes |

Total ≈ 30-45 agent-hours; user time ≈ 10 short in-game checks.

---

## Phase 0 – Foundations

### Task 1: Scaffold, deploy script, "hello"

**Size:** S · **Agent:** Implementer · **Depends on:** none

**Files:**
- Create: `TalentShare.toc`, `Core/Base/Init.lua`, `tools/deploy.ps1`, `.gitignore`, `README.md`

**Interfaces:**
- Produces: global-free namespace `ns` (second vararg of every file) with `ns.VERSION = "0.1.0"`, `ns.PROTOCOL = 1`, `ns.Print(msg: string)`; slash `/ts` and `/talentshare`.

- [ ] **Step 1:** `talentshare/` sits inside an unrelated parent git repo (Unity project). Ask the user, then run `git init` in `wowaddons/talentshare` so this addon has its own history.
- [ ] **Step 2:** Write `TalentShare.toc`: `## Interface: 16001`, `## Title: TalentShare`, `## Notes`, `## Author`, `## Version: 0.1.0`, `## SavedVariables: TalentShareDB`, then `Core\Base\Init.lua`.
- [ ] **Step 3:** `Core/Base/Init.lua`: create `ns`, register `SLASH_TALENTSHARE1 = "/ts"`; `/ts` prints `TalentShare 0.1.0`; `/ts version` same.
- [ ] **Step 4:** `tools/deploy.ps1 -WowDir <path>`: creates a directory junction `<WowDir>\_forever_\Interface\AddOns\TalentShare` → repo root (idempotent; refuses to overwrite a real folder). `.gitignore` ignores `*.zip`, `.release/`.
- [ ] **Step 5 – USER GATE verify:** run `powershell tools/deploy.ps1 -WowDir "<path>"`, start the Forever client, enable `/console scriptErrors 1`. Expected: addon listed on the character-select AddOns screen (not "out of date"); `/ts` prints `TalentShare 0.1.0`; zero Lua errors.
- [ ] **Step 6:** Commit `feat: scaffold addon and deploy script`.

### Task 2: Offline test harness

**Size:** S · **Agent:** Implementer · **Depends on:** T1

**Files:** Create `tests/run.lua`, `tests/wowstubs.lua`, `tests/test_util.lua`, `Core/Base/Utility.lua`; modify `TalentShare.toc`.

**Interfaces:**
- Produces: `tests/run.lua` (discovers `tests/test_*.lua`, each returns a table `{ name = function() ... end }`; prints `N passed, M failed`; exit code 1 on failure). `tests/wowstubs.lua` returns `function install(env) -> ns` defining stubs: `GetServerTime() -> number` (settable via `env.now`), `C_Timer.After`, `LibStub`, `IsInGuild() -> bool`. `Util.lua`: `ns.Util.DeepCopy(t) -> table`, `ns.Util.FullName(name: string, realm: string?) -> string` (`"Name-Realm"`, realm spaces stripped), `ns.Util.Count(t) -> number`.

- [ ] **Step 1:** Install LuaJIT (any Lua 5.1-compatible), confirm `luajit -v`.
- [ ] **Step 2:** Write failing tests in `tests/test_util.lua`: `FullName("Bob","Area 52") == "Bob-Area52"`; `FullName("Bob-Area52") == "Bob-Area52"`; `DeepCopy` produces an independent table; `Count({a=1,b=2}) == 2`.
- [ ] **Step 3:** Run `luajit tests/run.lua` → expect FAIL (Util missing).
- [ ] **Step 4:** Implement `Core/Base/Utility.lua` and `run.lua`/`wowstubs.lua`; add `Core\Base\Utility.lua` to the TOC.
- [ ] **Step 5:** Run `luajit tests/run.lua` → `4 passed, 0 failed`, exit code 0.
- [ ] **Step 6:** Commit.

**Verification by:** Tester (Haiku) runs the command and reports the counts.

### Task 3: API probe addon and findings

**Size:** M · **Agent:** Implementer writes, Tester reads output · **Depends on:** T1

**Purpose:** removes the biggest uncertainty (which profession/guild APIs exist on Forever) before any real code depends on them.

**Files:** Create `dev/TalentShareProbe/TalentShareProbe.toc`, `dev/TalentShareProbe/Probe.lua`, `docs/api-findings.md`. Extend `tools/deploy.ps1` to also junction `dev/TalentShareProbe`.

**Interfaces:**
- Produces: SavedVariable `TalentShareProbeDB` with `{ build = {version, build, interface}, apis = {[name]=bool}, events = {...}, samples = {...} }`, and `docs/api-findings.md` with a table: API → exists? → return shape → chosen use in T6.

- [ ] **Step 1:** `Probe.lua` records `apis[...] = (type(x)=="function")` for: `C_TradeSkillUI.GetAllRecipeIDs/GetRecipeInfo/GetRecipeSchematic/GetBaseProfessionInfo/GetTradeSkillLine/GetTradeSkillLineInfoByID`, legacy `GetNumTradeSkills/GetTradeSkillInfo/GetTradeSkillReagentInfo/GetTradeSkillNumReagents/GetTradeSkillReagentItemLink/GetTradeSkillRecipeLink`, `GetProfessions`, `GetProfessionInfo`, `C_ChatInfo.RegisterAddonMessagePrefix/SendAddonMessage/IsAddonMessagePrefixRegistered`, `C_GuildInfo.GuildRoster`, `GetNumGuildMembers`, `GetGuildRosterInfo`, `IsInGuild`, `C_Spell.GetSpellInfo`, `C_Item.GetItemInfo`, `C_Item.RequestLoadItemDataByID`, `GetServerTime`, `GetTradeSkillLine`, `GetSkillLineInfo`, `GetNumSkillLines`.
- [ ] **Step 2:** Add a slash `/tsp scan` that, if a profession window is open, records for the first 5 recipes the raw returns (as `tostring`ed key/values) of the working recipe-info and reagent calls; and `/tsp events` that logs every event name fired by opening/closing a profession window and changing skill (register `TRADE_SKILL_SHOW`, `TRADE_SKILL_LIST_UPDATE`, `TRADE_SKILL_DATA_SOURCE_CHANGED`, `SKILL_LINES_CHANGED`, `CHAT_MSG_SKILL`, `PLAYER_LEVEL_UP`, `GUILD_ROSTER_UPDATE`, `CHAT_MSG_ADDON`).
- [ ] **Step 3 – USER GATE:** deploy; log in on a character with ≥2 professions; run `/tsp scan`, open each profession window, run `/tsp scan` again, then `/reload`.
- [ ] **Step 4:** Tester reads `TalentShareProbeDB` and reports which APIs exist and the sample shapes. Implementer writes `docs/api-findings.md` including: final interface number, correct TOC suffix (`_Forever`/`_Camelot`/none needed), whether profession windows expose recipe IDs, where reagents come from, whether recipe IDs are spell IDs.
- [ ] **Step 5:** Commit `docs: forever API findings`.

**Verification:** `docs/api-findings.md` has no "unknown" rows for the APIs T6 needs; if profession APIs are missing, STOP and re-plan T6/T7.

### Task 4: Vendor libraries

**Size:** S · **Agent:** Implementer · **Depends on:** T1

**Files:** Create `Libs/LibStub/`, `Libs/CallbackHandler-1.0/`, `Libs/ChatThrottleLib/`, `Libs/AceComm-3.0/`, `Libs/LibSerialize/`, `Libs/LibDeflate/`, `Libs/Libs.xml`; modify `TalentShare.toc` (load `Libs\Libs.xml` first); add `Libs/LICENSES.md`.

- [ ] **Step 1:** Download current releases from their GitHub repos (Ace3 / ChatThrottleLib / LibSerialize / LibDeflate) into `Libs/`; record repo URL + version + license per lib in `LICENSES.md`.
- [ ] **Step 2:** Add `/ts libs` printing `LibStub:GetLibrary(name, true)` presence for each lib.
- [ ] **Step 3:** Add `tests/test_libs.lua`: loads LibStub, LibDeflate and LibSerialize via `loadfile`; asserts `LibDeflate:DecompressDeflate(LibDeflate:CompressDeflate(s)) == s` for a 5 KB string and `LibSerialize:Deserialize(LibSerialize:Serialize(t))` round-trips a nested table.
- [ ] **Step 4:** Run `luajit tests/run.lua` → pass. **USER GATE:** `/ts libs` shows all six libs present, no Lua errors.
- [ ] **Step 5:** Commit.

---

## Phase 1 – Local data

### Task 5: Store (SavedVariables schema)

**Size:** S · **Agent:** Implementer · **Depends on:** T2

**Files:** Create `Core/Data/Store.lua`, `tests/test_store.lua`.

**Interfaces:**
- Produces (`ns.Store`):
  - `Init(sv: table|nil) -> table` — returns/normalises `TalentShareDB` = `{ schema=1, chars={}, catalog={}, orders={}, debug={}, me=nil }`
  - `PutChar(rec: CharRecord) -> boolean` — stores only if `rec.rev` > existing `rev`; returns changed
  - `GetChar(fullName: string) -> CharRecord|nil`
  - `ListChars() -> CharRecord[]` (sorted by name)
  - `PutCatalog(entries: table<recipeID, CatalogEntry>)` — insert if absent
  - `GetRecipe(recipeID: number) -> CatalogEntry|nil`
  - `Prune(rosterNames: table<string,true>, keepUnknownDays: number)` — drop chars not in roster
  - `Crafters(recipeID: number) -> CharRecord[]` — chars knowing it
- `CharRecord = { name="Bob-Realm", class="MAGE", level=60, rev=<serverTime>, professions = { [skillLineID] = { name="Cooking", rank=225, max=300, recipes = { [recipeID]=true } } } }`
- `CatalogEntry = { name="Roasted Boar Meat", icon=133964, minSkill=1, produces=itemID|nil, reagents={ {itemID=769, count=1} } }`

- [ ] **Step 1:** Write tests: `Init(nil)` returns schema 1; `PutChar` with older rev returns false and keeps new; `Crafters(42)` returns only chars whose `professions[*].recipes[42]`; `Prune({["A-R"]=true})` removes `B-R`; `Init` with a table missing `orders` fills it (migration-safe).
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS. **Step 5:** Commit.

### Task 6: Api adapter

**Size:** M · **Agent:** Implementer · **Depends on:** T3, T5

**Files:** Create `Core/Game/Api.lua`, `tests/test_api.lua`; modify TOC.

**Interfaces:**
- Produces (`ns.Api`) — the *only* file that calls profession/guild WoW APIs:
  - `GetPlayerProfessions() -> {skillLineID:number, name:string, rank:number, max:number}[]` (works without a window; all professions incl. secondary)
  - `GetOpenProfession() -> {skillLineID, name, rank, max, recipes = { {recipeID, name, icon, minSkill, produces, reagents={{itemID,count}}} }} | nil` (nil when no window open)
  - `GetGuildRoster() -> table<string,true>` (full names)
  - `GetPlayerInfo() -> {name:string, class:string, level:number}`
  - `IsGuilded() -> boolean`
- Implementation choice per T3 findings; fall back chain documented in the file header.

- [ ] **Step 1:** Write `tests/test_api.lua` using stubs that emulate the two API shapes found in T3 (recorded sample from `docs/api-findings.md`): assert normalised output equal for both shapes; `GetOpenProfession()` returns nil when the stub window is closed.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement from T3 findings. **Step 4:** Run → PASS.
- [ ] **Step 5 – USER GATE:** add `/ts dump` printing `GetPlayerProfessions()` and (if window open) recipe count + first recipe with reagents. Expected: matches what the profession window shows.
- [ ] **Step 6:** Commit.

### Task 7: Scanner

**Size:** M · **Agent:** Implementer · **Depends on:** T5, T6

**Files:** Create `Core/Data/Scanner.lua`, `tests/test_scanner.lua`; modify TOC.

**Interfaces:**
- Consumes: `ns.Api.*`, `ns.Store.*`.
- Produces (`ns.Scanner`): `Refresh(now: number) -> changed:boolean` — rebuilds *my* `CharRecord` from `Api.GetPlayerProfessions()` (rank/max), merges recipes from `Api.GetOpenProfession()` when open, writes catalog entries, bumps `rev = now` only if something changed, stores via `Store.PutChar`, remembers my name in `TalentShareDB.me`.

- [ ] **Step 1:** Write tests with a fake Api: (a) first scan stores 3 recipes + catalog + reagents; (b) re-scan identical data → `changed == false`, `rev` unchanged; (c) **RF2:** window "open" but `recipes = {}` → previously cached recipes for that profession are kept; (d) profession no longer in `GetPlayerProfessions()` → removed from record; (e) rank 100 → 125 → `changed == true`, recipes kept.
- [ ] **Step 2-4:** FAIL → implement → PASS (`luajit tests/run.lua`).
- [ ] **Step 5 – USER GATE:** `/ts scan` then `/reload`; Tester reads `TalentShareDB.chars["<me>"]` and compares recipe counts to the user's reported counts per profession.
- [ ] **Step 6:** Commit.

### Task 8: Event wiring and refresh triggers

**Size:** S · **Agent:** Implementer · **Depends on:** T7

**Files:** Create `Core/Game/Events.lua`, `tests/test_events.lua`; modify TOC. Also create `ns.Debug.Log(tag: string, ...)` (ring buffer 200 in `TalentShareDB.debug`) in `Core/Base/Utility.lua`.

**Interfaces:**
- Produces: `ns.Events.On(name: string, fn)`, `ns.Events.Fire(name: string, ...)` for internal events: `LOCAL_CHANGED` (my record changed), `WINDOW_OPENED`. WoW events handled: `PLAYER_LOGIN`, `PLAYER_LEVEL_UP`, `TRADE_SKILL_SHOW`, `TRADE_SKILL_LIST_UPDATE`, `SKILL_LINES_CHANGED` (names per T3 findings) → debounced (1.0 s, `C_Timer.After`) call to `Scanner.Refresh(GetServerTime())`; fires `LOCAL_CHANGED` if changed.

- [ ] **Step 1:** Tests with fake timer: 10 `TRADE_SKILL_LIST_UPDATE` calls in the same second → exactly one `Refresh`; `PLAYER_LEVEL_UP` updates `level` in record and fires `LOCAL_CHANGED`.
- [ ] **Step 2-4:** FAIL → implement → PASS.
- [ ] **Step 5 – USER GATE:** log in, open each profession, level up or learn a recipe if convenient; Tester checks `TalentShareDB.debug` shows exactly one `scan` entry per burst and `LOCAL_CHANGED` only on real changes.
- [ ] **Step 6:** Commit.

---

## Phase 2 – Guild sync

### Task 9: Codec

**Size:** S · **Agent:** Implementer · **Depends on:** T2, T4

**Files:** Create `Core/Net/Codec.lua`, `tests/test_codec.lua`.

**Interfaces:**
- Produces (`ns.Codec`): `Encode(msg: table) -> string` (LibSerialize → LibDeflate compress → `EncodeForWoWAddonChannel`), `Decode(s: string) -> table|nil, err:string|nil`. `Decode` returns `nil, "..."` (never throws) for: non-string, bad encoding, bad inflate, non-table, missing/`~= ns.PROTOCOL` `v`, missing string `t`, decoded size > 64 KB (RF5).

- [ ] **Step 1:** Tests: round-trip a `{v=1,t="HELLO",...}`; `Decode("garbage")` → nil + err; `Decode(nil)` → nil + err; encoding a 300-recipe snapshot yields < 20 KB; message with `v=2` rejected; a decompression-bomb string (1 MB of zeros compressed) rejected by size cap.
- [ ] **Step 2-4:** FAIL → implement → PASS. **Step 5:** Commit.

### Task 10: Sync protocol (pure state machine)

**Size:** L · **Agent:** Architect (main session) · **Depends on:** T5, T9

**Files:** Create `Core/Net/Sync.lua`, `tests/test_sync.lua`.

**Design:**
- Messages (all tables, `v`, `t`): `HELLO {chars = {[fullName]=rev}}` — digest of every character record I hold (only my own `rev` is authoritative, but I advertise all I hold so late joiners learn from anyone); `WANT {names={fullName...}}`; `SNAP {char=CharRecord, catalog={...}}`. Orders messages are added in T13.
- Flow: on login/window-open/`LOCAL_CHANGED` → `Hello()`. On HELLO from X: for every name where remote rev > mine (or unknown) → send `WANT` to X (WHISPER) — at most 5 names per WANT. On WANT: schedule `SNAP` for each requested name I hold, after a random delay 0-`jitter` s, **suppressed** if I have already seen a SNAP for that name+rev since the WANT. A peer may only be believed about its **own** record when it is the sender; other records are accepted only if rev is newer and they pass `ValidateChar`.
- `env` injection for tests: `Sync.New(env)` with `env = { send = function(msg, dist, target) end, now = function() return number end, rand = function() return 0..1 end, store = ns.Store, self = "Me-Realm" }`.

**Interfaces:**
- Produces (`ns.Sync`): `New(env) -> sync`; `sync:Hello()`; `sync:OnMessage(msg: table, sender: string)`; `sync:Tick(now: number)` (fires due jittered sends); `sync.stats = {sent=n, received=n, dropped=n}`; `Sync.ValidateChar(rec) -> boolean` (name string, level 1-80, rev number, rank ≤ max, recipe IDs numeric, ≤ 2000 recipes).

- [ ] **Step 1:** Write tests with a fake network of N Sync instances sharing an in-memory bus:
  - two peers, A has newer record → B ends up with it after `HELLO → WANT → SNAP`;
  - own-echo (`sender == self`) ignored;
  - **RF5:** garbage msg / wrong `t` / `ValidateChar` failure → `dropped` increments, no throw; peer X cannot overwrite Y's record with an *older* rev;
  - **RF3:** 300 peers HELLO at t=0, one peer holds the only copy of K characters → total SNAPs sent for each name ≤ 2 (suppression) and the max sends per instance per second ≤ 1 over a 60 s simulated run;
  - convergence: after random HELLO/loss (20% drop) for 120 simulated seconds with 10 peers, all peers hold identical `rev` for every name.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS (tests are deterministic: seeded `rand`). **Step 5:** Commit.

### Task 11: Comm transport and guild integration

**Size:** M · **Agent:** Implementer · **Depends on:** T8, T10

**Files:** Create `Core/Net/Communication.lua`, `tests/test_comm.lua`; modify TOC (after Sync/Events).

**Interfaces:**
- Consumes: `ns.Sync.New`, `ns.Codec`, AceComm (`RegisterComm("TShare", cb)`, `SendCommMessage(prefix, text, dist, target, prio)`), `ns.Api.IsGuilded/GetGuildRoster`.
- Produces (`ns.Comm`): `Start()` (called on `PLAYER_LOGIN`): registers prefix, creates the `Sync` instance with `send = Codec.Encode → SendCommMessage` (`"GUILD"` or `"WHISPER"`, priority `"BULK"`), starts a 1 s ticker for `sync:Tick`; `ns.Comm.sync` exposes the instance. Listens to `LOCAL_CHANGED` and `WINDOW_OPENED` → `sync:Hello()` (rate-limited to 1 per 30 s). On `GUILD_ROSTER_UPDATE` (requested by `C_GuildInfo.GuildRoster()` at login and every 5 min) → `Store.Prune(roster)`. Not in a guild → `Start()` is a no-op and `ns.Comm.active == false` (RF1). `/ts comm` prints stats.

- [ ] **Step 1:** Tests with stubbed AceComm: `IsGuilded()==false` → no `RegisterComm`, no sends (RF1); `LOCAL_CHANGED` twice within 30 s → one HELLO; roster without "Gone-R" → record pruned (RF1); sending failure result codes (throttle 3, lockdown 11) never raise.
- [ ] **Step 2-4:** FAIL → implement → PASS.
- [ ] **Step 5 – USER GATE (needs a second guild member/alt online with the addon):** both log in. Expected: within ~60 s each client's `TalentShareDB.chars` contains the other character (Tester reads both SavedVariables files after `/reload`); `/ts comm` shows `sent>0 received>0 dropped=0`; no disconnect, no Lua errors. Fallback if no second character: `/ts simulate` feeds recorded messages through `OnMessage` (loopback test, documented as weaker).
- [ ] **Step 6:** Commit.

---

## Phase 3 – Orders

### Task 12: Orders model and merge (pure)

**Size:** M · **Agent:** Architect (main session) · **Depends on:** T2

**Files:** Create `Core/Data/Orders.lua`, `tests/test_orders.lua`.

**Data model:**
```
Order = { id="Bob-Realm:1731700000:1", requester="Bob-Realm", recipeID=2550, qty=3, note="",
          createdAt=1731700000, closed=nil|"done"|"cancelled", closedAt=nil|ts, closedBy=nil|name,
          claims = { ["Amy-Realm"] = { state="claimed"|"withdrawn", t=ts } } }
Status (derived) = "cancelled" | "done" | "claimed" (≥1 claim in state claimed) | "open"
Version v(order) = createdAt + Σ claim.t + (closedAt or 0)
```
Merge rules (CRDT-style, so order of arrival never matters): claims merge per crafter, newer `t` wins (ties: `claimed` loses to `withdrawn`); `closed` — if either side closed, the earlier `closedAt` wins (ties: `cancelled` over `done`); immutable fields come from the lowest `createdAt`.

**Interfaces:**
- Produces (`ns.Orders`): `New(now: function) -> orders`; `:Create(requester, recipeID, qty, note) -> Order`; `:Claim(id, crafter)`; `:Withdraw(id, crafter)`; `:Close(id, by, "done"|"cancelled") -> boolean` (only requester may cancel; requester or a claimer may mark done); `:Merge(order) -> changed:boolean` (rejects invalid, qty 1-99, note ≤ 80 chars, ≤ 50 claims); `:Get(id)`; `:List(filter?) -> Order[]` (filter `{status=, recipeID=, requester=, crafter=}`); `:Status(order) -> string`; `:Digest() -> table<id, v>`; `:Missing(remoteDigest) -> Order[]` (orders I hold that remote lacks or has lower `v`); `:Prune(now, maxAgeSec)` (drops closed orders older than 7 days and open orders older than 30 days).

- [ ] **Step 1:** Write tests: create→claim by A and B→status `claimed`, both claims listed; A withdraws → still `claimed` (B); both withdraw → `open`; `Merge` is **idempotent** (merging same order twice → second returns false) and **commutative** (merge order permutations of 5 random event sequences produce identical orders — RF4); concurrent claim by A and B on two replicas, then exchange → both replicas hold both claims (RF4); cancel by non-requester rejected; `Close done` then late `Claim` still listed but status stays `done`; invalid qty/oversized note rejected; `Digest/Missing` pair returns exactly the differing orders; `Prune` removes only expired.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS. **Step 5:** Commit.

### Task 13: Orders sync

**Size:** M · **Agent:** Implementer · **Depends on:** T11, T12

**Files:** Modify `Core/Net/Sync.lua`, `Core/Net/Communication.lua`, `Core/Data/Store.lua` (persist `orders`), `tests/test_sync.lua`.

**Interfaces:**
- Adds messages: `ORDER {order=Order}` (broadcast to GUILD on any local create/claim/withdraw/close); `ODIGEST {orders={[id]=v}}` (included in HELLO as `HELLO.orders`); `OPUSH {orders={Order...}}` (WHISPER reply with `orders:Missing(remote)`, max 10 per message, jittered + suppressed like SNAP).
- `Sync.New(env)` gains `env.orders`; `sync:BroadcastOrder(order)`.

- [ ] **Step 1:** Extend the fake-network tests: order created on A reaches all 10 peers within one `ORDER` broadcast; a peer that was offline receives it via HELLO→OPUSH; 300-peer HELLO storm still produces ≤ 2 OPUSH per missing order (RF3); malformed `ORDER` dropped (RF5); a forged `ORDER` where `claims[X]` newer is accepted (trust model: guild is trusted; documented), but invalid shape is not.
- [ ] **Step 2-4:** FAIL → implement → PASS.
- [ ] **Step 5 – USER GATE (2 characters):** `/ts order test` creates an order on A; B (after `/reload`) shows it in `TalentShareDB.orders`; B runs `/ts order claim <id>`; A sees the claim; B logs out and back in after A closes the order → B converges to `done`.
- [ ] **Step 6:** Commit.

---

## Phase 4 – UI

UI conventions: one window `TalentShareFrame` (BasicFrameTemplate, movable, closes with Esc via `UISpecialFrames`), 3 tabs (Recipes, Orders, Guild), content scroll lists built with a simple pooled-row scroll frame (`ns.UI.ScrollList`). No protected templates. All text via a single `ns.L` table to ease later localisation. UI tasks are verified by the user in-game plus a **debug view-model layer**: each UI module exposes a pure function (e.g. `RecipeList.BuildRows(state) -> rows`) that is unit-tested offline; frame code is kept thin.

### Task 14: Window shell, slash, minimap button

**Size:** M · **Agent:** Implementer · **Depends on:** T8

**Files:** Create `UI/Window.lua`, `UI/Widgets.lua` (`ns.UI.ScrollList`, `ns.UI.Dropdown`, `ns.UI.EditBox`), `tests/test_widgets.lua` (pure row-windowing math only); modify TOC.

**Interfaces:**
- Produces: `ns.UI.Toggle()`, `ns.UI.Show()`, `ns.UI.SelectTab(name: "recipes"|"orders"|"guild")`, `ns.UI.RegisterTab(name, label, buildFn, refreshFn)`; Show fires internal `WINDOW_OPENED` (triggers a sync Hello, requirement 3). `/ts` with no args toggles the window; minimap button (draggable, position saved in `TalentShareDB.ui`); window position/size persisted.

- [ ] **Step 1:** Offline test for the scroll windowing math: given 1000 rows, row height 20, viewport 300 → visible index range for offsets 0, 500, end.
- [ ] **Step 2-4:** FAIL → implement → PASS.
- [ ] **Step 5 – USER GATE checklist:** `/ts` opens/closes window; Esc closes; drag works and position survives `/reload`; minimap button toggles; opening the window produces a `WINDOW_OPENED` + `HELLO` log entry; no taint warnings ("action blocked") in combat or when opening other panels.
- [ ] **Step 6:** Commit.

### Task 15: Recipe browser (filter + search)

**Size:** L · **Agent:** Implementer · **Depends on:** T5, T14

**Files:** Create `UI/RecipeList.lua`, `tests/test_recipelist.lua`.

**Interfaces:**
- Consumes: `Store.ListChars/GetRecipe/Crafters`.
- Produces: `RecipeList.BuildRows(state: {profession: skillLineID|nil, text: string, onlyOnline: boolean?, canCraftMine: boolean?}, store) -> Row[]` where `Row = {recipeID, name, icon, profession, minSkill, crafterCount, crafters={fullName...}}` sorted by profession then name; text search is case-insensitive on recipe name **and** reagent names (keeps requirement 6 simple: one search box). Left column: profession dropdown (only professions someone in the guild has) + search box; list shows icon, name, `(n crafters)`.

- [ ] **Step 1:** Tests (fixture: 4 chars, 3 professions, 12 recipes): profession filter returns only that profession; text `"boar"` matches recipe name; text `"mageroyal"` matches via reagent; duplicates across characters collapse into one row with merged crafters; empty store → `{}`; profession with 0 known recipes not offered in the dropdown.
- [ ] **Step 2-4:** FAIL → implement `BuildRows` → PASS; then implement the frames using it.
- [ ] **Step 5 – USER GATE checklist:** list populated with own + synced guild recipes; dropdown filters; search narrows live without lag at ≥ 1000 rows; empty state text shown when no data.
- [ ] **Step 6:** Commit.

### Task 16: Recipe detail and reagents

**Size:** M · **Agent:** Implementer · **Depends on:** T15

**Files:** Create `UI/RecipeDetail.lua`, `tests/test_recipedetail.lua`.

**Design decision (reagents):** right panel shows, for the selected recipe: icon + name, min skill, produced item tooltip on hover, reagent rows `icon  name  need N  (you have M)` where *have* = `GetItemCount(itemID, true)` of the current character (bank included), coloured green if enough, red otherwise; a "Crafters" list (name, class colour, profession rank, `last seen` age from `rev`) with a **Whisper** button; a **Request this** button (opens the order dialog from T17; disabled until T17 lands).

**Interfaces:**
- Produces: `RecipeDetail.BuildModel(recipeID, store, haveFn) -> {recipe, reagents={ {itemID,name,count,have,enough} }, crafters={ {name,class,rank,max,ageSec} } }`; item names resolved via `C_Item.GetItemInfo` with async load (`GET_ITEM_INFO_RECEIVED` triggers refresh, placeholder `"item:<id>"` until then — must never error on nil).

- [ ] **Step 1:** Tests: `have`/`enough` math with fake `haveFn`; reagent whose item info is not cached yields placeholder name, not error; crafters sorted by rank desc then name; recipe unknown to catalog → model `nil`.
- [ ] **Step 2-4:** FAIL → implement → PASS.
- [ ] **Step 5 – USER GATE:** click several recipes: reagents correct vs. the real profession window; hover shows item tooltips; Whisper button opens a whisper to the crafter; stale data shows an age.
- [ ] **Step 6:** Commit.

### Task 17: Orders UI (the demand board)

**Size:** L · **Agent:** Implementer · **Depends on:** T13, T14, T16

**Files:** Create `UI/OrdersTab.lua`, `UI/OrderDialog.lua`, `tests/test_orderstab.lua`.

**Interfaces:**
- Consumes: `ns.Orders` (T12), `Sync:BroadcastOrder` (T13).
- Produces: `OrdersTab.BuildRows(orders, filter, me) -> Row[]` where `Row = {id, recipeName, qty, requester, status, claimers={names}, canClaim, canWithdraw, canClose, canCancel, ageSec}`; filters: *All / Open / Mine (requested by me) / I'm crafting / Can craft (I know the recipe)*. Buttons per row: **Claim** (only if I know the recipe), **Withdraw**, **Done**, **Cancel**. Status column colour-coded; claimers listed ("Amy, Joe"). `OrderDialog.Open(recipeID)` — qty (1-99) and note (≤ 80) → `Orders:Create` + broadcast. Rows for recipes unknown to the catalog show `Recipe #id`.

- [ ] **Step 1:** Tests: `canClaim` false for a recipe I don't know; requester sees Cancel but not Claim on own order unless they know the recipe; `Mine` filter; sort = open first, then claimed, then newest; closed orders hidden by default but shown with a "Show closed" flag.
- [ ] **Step 2-4:** FAIL → implement → PASS.
- [ ] **Step 5 – USER GATE (2 characters):** A requests 3× a recipe → appears on B's Orders tab within ~10 s; B (who knows it) claims → A sees "claimed by B"; second crafter C claims → both listed; B marks Done → everyone sees Done; A cancels another order → disappears from open list on all clients; `/reload` keeps everything.
- [ ] **Step 6:** Commit.

---

## Phase 5 – Release

### Task 18: Packaging and release

**Size:** M · **Agent:** Implementer · **Depends on:** T17 (a v0.1 manual package may be cut earlier from any green milestone)

**Files:** Create `.pkgmeta`, `.github/workflows/release.yml`, `tools/package.ps1`, `CHANGELOG.md`; modify `README.md`, TOC (`## X-Curse-Project-ID`).

- [ ] **Step 1 (manual release first):** `tools/package.ps1` zips only the addon (`TalentShare.toc`, `Core/`, `UI/`, `Libs/`, README) into `dist/TalentShare-<version>.zip` with a single top-level `TalentShare/` folder; excludes `tests/ dev/ eval/ docs/ tools/ .git*`. Verify with `Expand-Archive` into a temp folder: top-level has exactly `TalentShare/` and the TOC is at `TalentShare/TalentShare.toc`.
- [ ] **Step 2 – USER GATE:** unzip into `_forever_\Interface\AddOns` on a clean install (remove the junction first); log in; `/ts` works; two characters sync (this is the v0.1 manual release for the guild).
- [ ] **Step 3:** `.pkgmeta`: `package-as: TalentShare`, `ignore:` the same exclusion list. Libraries stay vendored (no `externals`).
- [ ] **Step 4:** User creates the CurseForge project (Author Dashboard → World of Warcraft → Addons), tells us the project ID; add `## X-Curse-Project-ID: <id>` to the TOC; user creates an API token at `wow.curseforge.com/account/api-tokens` and stores it as repo secret `CF_API_TOKEN` (verified in packager `release.sh`: `CF_API_KEY` is the deprecated fallback).
- [ ] **Step 5:** `.github/workflows/release.yml` as in the BigWigs docs (trigger on tag, `fetch-depth: 0`, `BigWigsMods/packager@v2`, env `CF_API_TOKEN`, `GITHUB_OAUTH`). Dry run locally first: `release.sh -d -z` and inspect the zip.
- [ ] **Step 6 – USER GATE:** push tag `v0.1.0`; verify the file appears on CurseForge **tagged with the Forever game version** (if it is tagged wrong or "Midnight", fix with the packager `-g` flag or manual upload and record the answer in `docs/api-findings.md`); install through the CurseForge app on a clean profile.
- [ ] **Step 7:** Commit and tag.

### Task 19: Soak and hardening

**Size:** M · **Agent:** Tester (runs) + Implementer (fixes) · **Depends on:** T18

- [ ] **Step 1 (offline):** add `tests/test_soak.lua`: 100 simulated peers × 40 simulated minutes of random logins/logouts, level-ups, order churn with 10% message loss → assertions: converged state, total messages per peer per minute ≤ 30, no instance exceeds the 10-burst/1-per-s budget, SavedVariable size after 7 days of orders churn < 2 MB (serialize and measure).
- [ ] **Step 2 (offline):** fuzz `Codec.Decode`/`Sync.OnMessage` with 10 000 random tables/strings → zero thrown errors (RF5).
- [ ] **Step 3 – USER GATE (real guild, 1 evening):** leave addon running; Tester reads `TalentShareDB.debug` + `/ts comm` stats: `dropped` stays low, no "AddonMessageThrottle" results, no disconnects, memory (`/dump GetAddOnMemoryUsage("TalentShare")`) stays < 10 MB with a full guild cache.
- [ ] **Step 4:** Fix findings; bump to `0.1.1`; release via T18 flow.

---

## Self-review

- **Requirements coverage:** 1 → T3/T6/T7; 2 → T5/T10/T11 (cache in SavedVariables, no backend); 3 → T8 (level-up/skill), T11/T14 (login + window-open Hello); 4 → T14/T15/T16; 5 → T12/T13/T17; 6 → T18 (manual zip first, then CurseForge). Filter-by-profession + search + reagents covered; more advanced filters deliberately omitted (keep simple).
- **Review Focus mapping:** RF1 → T11; RF2 → T7; RF3 → T10, T13, T19; RF4 → T12, T13; RF5 → T9, T10, T13, T19.
- **Interface consistency:** `CharRecord`/`CatalogEntry` defined in T5 and used by T6, T7, T10, T15, T16; `Order` defined in T12 and used by T13, T17; `Sync.New(env)` defined in T10 and extended (not renamed) in T13; `ns.Events.Fire("LOCAL_CHANGED"/"WINDOW_OPENED")` defined in T8 and consumed by T11, T14.
- **Known risks / decisions to revisit after T3:** (1) profession APIs on Forever may differ from retail – T6 is the only file that changes; (2) recipe IDs may be spell IDs vs. recipe IDs – adapter normalises; (3) if recipe reagents are not readable without the window open, T7 scans on window-open only (already designed that way); (4) per-snapshot size – if > 20 KB compressed, add per-profession SNAP splitting in T10 (tests already measure size in T9); (5) trust model: any guild member can forge any order action – acceptable for v1, documented in README.

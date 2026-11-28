# 028 Craft cooldowns grid: spec

- Status: done
- Created: 2026-11-24
- Target version: 1.4.0 unreleased (protocol 2.7 -> 2.8, schema 8 -> 9)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
A "Cooldowns" mode in the Misc Items (Sonstiges) dropdown shows every timegated craft in a grid of icons the size of an action button, with a cooldown sweep and a timer.
Clicking a tile whispers a crafter, and the whisper includes the craft's link.

## Requirements
- R1: The Misc Items mode dropdown gets a fifth entry "Cooldowns" (deDE "Abklingzeiten"); it shows a grid instead of the
  table. The mode is saved like the other modes.
- R2: The grid has one tile per timegated craft (a switch shows one tile per crafter instead) of Classic / Forever (data file, R3). Crafts with a shared cooldown are ONE
  tile: all transmutes are one "Transmute" tile.
- R3: The set of timegated crafts is a static data file (group key, profession, spell ids, optional item id for item
  cooldowns such as the Salt Shaker, icon, fallback duration). Ids and durations are marked unverified until the `/ps cd`
  probe confirms them in game.
- R4: The crafters of a tile are all guild members whose synced recipes contain any spell of the group (anyone who knows the
  recipe). A tile with no crafter is shown dimmed with the text "nobody" and cannot be clicked.
- R5: The owner's client reads its own cooldowns, but only from the game: `GetSpellCooldown` for a known spell of the group,
  `GetTradeSkillCooldown` while the profession window is open, and the item cooldown for item groups. It reads on login
  (after the first cooldown update), when a cooldown changes, when the profession window opens, and after a successful
  cast of a group spell. If the game returns nothing usable, the stored value stays and is updated on the next good
  reading. If a group spell is cast but no reading follows, the fallback duration is used and marked "estimated".
- R6: Ready times are stored in server time (`GetServerTime`). When the owner sends its record, it adds the send stamp
  `at` (its own server time at sending). The receiver works out the remaining time as `readyAt - at` and stores
  `localReadyAt = receiverNow + remaining`, so a clock difference between the two clients makes no difference.
- R7: Every crafter has one of these states: `ready`, `cooling` (with time left), `unknown` (knows the recipe, has no
  cooldown record yet) or `estimated`. Offline crafters are greyed out.
- R8: The tile shows the best crafter: a ready online crafter first, then the online crafter whose cooldown ends soonest,
  then offline crafters. The tile also shows:
  - a cooldown sweep with a timer text (`2d 4h`, `3h 12m`, `12:30`)
  - a badge with the number of crafters who are ready right now (`2/5`)
  - the profession-coloured border
- R9: Tooltip: the craft name, the profession, the result item, the reagents, and one line per crafter. Each crafter line
  shows the online dot, the name, the state with time left, the exact ready time, and "updated X ago". The tooltip ends
  with "Click: whisper <best> / Right-click: choose a crafter".
- R10: Left-click whispers the best online crafter. Right-click opens a menu with all crafters, offline ones disabled.
  The whisper box is pre-filled with the craft link through the existing `whisper()` + `Model.ChatText` path. You cannot
  whisper yourself, and clicking does nothing when no crafter is online, with a short note saying so.
- R11: Visual effects:
  - Cooling tiles have a desaturated icon with the sweep and edge.
  - When a tile becomes ready it plays the cooldown "bling" and a one-off shine, then shows a soft gold glow that
    pulses while it stays ready.
  - Hovering grows the icon slightly and highlights it.
  - The glow is a texture of this addon (not `ActionButton_ShowOverlayGlow`), so it does not depend on that API.
  - Unknown-state crafters show a small "?" corner.
  - All animations stop when the grid is hidden, and the timer text refreshes at most once per second.
- R12: Debug options (`/ps cd` in every build; the Dev tools menu in the dev build):
  - `/ps cd` prints, for each group: whether the spell is known, the raw `GetSpellCooldown` / `GetTradeSkillCooldown`
    / item cooldown values, the stored `readyAt`, server time and local time.
  - The dev menu can fill fake cooldown data with every state, including one peer whose clock is 2 h off and one
    offline peer.
  - The dev menu adds a fake crafter whose cooldown ends in 20 s (Triggers -> "A cooldown ends in 20 s"), so the change
    to ready can be watched. A fake member, not my own record: see Decisions.
  - The dev menu can clear the fake data.
- R13: Older peers (protocol < 2.8) ignore the new HELLO field and message types; the other records still sync.

## Non-goals
- Expansion cooldowns other than Classic / Forever (TBC, Wrath and so on).
- Reminders or toasts when one of my own cooldowns is ready (possible later).
- Reading other players' cooldowns without the addon, and claiming or reserving a cooldown.
- Crafting from the tile (it only whispers).

## Design
- `Core/Data/CraftCooldowns.lua` (new, pure):
  - Holds `GROUPS`, the ordered list of `{ key, professionKey, spells = {...}, itemID?, iconSpell, fallback = seconds }`.
  - Also `GroupOfSpell(spellID)` and the record functions `Sanitize`, `Get`, `Put` and
    `Update(myName, readings, serverNow)`.
  - `rev` only goes up when a `readyAt` moves by more than 60 s or a group is added or removed. This keeps reading jitter
    from causing resends.
  - Receiving works like this: `FromWire(record, receiverNow)` -> local `readyAt`.
- `Core/Data/Store.lua` (changed): `cds` table, schema 9 (additive migration), sanitize on load, roster pruning, `/ps clean`.
- `Core/Net/Sync.lua` (changed): `cooldownKind()` record kind (`crev`, `WANTC`, `CDS`). `myRecord` returns a copy with
  `at = GetServerTime()` (the send stamp is not part of the revision). `store` converts it with `FromWire`.
- `Core/Base/Init.lua`: `PROTOCOL_MINOR` 7 -> 8.
- `Core/Game/Api.lua` (changed): `Api.ReadCraftCooldowns()` returns known groups, readings
  `{ [groupKey] = { remaining = s, source = "spell"|"trade"|"item" } }` and the raw values per group (for `/ps cd`);
  `Api.OpenWindowCooldownRecipes()` lists every recipe with a cooldown in the open profession window (finds the real
  recipe ids); `Api.CraftLink(group)` builds the whisper link.
  - Unreadable groups are left out.
  - A start value of 0 is trusted only after the first `SPELL_UPDATE_COOLDOWN` since login.
  - A negative or impossible remaining time (more than 2x the fallback) is dropped.
- `Core/Game/Events.lua` (changed):
  - `PLAYER_LOGIN` arms the reading.
  - `SPELL_UPDATE_COOLDOWN` / `BAG_UPDATE_COOLDOWN` trigger a reading, debounced to 2 s.
  - `TRADE_SKILL_SHOW` / `TRADE_SKILL_UPDATE` and `UNIT_SPELLCAST_SUCCEEDED` (player, group spell) also trigger it; for
    a cast this also sets the estimated fallback.
  - `/ps cd` runs the probe.
- `Core/View/Model.lua` (changed): `BuildCooldownTiles(now, online)` -> tiles with crafters, state, best crafter,
  readyCount (pure, tested); `FormatCooldown(seconds)`.
- `UI/CooldownGrid.lua` (new): the tile pool and layout (36 px, as many per row as fit, re-flows on resize), and the
  `CooldownFrame` (`SetDrawEdge`, `SetDrawBling`). It also has the glow and shine, the hover scale, the tooltip, the
  click whisper and the right-click menu, plus one throttled ticker that runs only while the grid is shown.
- `UI/Window.lua` (changed): the mode entry, showing the grid in place of the table and hiding the table-only controls in
  this mode.
- `UI/DevProbe.lua` (changed): fake crafters in every state (`/psd fake cooldowns`), a fake cooldown ending in 20 s
  (`cdsoon`), the `/ps cd` probe (`cdprobe`); "Remove all fake data" also clears the `cds` table. In the dev build the
  grid counts these fake crafters as online.
- `Core/Debug/Diagnostics.lua` (changed): cooldown pulls and records in `/ps export`.
- Data shape:
  - Store: `cds[name] = { rev, cds = { [groupKey] = readyAt (local server time), est = { [groupKey] = true } }, seen }`.
  - Wire: `{ rev, at, cds = {...}, est = {...} }`.
- Pure logic: CraftCooldowns, Model. WoW calls only in Api.lua, Events.lua and the UI.

## Tasks
- [x] T1 (S): Data file with groups (transmute, mooncloth, salt shaker, any others found) + lookup. Verify: test_craft_cooldowns "groups well formed"
- [x] T2 (M): Record Sanitize/Update/Put + Store schema 9 + pruning/clean. Verify: test_craft_cooldowns sanitize/rev/migrate
- [x] T3 (M): Sync kind + send stamp + clock-offset conversion, protocol 2.8. Verify: two-peer sync test with a 2 h clock skew; old-peer test
- [x] T4 (M): Api.ReadCraftCooldowns + Events wiring + fallback on cast. Verify: fake-client API test (incl. start=0 before first update, negative remaining); test_load
- [x] T5 (M): Model tiles (crafters from recipes, states, best crafter, sort, badge, format). Verify: test_craft_cooldowns_model
- [x] T6 (L): UI/CooldownGrid + Window mode + tooltip + click/right-click whisper with link + effects. Verify: test_load (grid builds), in game
- [x] T7 (M): Debug options: `/ps cd` probe, fake data, 20 s self cooldown, clear. Verify: test_load; in game
- [x] T8 (S): Docs (README, CHANGELOG, protocol.md, status.md, doc.md, api-findings after the probe)

## Review Focus (failure modes a happy-path test would miss)
1. RF1: Peer sends `at` = 0, NaN, or far in the future, or `readyAt` 10 years ahead, or 500 groups, or an unknown group key
   -> the record is rejected or clamped, unknown groups are skipped, nothing crashes. Pinned by: T2, T3
2. RF2: After login `GetSpellCooldown` returns 0 before the cooldown data is loaded -> my stored "cooling" value must NOT
   flip to ready and be broadcast. Pinned by: T4
3. RF3: The two clocks differ by hours (R6) -> the receiver shows the same remaining time as the owner, within the transit
   delay. Pinned by: T3
4. RF4: A crafter unlearns the profession, or leaves the guild -> they disappear from the tile, and their stale cooldown
   record is pruned. Pinned by: T2, T5
5. RF5: The grid stays open for hours -> no OnUpdate runs while it is hidden, the timer text updates once per second, and
   no tiles are created again on refresh (pooling). Pinned by: T6

## Cross-cutting checklist (answer every line; "n/a: reason" is fine)
- [x] Protocol: minor 2.7 -> 2.8, additive (HELLO field `crev`, types `WANTC`/`CDS`; older peers ignore both).
- [x] Stored data: schema 8 -> 9, additive (new `cds` table); a version reset drops peers' cds records like access/rep.
- [x] Trust model: allow-list sanitize, group keys only from the data file, times clamped, a peer can only send its own
  record (engine rule); names escaped in the tooltip.
- [x] Localization: only group keys and numbers are stored or sent; craft and item names come from the viewer's client;
  the new UI strings go through `L` (enUS + deDE).
- [x] Load order: CraftCooldowns after Reputation and before Feedback/Sync; CooldownGrid before Window (TOC +
  tests/run.lua + the test_load list).
- [x] Packaging: new files under Core/ and UI/ (packaged); features/ stays ignored.
- [x] Tests: tests/test_craft_cooldowns.lua, tests/test_craft_cooldowns_model.lua; RF1-RF5.
- [x] Docs: README, CHANGELOG, docs/status.md, docs/protocol.md, docs/api-findings.md, doc.md.

## Decisions (user answers and design choices, newest last)
- 2026-11-24: Classic / Forever cooldowns only (user).
- 2026-11-24: One tile per craft (user). Claude's reading: the tile stands for the craft, shows the best crafter's timer,
  and lists every crafter in the tooltip / right-click menu.
- 2026-11-24: Transmutes with a shared cooldown are one tile (user).
- 2026-11-24: Cooldown logic is left to Claude (user: "the start can perhaps be read even when stopped; just update the time
  next time"). It reads the real cooldown from the game on every chance it gets, keeps the old value when the reading is
  unusable, and uses the fallback duration only after an observed cast (claude).
- 2026-11-24: Clock handling (user): the sender adds its own timestamp, and the receiver computes the difference. The base
  is `GetServerTime`, plus the `at` stamp for clients whose clocks still differ (claude).
- 2026-11-24: Crafters = anyone who knows the recipe; members without cooldown data show as `unknown` (user).
- 2026-11-24: Click whispers with the craft link (user).
- 2026-11-24: Visual effects as in R11 (user: "make it fancy, you decide").
- 2026-11-24: Tooltip contents as proposed (user).
- 2026-11-24: Tile size = action button size, 36 px (user).
- 2026-11-24: Debug options as in R12 (user).
- 2026-11-24: Own record kind, not part of the character record: cooldowns change daily, and the recipe record would
  otherwise be pulled again every time (claude).
- 2026-11-24: The user said "go ahead" without answering the tile question. Built as one tile per craft, with a switch
  "One tile per crafter" in the grid's toolbar, so both readings are available (claude).
- 2026-11-24: The 20 s debug cooldown goes on a fake member, not on my own record: my record is synced to the guild and
  is overwritten by the next real reading within seconds (claude).
- 2026-11-24: Crafters of an item group (Salt Shaker) are whoever's record lists it: holding the item is not a recipe, so
  the owner's client reports the group when the item is in its bags or bank (claude).
- 2026-11-24: A "ready" reading from a spell is believed only after the first `SPELL_UPDATE_COOLDOWN`, or 20 s after
  login. Readings that show a cooldown are always believed (RF2) (claude).
- 2026-11-24: The glow is a texture of this addon, not `ActionButton_ShowOverlayGlow`, so it works whether or not that
  API exists on Forever (claude).

## Open questions
- Spell ids and durations of the groups on Forever (Transmute shared cooldown; Arcanite length; Mooncloth; Salt Shaker item
  cooldown). Recipe ids in the store must be spell ids for R4 to work. (needs: game, `/ps cd`)
- Does `GetSpellCooldown` return the long tradeskill cooldown after a relog without opening the profession window? (needs: game)

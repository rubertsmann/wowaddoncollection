# 022 Misc items tab with keys: spec

- Status: verifying
- Created: 2026-11-23
- Target version: 1.2.0 (protocol 2.4, schema 6)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
The "Available" tab becomes **Misc Items** with a mode dropdown: **Recipe items** (today's board), **Keys** (which guild
members hold which dungeon key) and **Attunements** (which members can enter which raid), so a group knows whom to bring.

## Requirements
- R1: The tab is labelled "Misc Items" (deDE "Sonstiges"); a dropdown at the top switches between Recipe items, Keys and
  Attunements. The chosen mode is kept in the local UI settings. Recipe items behaves exactly as before (search, filter,
  dibs, hide, whisper).
- R2: Keys mode lists one row per key the guild knows of: key icon + name, the instance it opens, and the members who hold
  it. Search matches key, instance and member names. Click a row = holders with locations; icon click or "Whisper a
  holder" whispers the first other holder. No dibs on keys.
- R3: A key is recognised by the item class **Key (13)** or by a curated list (`Core/Data/Access.lua`) of door/entry
  items that are not class 13 (e.g. Seal of Ascension). A curated deny-list removes instance-only and one-time keys
  (Relic Coffer Key, Viewing Room Key, Gordok keys, Scarab Coffer keys). Bound and unbound keys both count.
- R4: Keys are read from the bags, the key ring (if the client has one) and the bank while it is open; the bank state is
  kept afterwards (same "readable locations only" rule as recipe items).
- R5: Attunements mode lists one row per attunement (Molten Core, Onyxia, Blackwing Lair, Naxxramas, Upper Blackrock
  Spire) with the members who have it and, per row, the members known NOT to have it. An attunement counts as held when
  any of its listed quest ids is completed or its item is held (data table in `Core/Data/Access.lua`).
- R6: Keys + attunements of a character form ONE "access" record authored only by that character, replaced as a whole by
  a newer `rev`. Only its revision rides in HELLO (`arev`); the record is pulled (`WANTA`/`ACCESS`) only when that
  revision is newer than the held one, so traffic happens once or twice per character life. Pulls of access records
  wait behind character/offers pulls (lowest priority).
- R7: Only item ids / attunement keys / booleans are stored and sent; names, icons and instance names are resolved on the
  viewer's client (instance names via the locale tables).
- R9: The Misc Items table works like the Recipes table: header with sortable columns, and every mode has its own
  column set, column choice ("Columns" menu) and sort, kept in the local UI settings.
- R8 (stretch, deferred): A small key/attunement icon on party and raid frames for members who hold an access entry relevant to
  the current group's target (first version: icon shown when the member holds ANY key; tooltip lists them). Off by
  default switchable in the options. Built last, may be cut.

## Non-goals
- Dibs or trading of keys; consumable openers (Skeleton Keys, Seaforium charges) and summon items (Mallet, Scepter,
  Brazier) are not part of this feature (a later mode can add them with the same record).
- Reading attunements of other players without their addon (no inspect).
- Exact attunement progress (quest step N of M); only held / not held.

## Design
- `Core/Data/Access.lua` (new, pure): `Access.KEYS` (itemID -> instance key), `Access.DENY` (itemID set),
  `Access.ATTUNEMENTS` (ordered list: key, instance, quest ids, item id), `Sanitize`, `Get`, `Put`, `Update(myName,
  scan, now)` (rev only bumps on a content change), `IsKey(itemID, classID)`, `ListKeys()`, `ListAttunements()`.
- `Core/Game/Api.lua` (changed): `Api.ScanAccess()` -> `{ keys = { [itemID] = true } | nil per readable location,
  att = { [attKey] = true|false } }`; key ring container if present (`KEYRING_CONTAINER`, -2), bank only while open;
  `Api.QuestDone(questID)` via `C_QuestLog.IsQuestFlaggedCompleted` / `IsQuestFlaggedCompleted`.
- `Core/Game/Events.lua` (changed): access scan on login, `BAG_UPDATE_DELAYED` (debounced, shared with the item scan),
  `QUEST_TURNED_IN`, bank open; `/ps access` prints what the scan sees (probe for the in-game check).
- `Core/Net/Sync.lua` (changed): `accessKind()` record kind (`arev`, `WANTA`, `ACCESS`), registered after offers.
- `Core/Data/Store.lua` (changed): `access` table, schema 6 (additive migration), sanitize on load, roster pruning and
  `/ps clean` include it.
- `Core/View/Model.lua` (changed): `BuildKeyRows`, `BuildAttunementRows` (pure, tested).
- `UI/Window.lua` (changed): tab key stays `available` internally (saved setting), label "Misc Items", mode dropdown
  and "Columns" checkbox menu (existing menu dropdown helper), one header + table list (`UI/Table.lua`) whose columns
  come from the shown mode.
- `Core/View/ColumnTable.lua` (new, pure): column table factory (columns, shown/hidden, sort, layout) taken out of
  `RecipeTable.lua`; `RecipeTable` keeps its API on top of it. `Core/View/MiscTables.lua` (new, pure): modes and one
  column table per mode. `UI/Table.lua`: header takes the column labels of the table it shows.
- `Core/Debug/Diagnostics.lua` (changed): access pulls and records in `/ps export`.
- `UI/GroupIcons.lua` (new, R8 only): non-secure textures anchored to party/raid unit frames.
- `Locales/enUS.lua`, `Locales/deDE.lua`: tab, mode, column and instance names.
- Data shape: `access[name] = { name, rev, keys = { [itemID] = { [loc] = true } }, att = { [attKey] = boolean } }`.
- Message shape: HELLO gains optional `arev`; new `WANTA {names, via?}`, `ACCESS {access}`. Additive: 2.3 peers ignore
  `arev` and drop the unknown types.

## Tasks
- [x] T1 (M): `Core/Data/Access.lua` data tables + Sanitize/Put/Update/List. Verify: `tests/test_access.lua`.
- [x] T2 (S): Store schema 6, `access` table, load sanitize, roster prune, clean. Verify: `test_access.lua`, `test_core.lua`.
- [x] T3 (M): Sync record kind `access`, protocol 2.4. Verify: `test_sync.lua` (two peers converge; forged author dropped).
- [x] T4 (M): `Api.ScanAccess`, `Api.QuestDone`, events, `/ps access`. Verify: `test_items_api.lua` with stubbed APIs; in game `/ps access`.
- [x] T5 (M): Model `BuildKeyRows` / `BuildAttunementRows`. Verify: `tests/test_access_model.lua`.
- [x] T6 (M): Window: rename tab, mode dropdown, Keys and Attunements views, locale strings. Verify: `test_load.lua`, `test_locale_files.lua`; in game screenshot.
- [ ] T7 (M, stretch, deferred): `UI/GroupIcons.lua` party/raid icon + option. Verify: in game in a group.
- [x] T9 (M): generic `ColumnTable`, `MiscTables` per-mode columns, header labels, columns menu. Verify: `tests/test_access_model.lua`, `test_recipe_table.lua`.
- [x] T8 (S): docs (doc.md, README, CHANGELOG, docs/protocol.md, docs/status.md).

## Review Focus (failure modes a happy-path test would miss)
1. RF1: peer sends an ACCESS record for another name, 10 000 keys, non-boolean att values, unknown attKey -> dropped whole. Pinned by: T1, T3.
2. RF2: bank closed -> bank keys kept from the last bank visit, not wiped; key ring API missing -> bags still scanned. Pinned by: T4.
3. RF3: quest API missing or item data not loaded yet (class unknown) -> no false "not attuned" flip that bumps rev every login (unknown != false). Pinned by: T1, T4.
4. RF4: 2.3 peer in the guild -> keeps syncing chars/offers/orders, never sees access. Pinned by: T3.
5. RF5: the recipe items mode still works unchanged after the rename (saved tab key "available"). Pinned by: T6, existing `test_offers_model.lua`.

## Cross-cutting checklist (answer every line; "n/a: reason" is fine)
- [x] Protocol: additive bump to 2.4 (`arev`, `WANTA`, `ACCESS`); old peers ignore them.
- [x] Stored data: `Store.SCHEMA` 5 -> 6, additive (new empty `access` table), schema 5 data kept.
- [x] Trust model: allow-list sanitize (item ids in range, known locations, attKeys from `Access.ATTUNEMENTS` only, booleans), author == sender; names escaped before display.
- [x] Localization: only ids/keys sent; instance and mode names through `addon.Text`; item names from the viewer's client.
- [x] Load order: `Core\Data\Access.lua` after `Offers.lua`; `Core\View\ColumnTable.lua` before and `Core\View\MiscTables.lua` after `RecipeTable.lua`, in both TOCs (and `tests/run.lua`).
- [x] Packaging: new files under existing folders, `tools/package.ps1` picks them up; `features/` stays ignored.
- [x] Tests: `tests/test_access.lua`, `tests/test_access_model.lua`; adversarial: RF1-RF3.
- [x] Docs: README, CHANGELOG, docs/protocol.md, docs/status.md, doc.md.

## Decisions (user answers and design choices, newest last)
- 2026-11-23: Third mode = **Attunements** (user). Vanilla raid entry (MC, BWL, Naxx) is quest-based, not an item.
- 2026-11-23: Keys mode shows **who holds** each key, no dibs; plus "maybe" a small icon on party/raid portraits (user) -> R8, stretch, last.
- 2026-11-23: Sync as an **own record, pulled on change** (user). Keys and attunements share one "access" record because both change rarely.
- 2026-11-23: "Known grouped flag": item class 13 = Key (`Enum.ItemClass.Key`) covers most door keys; non-class-13 entry items (Seal of Ascension 12344, Drakefire Amulet 16309) and instance-only keys are handled by curated lists. Item/quest ids from warcrafttavern.com keys guide + warcraft.wiki.gg attunement page + model knowledge; every id is confirmed in game via `/ps access` before `done`.
- 2026-11-23: deDE tab label "Sonstiges" (the German client otherwise shows English "Misc Items"); internal tab key stays `available` so saved settings keep working.

- 2026-11-23: User: "rework the table view to be more inline with the recipe but having for each type different columns which different column configurations - implement it." -> R9/T9: generic ColumnTable shared with the Recipes tab; per-mode settings keys.
- 2026-11-23: Keys and attunements ride on the existing debounced item scan (same bag events) plus `QUEST_TURNED_IN`; no own timer.
- 2026-11-23: R8 (portrait icon) deferred: Forever's party/raid frames are unknown and the result cannot be checked offline; build after the in-game check of the lists.
- 2026-11-23: "online first" in R2 dropped: the addon keeps no online state for members; names only.

## Open questions
- Does Forever have a key ring container, and is `C_QuestLog.IsQuestFlaggedCompleted` available? (needs: game, `/ps access`)
- Are Naxxramas / BWL already in Forever's content? Rows for missing content can be hidden later (needs: user)

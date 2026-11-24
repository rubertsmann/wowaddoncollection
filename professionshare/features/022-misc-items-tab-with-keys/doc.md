# Misc items tab with keys

Status: verifying (offline proven, in-game checks pending) | Since version: 1.2.0 (protocol 2.4, schema 6) | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
The former **Available** tab is now **Misc Items** ("Sonstiges" in German). A dropdown switches between three lists:
**Recipe items** (the recipe board with dibs, unchanged), **Keys** (which guild members hold which dungeon key) and
**Attunements** (who can enter Molten Core, Onyxia, Blackwing Lair, Naxxramas and Upper Blackrock Spire). Each list is a
table like the Recipes tab, with its own columns and sort.

## How to use
- Tab **Misc Items**: pick the mode in the dropdown at the top left; the search box works in every mode.
- **Columns** menu (top right): turn the optional columns of the shown mode on or off. Click a column title to sort; click
  again to flip the direction. Every mode remembers its own columns and sort.
- Keys: every key of the list (`Access.KEYS`) has a row, also with nobody holding it (greyed out, 0 holders); other
  class Key items appear once somebody holds them. Click a row to see holders and where they keep the key; click the icon (or "Whisper a holder") to whisper the
  first other holder with the key's link. `*` marks keys you hold.
- Attunements: click a row (or hover) to see who is attuned and who is known not to be. `*` marks raids you are attuned to.
- `/ps access` prints what the key and attunement scan sees; `/ps access scan` also stores it.

## How it works
- Data (SavedVariables, schema 6): `access[name] = { name, rev, keys = { [itemID] = { [loc] = true } }, att = { [attKey] = boolean } }`.
  UI settings: `ui.miscMode`, `ui.offerColumns/offerSort`, `ui.keyColumns/keySort`, `ui.attunementColumns/attunementSort`.
- Messages (protocol 2.4, additive): `HELLO.arev`, `WANTA`, `ACCESS` (see `docs/protocol.md` section 12). The record only
  changes when a key or attunement changes, so it travels once or twice per character; afterwards only `arev` does.
- Modules: `Core/Data/Access.lua` (key/attunement lists, record, validation), `Core/Game/Api.lua` (`Api.ScanAccess`,
  `Api.QuestDone`), `Core/Game/Events.lua` (scan with the debounced item scan, on quest turn-in, `/ps access`),
  `Core/Net/Sync.lua` (record kind `access`), `Core/View/Model.lua` (`BuildKeyRows`, `BuildAttunementRows`, `KeyContact`),
  `Core/View/ColumnTable.lua` (generic column table, also behind `RecipeTable`), `Core/View/MiscTables.lua` (modes and
  their columns), `UI/Window.lua` (tab), `UI/Table.lua` (header takes the mode's labels).
- A key is an item of class Key (13) or in the curated `Access.KEYS` (Seal of Ascension, Drakefire Amulet); `Access.DENY`
  drops keys that only matter inside one run. Bound keys count.
- Attunement: held when one of its quests is completed (`C_QuestLog.IsQuestFlaggedCompleted`) or its item is held
  (`C_Item.GetItemCount`, bank included); "not attuned" only when the quest API answered; otherwise unknown.

## Localization
Only item ids, location keys and attunement keys/booleans are stored and sent. Tab, mode, column and instance names
are English with German translations; item names follow the viewer's client.

## Limits and known issues
- Key ids come from web sources (Warcraft Tavern keys guide); all ten plus the Forever Dalaran sewer key (277507) were
  confirmed on Forever with the dev key probe (`/psd keyprobe`), and Forever has a key ring and the quest API. The
  attunement quest ids (warcraft.wiki.gg) are answered by the client but not yet seen "true" on any member.
- "Lagerschlüssel von Krol'Dok" (267089, Forever) is shown without an instance: what it opens is not known.
- The bank is "last seen": a key moved out of the bank stays listed there until the next bank visit.
- Members on 2.3 builds are not listed in Keys/Attunements until they update.
- No party/raid frame icon yet (deferred, see log).
- No online indicator: holders are listed by name only.

## Changelog line
- Misc Items tab (was Available): Recipe items, Keys and Attunements, each a table with its own columns.

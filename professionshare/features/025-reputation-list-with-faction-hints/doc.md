# Reputation list with faction hints

Status: built, verifying | Since version: 1.4.0 (unreleased) | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
The Misc Items tab has a fourth list, **Reputation**: every guild member's standing with the factions that matter in
Classic (Hydraxian Waterlords, Argent Dawn, Zandalar Tribe, Cenarion Circle, Brood of Nozdormu, Thorium Brotherhood,
Timbermaw Hold, Wintersaber Trainers, home cities, goblin towns, battleground factions). Hovering a row shows what each
standing of that faction unlocks, with the member's reached standings highlighted and the next unlock marked.

## How to use
- UI: Misc Items -> dropdown "Reputation". Click a column title to sort (Standing sorts by level, then progress).
  "All factions" dropdown: show one faction. Search box: every word must match faction, member or standing
  ("thorium honored"). Columns menu: show "Updated". Hover a row: hints. Click the icon or the member's name: whisper that member (own rows: the click selects).
  Select a row: the line under the list says what the member's next standing unlocks.
- Commands: `/ps rep` (what the scan sees: API, every listed faction with id, client name, standing; `?` = id unknown
  on this client), `/ps rep scan` (share my current standings now, also progress-only changes).

## How it works
- Data (SavedVariables): `rep[name] = { name, rev, f = { [factionID] = { s, v, m } } }` (schema 8).
- Messages: `HELLO.rrev`, `WANTR {names, via?}`, `REP {rep}` (protocol 2.6, docs/protocol.md section 14).
- Modules:
  - `Core/Data/FactionHints.lua`: STATIC data (tracked factions, ids, groups, icons, hints en/de, optional item ids),
    `CHECKED` date. Updated with the project skill `update-faction-hints`.
  - `Core/Data/Reputation.lua`: record validation, store, my record update (level at once, progress every 30 min).
  - `Core/Game/Api.lua`: `ScanReputation`, `FactionName`, `StandingLabel` (GetFactionInfoByID, C_Reputation fallback).
  - `Core/Game/Events.lua`: scan after `UPDATE_FACTION` (5 s debounce) and at login; held-back progress re-scanned.
  - `Core/Net/Sync.lua`: record kind `rep`.
  - `Core/View/Model.lua`: `BuildReputationRows`, `ReputationFactions`, `FactionHintLines`, shared `SearchWords` /
    `MatchesWords` (also used by the Recipes search).
  - `Core/View/MiscTables.lua`: mode `reputation` and its column table; `UI/Window.lua`: filter, rows, tooltip.

## Localization
Faction names and standing labels come from the viewer's client (fallback: English data name, addon translation of
the 8 standing labels). Hint texts are English and German in the data file (English for other languages). Only ids and
numbers travel.

## Limits and known issues
- Hints are hand-written static notes from warcraft.wiki.gg and are NOT verified against Forever; some are general
  ("more recipes with each level"). No item ids are shipped yet.
- A faction the character met that sits at exactly Neutral 0 under a collapsed header in the reputation window is not
  seen (the list only shows expanded headers); it appears once it gains any reputation or the header is expanded.
- Progress of a member who stops farming within 30 minutes of the last shared change is shared on the next scan
  (retry timer, `UPDATE_FACTION` or login).
- Members on 1.3.0 or older do not appear in the list.
- Factions only one side can earn carry `side` in the data and are not scanned on the other side (its client reports
  them as Hated 0 without the character having met them).

## Verification
See [verify.md](verify.md).

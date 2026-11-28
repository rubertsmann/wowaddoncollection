# 042 Companion nicknames: spec

- Status: done
- Created: 2026-11-27
- Target version: 0.12.0 (with 041, protocol 1.7, schema 3)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
A player can give each companion in the roster a nickname. The nickname is saved per companion and shown in place of the
species name, both locally and to guild members.

## Requirements
- R1: Each roster companion can carry an optional nickname, 1-24 characters (at most 96 bytes) of UTF-8 after cleaning
  (control characters and `|` removed, spaces collapsed and trimmed). A companion is named **once**: a second name
  is refused ("named"), and so is an empty one ("empty"). Dev: `/ggd caught unname` takes it away again for testing.
- R2: The nickname persists across `/reload`, relog and the load-time sanitizer (`sanitizeCompanion`). Release or death
  removes it with the companion. Switching the active companion keeps every nickname.
- R3: Wherever a companion is shown (minimal pet view, companion panel header, roster list, release confirm, chat lines
  for needs and training), the nickname is shown, falling back to the species name.
- R3a: In fights (team dialog, team carousel, arena replay, fight history), the nickname is shown, and hovering over it
  shows the original species name. The species name is looked up from the NPC id (the local collection first, then the
  sent `n`).
- R3b: Ids are the reference everywhere. A companion is identified by `uid` (own) or `npc` id (a peer's fighter), never
  by its nickname or name text. Selecting, releasing, team picks, fight ids, fight math and history keys use ids only.
  The nickname is display data.
- R4: Collection > Caught: when the selected roster companion has no nickname, a **Rename** button shows above
  **Make companion** (each button keeps its own slot). A click replaces it with an edit box plus a tick and a cross. The tick (or Enter) names the companion: chat
  line, views refreshed, published to the guild; a refusal shows its reason and the box stays open. The cross (or
  Escape) goes back to the button. Once named, the button is gone. The same once-only naming works by clicking the
  active companion's name in the companion view and with `/gg caught name <text>`.
- R5: Guild members see the nickname. It travels in the `caught.c` record section and in arena team fighters as the
  optional field `nk`. Receivers clean it like `n` and escape it before display. A peer without the field sees the
  species name as before.
- R6: Sorting the roster by name uses the shown name (nickname, else species).

- R7: Each companion caught from now on records when (`at`, server time) and where (`map`, the uiMapID from
  `C_Map.GetBestMapForUnit("player")`) it was caught. Only ids and numbers are stored; the zone name is resolved at
  display time through `C_Map.GetMapInfo(cm).name`, so it follows the client language. Companions caught before this
  (and restored ones) show "unknown" and do not use the species' first-seen time as a guess.
- R8: Hovering over my companion's name in the companion panel, a roster row, or a row of the team picker shows
  "Caught <date> in <zone>". The fight cards and the replay show the species on hover (fighters carry no uid, and the
  origin is never sent).

## Non-goals
- No profanity filter or moderation. The guild is the trust boundary, as for notes in ProfessionShare.
- No unique names. Two companions can share a nickname.
- Restore codes (040) do not carry the nickname.
- No renaming species in the collection (the catalogue stays species names).

## Design
- `Core/Minigames/AzeCaught.lua` (changed):
  - The companion's own data sits in one sub-table, `companion.info = { nick?, at?, map? }`, so the nickname lives next
    to the catch information.
  - `MAXIMUM_NICK_CHARACTERS = 24` and `MAXIMUM_NICK_BYTES = 96`.
  - New functions: `NormalizeNickname`, `CleanNickname`, `CleanInfo`, `ShownName`, `SpeciesName`, `HasNickname`,
    `SetNickname(uid, text)` (refusals `readonly`/`unknown`/`invalid`/`toolong`) and `CatchOrigin`.
  - `recordCatch` stamps `info.at`/`info.map` on the companion the catch created and reports `result.uid`.
  - `Throw` keeps `throw.map`.
  - `sanitizeCompanion` keeps `CleanInfo(info)`.
  - `BuildSection` and the section cleaner carry `nk`.
- `Core/Game/Api.lua` (changed): `Api.PlayerMapID()` and `Api.MapName(id)`, both through the existing `read` (pcall and
  the secret check).
- `Core/Game/Catcher.lua` (changed): passes `map = Api.PlayerMapID()` with the throw and trap targets. Adds
  `/gg caught name`, `Catcher.Rename`, and the shown name in the need/training/death chat lines.
- `Core/Minigames/Arena.lua` (changed): the fighter build at `:211` adds `nk`, and the fighter cleaner at `:258` cleans it.
- `Core/View/Model.lua` (changed): roster rows and companion rows show the shown name, and `nameKey` uses it.
- `UI/AzeCaughtPanel.lua`, `UI/PetView.lua`, `UI/TeamDialog.lua`, `UI/ArenaView.lua`, `Core/Game/Catcher.lua`
  (changed): about 15 display sites switch from `companion.n` / `fighter.n` to the shown name. These sites are listed
  in the grep for `\.n\b`. The rename edit box goes in AzeCaughtPanel.
- `Core/Game/Catcher.lua` (changed): `/gg caught name`.
- `Locales/deDE.lua`: new strings.
- Data shape change: optional `caught.roster[uid].info = { nick?, at?, map? }`, and history rows gain `mi/mk/ti/tk`.
  Additive, and schema stays 3 (an older build drops `info` on load and loses nothing else).
- Message shape change: optional `nk` in `caught.c` and in the arena team fighters. Additive, and protocol stays 1.7 if
  this ships together with 041 (1.7 is unreleased); otherwise 1.8.
- Pure logic lives in AzeCaught/Arena/Model. The edit box is the only client UI.

## Sweep: every place the species name `n` is copied, stored or shown (2026-11-27)
| Where | What it does with the name | Plan |
|---|---|---|
| `AzeCaught.lua:983` `freshCompanion` | copies `entry.n` into the companion | keep (species cache); add `info` |
| `AzeCaught.lua:1573` `sanitizeCompanion` | rebuilds the companion from the collection entry, so any field not copied is lost | copy `info` explicitly (RF3) |
| `AzeCaught.lua:1443` `BuildSection` `c.n` / cleaner `:1472` | the guild sees the active companion's species | add `nk`; keep `n` |
| `AzeCaught.lua:1067` roster sort | sorts by `n` | sort by shown name, ties by `uid` |
| `AzeCaught.lua:1722` / `:1746` restore code | carries the species name text | keep; no nickname or origin (non-goal) |
| `AzeCaught.lua:931` companion snapshot (`name = companion.n`) | used by chat/journal | add `nick` |
| `AzeCaught.lua:646`, `:1372`; `Arena.lua:136` Wallet notes | ledger note = name text | keep the species (a ledger line is history, and a later rename must not rewrite it) |
| Journal lines (`name = entry.n`) | diagnostics | keep the species; add `uid` where a companion is meant |
| `Arena.lua:211` fighter build / `:258` cleaner | sends the species `n` | add `nk`; fight math and ids untouched |
| `Arena.lua:1059` fight history `me`/`them` | stores baked name text | store `npc` + `nk` per side (T5b) |
| `Arena.lua:1220` / `:1225` dev dummy | `n .. " (Dummy)"` | show "(Dummy)" as a display suffix instead of baking it into the name |
| `Model.lua:150` guild companion rows | `companion = escape(c.n)` | nickname, species on hover |
| `Model.lua:213` roster rows | `name = entry.n` from the collection | shown name, `nameKey` from it |
| `Model.lua:188`, `:384` collection rows / NPC info | species catalogue | keep the species (non-goal) |
| `Catcher.lua:239`, `:853`, `:933`, `:980`, `:1252`, `:1491` | chat lines and dev output | shown name in player lines; dev output prints both |
| `UI/PetView.lua:323`, `UI/AzeCaughtPanel.lua:800`, `:814`, `:1199` | pet view, panel header, release confirm | shown name; header gets the rename click and the origin line |
| `UI/AzeCaughtPanel.lua:1330` | collection preview of a species | keep the species |
| `UI/TeamDialog.lua:59`, `:98`; `UI/ArenaView.lua:662`, `:921`, `:949`, `:1049` | fight UI | nickname + hover species (R3a) |
| `UI/RunnerView.lua:158`, `:256`; `Runner.lua:55-57`, `:121` | obstacle monsters (species from the collection and static fallbacks) | keep; these are monsters, not my companion |
| `Locales/deDE.lua` `{name}` strings | templates | unchanged keys; new strings for rename/origin |
| `tests/*` fixtures with `n = ...` | test data | extend; no rename needed |

Not found: no static data files, saved lookup tables or helpers keyed by the companion name. Every lookup already goes
through `uid` / `npc`. The only name-keyed logic is the roster sort.

## Tasks
- [x] T1 (S): `SetNickname`, `ShownName`, the cleaning rules, and `sanitizeCompanion` keeping `nick`. Verify: `tests/test_nickname.lua` (set, clear, too long, UTF-8 cut, `|c`/`|T` escapes, control characters, unknown uid, survives sanitize, gone after release).
- [x] T2 (S): Model rows and sorting use the shown name. Verify: test_nickname (roster row name, sort order).
- [x] T3 (M): local display sites (pet view, panel header, roster, release confirm, chat lines). Verify: read-only grep of no remaining raw `companion.n` display, plus in-game screenshot.
- [x] T4 (M): rename UI (click the name, edit box, Enter/Escape, focus released on hide) and `/gg caught name`. Verify: in-game.
- [x] T5 (M): `nk` in `caught.c` and arena fighters; cleaners; TeamDialog/ArenaView show it. Verify: test_nickname (round trip through BuildSection -> cleaner, garbage `nk` dropped without dropping the section), `docs/protocol.md` updated; MULTI-CLIENT check.
- [x] T5b (S): fight history stores `npc` ids plus `nk` per side instead of the baked name text (`Arena.lua:1059`, `me`/`them`), and the history row resolves species from the id with the nickname shown and the species on hover; old history rows with `me`/`them` text still render. Verify: test_nickname (history row built from ids; old row compatible).
- [x] T5c (S): catch origin: stamp `info.at`/`info.map` on the companion `Reconcile` creates for a catch (`recordCatch`, `AzeCaught.lua:632`); map id through `Api` (new `Api.PlayerMapID()`, nil-safe when `C_Map` is missing); sanitize both (integer ranges). Verify: test_nickname (stamped on catch, nil map tolerated, kept through sanitize, old companions have none) + IN-GAME (a catch while in combat reports no blocked call).
- [x] T5d (S): show origin: panel line "Caught <date> in <zone>", tooltip in the roster/pet view/fight hover; zone name resolved at display, "unknown" fallback. Verify: in-game screenshot.
- [x] T4b (S): Collection > Caught Rename button and editor (`Panel.RefreshRosterRename`, `StartRosterRename`, `ConfirmRosterRename`, `CancelRosterRename`); `AzeCaught.CanRename`/`ClearNickname`; `/ggd caught unname`. Verify: test_nickname ("only once", "dev clear") + in-game.
- [x] T6 (S): deDE strings, README, CHANGELOG, doc.md.

## Review Focus (failure modes a happy-path test would miss)
1. RF1: a peer sends `nk` with `|T...|t` / `|H` links or 500 bytes -> it is cleaned and cut, or dropped, and the rest of the section survives. Pinned by: T5.
2. RF2: a nickname cut in the middle of a multibyte character -> the cut is UTF-8 safe (`TruncateUtf8`). Pinned by: T1.
3. RF3: the load-time sanitizer (the 040 data-loss path) rebuilds companions from the collection entry -> `nick` must be carried over explicitly, or every nickname silently vanishes on reload. Pinned by: T1.
4. RF4: the edit box keeps keyboard focus after the panel closes (the player can't move) -> `ClearFocus` on hide/Escape. Pinned by: T4.
7. RF7: `C_Map.GetBestMapForUnit` returns nil (in an instance, during a loading screen, or the API is missing in this client) or `GetMapInfo` has no name -> the catch still succeeds and the origin shows "unknown zone". Pinned by: T5c.
8. RF8: the catch happens in combat (it always does) -> the map call must not be blocked in combat, as the range check was in 039. Pinned by: T5c in-game.
6. RF6: two companions with the same nickname (or a nickname equal to another species name) in one team or roster -> picks, release and select still act on the right one (by `uid`). Pinned by: T1/T5.
5. RF5: an arena fight between a 1.7 peer with nicknames and one without them computes the same fight (`nk` is display only, never in the fight math or the fight id). Pinned by: T5.

## Cross-cutting checklist (answer every line; "n/a: reason" is fine)
- [x] Protocol: additive `nk` in `caught.c` and fighters; stays 1.7 (ships with 041). Old peers drop the unknown field and show the species. docs/protocol.md has a section.
- [x] Stored data: schema stays 3 (optional `info = { nick?, at?, map? }`, history `mi/mk/ti/tk`). Downgrading to 0.11.x drops `info` (sanitizer allow-list) without other loss.
- [x] Trust model: peer `nk` goes through `CleanNickname` (CleanString 96 bytes, no `|`, normalized, at most 24 characters); display through `Utility.Escape` / `ChatSafe`.
- [x] Localization: the nickname is user text and is not translated. Only the map id is stored, and the zone name comes from the client at display time. 9 new strings in deDE, including the date format.
- [x] Load order: n/a, no new file. TeamDialog and ArenaView call `addon.AzeCaughtPanel` / `addon.TeamDialog` at run time only.
- [x] Packaging: n/a, no new top-level paths.
- [x] Tests: `tests/test_nickname.lua` (picked up by the `tests/test_*.lua` listing) with 17 tests, plus a history assertion in `test_arena.lua`.
- [x] Docs: README, CHANGELOG, docs/protocol.md, doc.md.

## Decisions (user answers and design choices, newest last)
- 2026-11-27: the nickname is stored per roster companion (`uid`), not per species, because 037 made every catch its own companion.
- 2026-11-27 (user): fights show the nickname, and hovering shows the original pet name. Ids (`uid`, `npc`) are always the reference point; names are display only. This answers "guild-visible": yes, R5/T5 stay.

- 2026-11-27 (user): add where and when the pet was caught. Stored as ids/numbers only (`info.at` time, `info.map` uiMapID); the zone name is resolved at display time.

- 2026-11-27 (user): the catch origin is only for me (not sent); ship with 041 in 0.12.0 (protocol stays 1.7); max 24 characters for now.
- 2026-11-27 (user): "datawise the nickname should be close to the actual caught information": one `info` sub-table per companion holds `nick`, `at`, `map`.
- 2026-11-27: the origin is shown in tooltips (name hover, roster rows, team picker rows), not as a new panel line. The companion view has no free line between the model and the heart row.
- 2026-11-27: the dev dummy's fighters get the nickname "Dummy 1..3" instead of " (Dummy)" appended to the species name.
- 2026-11-27 (user): a Rename button in Collection > Caught for the selected companion, shown only while it has no nickname (naming happens once). It is replaced by a text box with a tick and a cross; the tick renames and sets everything up. The once-only rule lives in `AzeCaught.SetNickname` (refusals "named", "empty"), so the name click and the slash command follow it too.

## Open questions
- none

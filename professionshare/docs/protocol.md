# Wire protocol, compatibility and stored data

Applies from 0.3.0 (protocol 2.0, schema 2); 0.4.0 adds protocol 2.1 and schema 3 (sections 6 and 7); 0.4.1 adds protocol 2.2 (section 8); 0.6.0 adds 2.3 and schema 4 (section 9); 0.7.0 removes the games again (schema 5, section 9) and runs the transport and the pull engine on the embedded LibGuildSync-1.0 with the wire unchanged (feature 015). Source of truth in code: `Core/Base/Init.lua` (versions), `Core/Net/Codec.lua`
(format), `Core/Net/Guard.lua` (gate), `Core/Net/Communication.lua` (transport), `Core/Net/Sync.lua` (messages), `Core/Data/Store.lua` (schema).
Tests: `tests/test_hardening.lua`.

## 1. Transport
- Addon-message prefix `PShare` (dev build `PShareDev`), channels `GUILD` and `WHISPER` only.
- One logical message = `Codec.Encode(msg)`: serialize (own serializer, no `loadstring`) -> `CompressDeflate` ->
  `EncodeForWoWAddonChannel`, then cut into chunks of `Codec.CHUNK` (225) bytes. At most `Codec.MAX_PARTS` (200) chunks;
  `Codec.MAX_ENCODED = CHUNK * MAX_PARTS` is the only size limit (sender and receiver share it).
- Chunk layout (plain text, so any version can read the version **before** buffering or inflating):

```
<major>.<minor>|<id>|<idx>|<total>|<part>        e.g.  2.0|1234a|1|3|...
```
  `id` = 4 hex digits of a random per-session salt + a counter (so `/reload` cannot reuse an id while a stale buffer exists),
  at most 12 hex digits. Pacing: token bucket (burst 5, 0.9 per second).
- 0.1/0.2 builds sent `<id>|<idx>|<total>|<part>` (no version). 0.3+ recognises that layout as "older client".

## 2. Compatibility rules
| Peer vs. me | Result |
|---|---|
| same major, same or older minor | processed |
| same major, **newer minor** | processed; one notice "newer version with extra features" |
| **newer major** | dropped before any buffer exists; one notice "newer version, cannot sync, update" |
| **older major** or legacy layout | dropped; one notice "older version cannot sync" |
| malformed header | silently ignored |

- **Major** (`addon.PROTOCOL_MAJOR`): any breaking change: chunk header, serializer, compression/encoding, meaning or required
  fields of an existing message. Peers with a different major never exchange data. Bump it deliberately and say so in the
  CHANGELOG.
- **Minor** (`addon.PROTOCOL_MINOR`): additive only: new optional fields, new message types. Receivers ignore unknown fields
  and unknown message types (already the behaviour: `Sync` drops unknown `t`, the sanitizers copy known fields only).
  Never remove, retype or repurpose a field inside a major.
- The payload also carries `v = major` (checked after decoding) so a header/payload mismatch is dropped.
- A notice is printed once per kind per session; the sender is recorded (bounded to `Guard.MAX_SEEN`) but never printed.
  `/ps comm` shows `protocol`, `rejected` and `incompatible peers`.
- Old clients cannot be told about newer ones (they cannot read the new header): the notice only works from 0.3.0 on.

## 3. Inbound gate (`Core/Net/Guard.lua`)
Run first in `Communication.OnAddonMessage`; nothing from outside the guild is parsed, buffered or answered.
- `GUILD`: accepted (the server delivers it only to guild members).
- `WHISPER`: accepted only if the sender is in the cached guild roster (`Communication.roster`, refreshed on every roster update).
  An empty/unknown roster rejects (fail closed); right after login early whispers may be dropped and are re-requested by the
  next HELLO.
- Any other channel: rejected.
- Trust model: guild members are trusted (they may create/claim/close any order); a member can only author their own
  character record. Not trusted: non-guild players, malformed data, and any peer text shown in the UI.

## 4. Input validation
Everything received (and everything loaded from SavedVariables) is rebuilt by allow-list copy:
`Store.SanitizeChar`, `Store.SanitizeCatalogEntry`, `Orders.Sanitize`. Rules: finite numbers only (parser rejects `inf`/`nan`),
integers within ranges, timestamps in `[0, now + 1 day]`, strings UTF-8 + length-bounded + no control characters, names
without `|`, `icon` = numeric file id or plain path. A SNAP may only carry catalog entries for recipes the sender knows.
Display: every peer-originated string leaves `Core/View/Model.lua` escaped (`|` -> `||`).

## 5. Stored data (SavedVariables `ProfessionShareDB`)
`Store.SCHEMA`:
| Schema | Build | Notes |
|---|---|---|
| 1 | 0.1.0, 0.2.0 | records stored as received |
| 2 | 0.3.0 | all persisted peer data re-validated on load; invalid entries dropped |
| 3 | 0.4.0 | + `offers`, `hidden` (section 7) |
| 4 | 0.6.0 | + `games` (section 9) |
| 5 | 0.7.0 | - `games` and the games UI settings (moved to GuildGames, feature 015) |

- Migrations run stepwise in `Store.Migrate` (`MIGRATIONS[n]` = n -> n+1). Peer-derived caches (`chars`, `catalog`) are
  re-fetchable, so a migration may drop them; `orders` and the viewer's own record deserve care.
- **Downgrade guard:** if the saved `schema` is newer than this build, the file is **not touched**: `Store.Init` returns the
  original table (so the game writes it back unchanged), the session runs on a throwaway database (`readonly`), and the
  user gets one notice. A non-table or corrupt marker starts an empty database.
- Rules for changes: changing the stored shape -> bump `Store.SCHEMA` and add a migration + test; changing the wire ->
  decide major/minor first and write it in the feature's `spec.md` Decisions.

## 6. Recipe items board (protocol 2.1, schema 3; feature 007)
Additive minor change: a 2.0 peer ignores everything below (unknown HELLO field and unknown message types are dropped).
- `HELLO` gets optional `orev` = `rev` of my offers record (omitted when I have none). A receiver holding an older (or no)
  record of the sender whispers `WANTO {names={sender}}` (once per sender+rev per minute); only the sender's own name is honoured.
- `OFFERS {offers = rec}` (whisper): `rec = { name, rev, items = { [itemID] = { [loc] = count } }, dibs = { ["Owner-Realm:itemID"] = { on, t } } }`.
  `loc` is one of `bag bank reagent mail auction gbank1..gbank8`. The author is the only writer (`rec.name` must equal the
  sender), so a dib can only be set or removed by the dibbing player; a newer `rev` replaces the whole record.
- `Offers.Sanitize` (allow-list, one bad entry rejects the record): <= 300 items, <= 200 dibs, counts 1..9999, `rev`/`t` in
  `[0, now + 1 day]`, dib keys parse to a safe owner name + item id, no dib on the author's own items.
- Display safety: item names/icons/profession come from the viewer's client (`C_Item.GetItemInfoInstant`: only class Recipe is shown);
  owner and dibber names are escaped in `Core/View/Model.lua`.

## 7. Stored data additions (schema 3)
`offers[name]` (records above), `hidden["Owner:itemID"] = ownerRev` (local removal; void once the owner's `rev` changes).
Migration 2 -> 3 only creates the two tables. Both are re-validated on every load; `/ps clean` empties them in place.

## 8. Canonical names, pull retry over GUILD, order name snapshot (protocol 2.2; feature 008)
Additive minor change: a 2.1 peer ignores the new fields and keeps working as before.
- **Names (local, no wire change):** every player name from the wire, the roster and the client is compared and stored as
  `Utility.CanonicalName(name)`: any spelling of MY realm (case, spaces, apostrophes, hyphens; plus spellings learned from the roster's
  entry for my own character and from the sender of my own GUILD echo) becomes `Name-<GetNormalizedRealmName>`; other
  realms keep their suffix without spaces. Stored keys are rewritten on login and whenever a new spelling is learned
  (`Store.Recanon`). `WANT`/`WANTO` names, `SNAP`/`OFFERS` record names and order names are compared in canonical form.
- **`WANT`/`WANTO` field `via = "GUILD"`:** the first pull is a whisper. Without the record after 45 s it is repeated on
  GUILD with `via = "GUILD"` (again after 90 s), then given up until the peer's next HELLO (at least 60 s later, as in 0.4.0). The owner answers
  a `via = "GUILD"` request with `SNAP`/`OFFERS` on GUILD, at most once per rev per 60 s; every member that was behind takes
  it. A 2.1 owner ignores `via` and whispers as before. Members ignore GUILD requests for other names.
- **Order fields `name`, `loc` (optional):** the recipe name as the requester saw it (UTF-8, <= 100 bytes, no `|`) and its
  language code. Shown when the viewer has no catalog entry for the recipe; a copy without the name is completed by `Merge`.
- **Anti-entropy:** every client sends a HELLO every 15 minutes.
- **Forever surnames:** a player's name is "First Surname-Realm" (see docs/api-findings.md). `WANT`/`WANTO` names carry the
  full name plus the first-name form a 0.4.0 client uses for itself (`Util.LegacyName`, omitted when two members share the
  first name), so 0.4.0 members answer; their records ("First-Realm") are mapped to the full name by `Utility.CanonicalName`.
  Verified offline against the real 0.4.0 code (git 7c0a09b): records flow in both directions.

## 9. Guild games: coin flip results (protocol 2.3, schema 4; feature 014). Moved to GuildGames in 0.7.0
From 0.7.0 (feature 015) ProfessionShare neither sends `grev` nor handles `WANTG`/`GAMES` (a 0.6.0 peer's are dropped as unknown
types, its `grev` is ignored), and schema 5 deletes `games` plus the games UI settings (fresh start, nothing imported).
The games live in the GuildGames addon (prefix `GGames`, protocol 1.0, same record shape; its `docs/protocol.md`). The
rest of this section documents 0.6.0.
Additive minor change: a 2.2 peer ignores `grev` and drops `WANTG`/`GAMES` as unknown types, so everything else keeps syncing.
- **Record** (`Core/Play/Games.lua`), one per character, authored only by that character, replaced as a whole by a newer `rev`:
  `{ name, rev, total = {won, lost, wins, losses}, weeks = { ["YYYY-Www"] = {won, lost, wins, losses} } (<= 4 keys),
  recent = { {c = stake, r = "W"|"L", t = time} } (<= 20, newest first) }`. Amounts are in **copper** (1g = 10 000c),
  bookkeeping only (no real gold is read or moved). Week keys are ISO 8601 weeks in UTC.
- **Slot machine section (optional) `slots = { total, weeks, recent }`:** same shape and limits as the coin section, but
  recent entries are `{c = stake, n = net, t}` with `n = -c` (a loss) or `c <= n <= c * 374` (a win; 5 paylines x 75 is the
  highest multiplier). Win totals may reach `wins * 1e9 * 374`. Every game has its own section and its own leaderboard;
  a client that does not know a section drops it (allow-list copy).
- **`HELLO` field `grev` (optional):** my record's `rev` when I have one. Pulled exactly like `orev`: `WANTG {names, via?}`
  (whisper first, then GUILD with `via = "GUILD"` after 45/90 s), answered with `GAMES {games}`.
- **Validation (whole record rejected on one bad entry):** safe name equal to the sender (canonical form); `rev` in
  `[0, now + 1 day]`; totals integers with `won, lost <= 2e13` copper, `wins, losses <= 1 000 000` and consistent
  (`wins <= won <= wins * 1e9`, same for losses); week keys `YYYY-Www` with year 2020..2100, week 1..53, not after the week
  of `now + 1 day`; `recent` a dense array of at most 20 flips with `c` in 1..1e9 (1c to 100 000g), `r` "W"/"L", `t` in `[0, now + 1 day]`.
  Results are self-reported (trust model): bounds and consistency are checked, truth is not.
- **Announce:** a flip sends a coalesced HELLO (at once when the last one is 30 s old, else one when the 30 s are over).
- **Stored data (schema 4):** `games[name]`. Migration 3 -> 4 only creates the table; it is re-validated on every load,
  emptied by `/ps clean`, pruned with players who left the guild, and peer records are dropped by the version-change reset.
- **Display:** names are escaped in `Core/View/Model.lua`. Dev-build simulated players (`/psd game sim`) live outside the
  database and are never sent.

## 10. Version source
One source: the TOC `## Version` (`Core/Base/Init.lua` reads it from addon metadata; a literal fallback exists for the offline
tests and is pinned to the TOC by a test). The release workflow refuses a tag that does not match the TOC version.

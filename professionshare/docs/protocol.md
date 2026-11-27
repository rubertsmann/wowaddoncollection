# Wire protocol, compatibility and stored data

Applies from 0.3.0 (protocol 2.0, schema 2); 0.4.0 adds protocol 2.1 and schema 3 (sections 6 and 7); 0.4.1 adds protocol 2.2 (section 8); 0.6.0 adds 2.3 and schema 4 (section 9); 0.7.0 removes the games again (schema 5, section 9); feature 022 adds protocol 2.4 and schema 6 (section 12) and runs the transport and the pull engine on the embedded LibGuildSync-1.0 with the wire unchanged (feature 015). Source of truth in code: `Core/Base/Init.lua` (versions), `Core/Net/Codec.lua`
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
| 6 | 1.2.0 | + `access` (dungeon keys and raid attunements, section 12) |
| 7 | 1.3.0 | + `feedback`, `feedbackState`, `feedbackDelivered` (section 13) |
| 8 | 1.4.0 | + `rep` (faction standings, section 14) |

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

## 11. Build tag in HELLO (1.0.1, LibGuildSync MINOR 3, protocol stays 2.3)
- **`HELLO` field `ver` (optional):** `"<addon version>/<active LibGuildSync MINOR>"`, e.g. `"1.0.1/3"`. Added by
  LibGuildSync's Channel to every HELLO of every addon that embeds it. Older 2.x clients ignore the field.
- Why: the chunk header carries only the protocol version. A fix that changes no message (the realm-free name fix)
  looks the same from both builds, so without `ver` no log can say which build a member ran.
- Receiver: kept per sender for the session (at most 200), only when it is a short plain string (`[%w.-+/_]`, 32 bytes);
  noted in the HELLO's trace line (`ver=1.0.1/3`, `ver=-` from builds before the field) and listed by `/ps comm` and the
  export report ("member builds seen this session"). Never used for decisions, only for diagnosis.

## 12. Dungeon keys and raid attunements (protocol 2.4, schema 6; feature 022)
Additive minor change: a 2.3 peer ignores `arev` and drops `WANTA`/`ACCESS` as unknown message types.
- `HELLO` gets optional `arev` = `rev` of my access record (omitted when I have none). A receiver holding an older (or no)
  record of the sender whispers `WANTA {names={sender}}`; only the sender's own name is honoured. Same pull engine, retry
  over GUILD and dedup as `WANTO` (LibGuildSync record kind `access`, registered after `chars` and `offers`, so its pulls
  queue last).
- `ACCESS {access = rec}`: `rec = { name, rev, keys = { [itemID] = { [loc] = true } }, att = { [attKey] = boolean } }`.
  `loc` is one of `bag keyring bank`; `attKey` one of `mc ony bwl naxx ubrs` (`Core/Data/Access.lua` `ATTUNEMENTS`).
  `att[k] = false` means "known not attuned"; a missing `k` means "not known on the author's client". The author is the
  only writer (`rec.name` must equal the sender); a newer `rev` replaces the whole record.
- Traffic: the record changes when a key is looted or an attunement quest is handed in, so after the first exchange only
  the number `arev` rides in each HELLO.
- `Access.Sanitize` (allow-list, one bad entry rejects the record): <= 60 keys, item ids 1..2^31-1, location values must be
  `true`, attunement keys from the list only, values boolean, `rev` in `[0, now + 1 day]`.
- Display safety: key names, icons and classes come from the viewer's client; only ids this client takes for a key
  (class Key 13 or the curated `Access.KEYS`, minus `Access.DENY`) are shown. Holder names are escaped in `Core/View/Model.lua`.
- Stored: `access[name]` (schema 6, migration 5 -> 6 creates the table); re-validated on every load, dropped for members
  who left the guild, emptied by `/ps clean`, dropped for peers by the version reset like `offers`.

## 13. Feedback for the developer (protocol 2.5, schema 7; feature 024)
Additive minor change: a 2.4 peer ignores `frev` and drops `WANTF`/`FEEDBACK` as unknown message types.
- `HELLO` gets optional `frev` = `rev` of my feedback record (omitted when I have sent none). Only a **reader** pulls:
  the developer's client (`Feedback.IsReader`: `Model.IsBuildViewer` name hash) or a development build. Everyone else
  treats every announced `frev` as held (never sends `WANTF`) and never stores another member's record, even one that
  arrives on GUILD after a pull retry.
- `WANTF {names, via?}` / `FEEDBACK {feedback = rec}`: same engine as `WANTA`/`ACCESS` (record kind `feedback`,
  registered last). `rec = { name, rev, items = { { t, k, text, log? } } }`, oldest first. `t` = send time (unique in
  the record), `k` one of `feedback feature bug`, `text` <= 300 bytes UTF-8 without control characters, `log` (bug
  snapshot) <= 1200 bytes, lines joined by a line feed, at most 3 items with a `log`, at most 10 items.
- No relay: a message reaches the developer when the sender and the developer are online at the same time.
- Not a secret: the record is a normal addon message, readable by anyone's own code on the wire.
- Display safety: text and snapshot are escaped (`Utility.Escape`) in the list, tooltip, detail panel and export window.
- Stored: `feedback[name]` (only mine, except on a reader's client) and `feedbackState["name#t"] = declined|answered|fixed`
  (the reader's local status), `feedbackDelivered[t] = true` (sender only: my messages a reader has asked for, shown as
  "delivered"). Schema 7, migration 6 -> 7 creates the tables. Re-validated on every load; not dropped by
  the roster prune, the version reset or `/ps clean` (the developer keeps messages of members who left).

## 14. Faction standings (protocol 2.6, schema 8; feature 025)
Additive minor change: a 2.5 peer ignores `rrev` and drops `WANTR`/`REP` as unknown message types.
- `HELLO` gets optional `rrev` = `rev` of my reputation record (omitted when I have none). A receiver holding an older
  (or no) record whispers `WANTR {names={sender}}`; same engine, retries and dedup as `WANTA` (record kind `rep`,
  registered after `access`).
- `REP {rep = rec}`: `rec = { name, rev, f = { [factionID] = { s, v, m } } }`: `s` standing 1 Hated .. 8 Exalted, `v`
  progress inside the standing, `m` size of the standing (`0 <= v <= m <= 1 000 000`). Only factions of
  `Core/Data/FactionHints.lua` `FACTIONS` are sent; factions the author has not met are left out. The author is the only
  writer; a newer `rev` replaces the whole record.
- Traffic: a standing level change (or a newly met faction) bumps `rev` at once; a progress-only change at most every
  `Reputation.PROGRESS_INTERVAL` (30 min), so farming reputation does not make the guild re-pull the record per kill.
- `Reputation.Sanitize` (allow-list): <= 64 entries, faction ids 1..100000, integers in range, `v <= m`, `rev` in
  `[0, now + 1 day]`; a malformed entry rejects the record, a well-formed entry for a faction this build does not list
  is skipped (a newer build may track more factions).
- Display safety: faction names and standing labels come from the viewer's client (English data name / addon
  translation as fallback); owner names are escaped in `Core/View/Model.lua`. The hint texts are static data of the
  viewer's own build and never travel.
- Stored: `rep[name]` (schema 8, migration 7 -> 8 creates the table); re-validated on every load, dropped for members
  who left the guild, emptied by `/ps clean`, dropped for peers by the version reset like `access`.

## 15. Recipe drop alerts (protocol 2.7, schema unchanged; feature 027)
Additive minor change: a 2.6 peer drops `DROP`/`DROPA` as unknown message types. Nothing is stored (session memory;
switches in `ui.drops`).
- `DROP {item}` on GUILD: a tradeable recipe item (class Recipe, not bind on pickup, its tooltip names a profession
  requirement) from the sender's own loot line just reached the sender's bags. Sent once per loot line, only when the
  sender's `share` switch is on.
- Each receiver reads the item's tooltip on its own client (`Core/Data/RecipeCheck.lua`: the last "Requires
  <profession> (n)" line, "Already known") and compares with its own stored skill. Learnable -> `DROPA {item, s="g", r}`
  whispered to the sender and a local alert; skill too low -> `DROPA {s="r", r}`; known, other profession, unreadable,
  `share` off -> nothing. The same `DROP` from the same sender within 60 s is ignored.
- `DROPA {item, s, r}`: `item` 1..10 000 000, `s` "g" or "r", `r` 0..1000 (the answerer's current skill). Stored only
  for one of the receiver's own drops of the last 15 minutes (at most 20); anything else is ignored.
- Display safety: answerer names are escaped (tooltip) or made chat safe (chat lines); item names come from the
  viewer's own client.
- Traffic: one small GUILD message per looted recipe, one whisper per member who can use it or lacks only the skill.

## 16. Craft cooldowns (protocol 2.8, schema 9; feature 028)
Additive minor change: a 2.7 peer ignores `crev` and drops `WANTC`/`CDS` as unknown message types.
- `HELLO` gets optional `crev` = `rev` of my cooldown record (omitted when I have none). A receiver holding an older
  (or no) record whispers `WANTC {names={sender}}`; same engine, retries and dedup as `WANTR` (record kind `cds`,
  registered after `rep`).
- `CDS {cds = rec, at}`: `rec = { name, rev, c = { [groupKey] = readyAt }, e = { [groupKey] = true } }`. `groupKey` is a
  key of `Core/Data/CraftCooldowns.lua` `GROUPS` (`transmute`, `mooncloth`, `saltshaker`); `readyAt` is the author's
  server time when that cooldown ends, 0 = ready; `e` marks an estimate (a cast was seen, the game reported no
  cooldown). A group missing from `c` = the author cannot do it (or its cooldown was never read). `at` = the author's
  server time when the answer was built.
- Clock handling: the receiver keeps `readyAt - at` (time left) and stores `receiverNow + timeLeft`
  (`CraftCooldowns.FromWire`), so two clients whose clocks differ show the same time left (within the transit delay).
  A peer that sends no `at` is taken to share the receiver's clock.
- Traffic: `rev` changes only when a ready time moves by more than 60 s, a group appears or goes, or an estimate becomes
  a real reading; reading the same cooldown again does not resend the record.
- `CraftCooldowns.Sanitize` (allow-list): <= 16 entries, string keys <= 24 bytes, ready times integers in
  `[0, 2^31-1]`, `e` values `true` only, `rev` in `[0, now + 1 day]`; a malformed entry rejects the record, an unknown
  group key is skipped. `FromWire` drops a group with more than 8 days left.
- Display safety: craft names, icons and links come from the viewer's client; owner names are escaped in
  `Core/View/Model.lua`.
- Stored: `cds[name]` (schema 9, migration 8 -> 9 creates the table) in the receiver's clock, plus `seen` (receiver's
  time of arrival, local only, never sent); re-validated on every load, dropped for members who left the guild,
  emptied by `/ps clean`, dropped for peers by the version reset like `rep`.

## 17. Profession window spells in HELLO (protocol stays 2.8, schema unchanged; feature 005)
Diagnosis only, like `ver` (section 11): a 2.8 peer without it ignores the unknown HELLO field.
- **`HELLO` field `wsp` (optional):** `"skillLine:spellID,..."` sorted, at most 200 bytes, the spells that opened my
  profession windows (a `TRADE_SKILL_SHOW` within 2 s after my own `UNIT_SPELLCAST_SUCCEEDED`, the open window's skill
  line). At most 16 skill lines and 4 spells each. Omitted when I have noted none.
- Receiver: `ProfessionSpells.Decode` accepts only digits, `:` and `,`, ids 1..99 999 999; anything else is ignored with
  a trace note. Only the developer's client (`Feedback.IsReader`) keeps it: `windowSpellReports[skillLine][spellID] =
  { by = { [sender] = true } (<= 10), at }`, bounded to 64 skill lines and 16 spells each. Never used for decisions:
  `/ps spellids` compares it with the static `ProfessionSpells.WINDOW`, which is edited by hand.
- Stored: `windowSpells` (mine) and `windowSpellReports` (developer only), created empty by `withAllTables`, kept
  through `/ps clean` and the version reset.

## 18. Order chat and history (protocol 2.9, schema unchanged; feature 048)
Additive minor change: a 2.8 peer drops `OMSG` as an unknown message type, ignores `xdig`, and its `Orders.Sanitize`
(allow-list) drops the new order fields, so orders keep syncing between both versions.
- **Order fields (optional):** `msgs = { {b, t, x} }` chat messages (author, server time, text) and `ev = { {k, b, t} }`
  status changes (`k` one of `claim withdraw done cancel`), each oldest first. Merge = union, one entry per `b`+`t`
  (`k`+`b`+`t` for events), the newest 30 of each kept; ties sort by key and text, so every client keeps the same set.
  Validation: names safe, times in `[0, now + 1 day]`, text UTF-8 <= 160 bytes without control characters and not
  blank; a bad entry is dropped (never the whole order), a list longer than 120 is not read.
- **`Orders.Version` unchanged** (2.8 peers compute the same number). The chat and the history have their own number
  `ExtraVersion` = sum of the entry times.
- **`HELLO` field `xdig`:** `{ [orderID] = ExtraVersion }` for those of the newest 100 orders that have chat or events
  (always sent, `{}` when none). A receiver pushes (OPUSH) an order whose extra part the peer lacks only when the peer
  sent `xdig`; a 2.8 peer is never sent orders for their chat.
- **`OMSG {id, m = {b, t, x}}` on GUILD:** one new chat message. `m.b` must equal the sender (canonical form), else it is
  dropped; an unknown order id is ignored (the message arrives later with OPUSH).
- **`ORDER`** broadcasts carry `ev` but not `msgs` (chat travels as `OMSG` and with OPUSH). OPUSH batches are cut at 10
  orders or about 8000 estimated bytes, whichever comes first.
- **Catalog field `tools` (optional):** up to 4 tool or place names (<= 60 bytes, no `|`) a recipe needs, read from
  `GetTradeSkillTools` where the client has it. A 2.8 peer drops it.
- Trust: relayed chat (OPUSH) is trusted like claims (guild members are trusted); live messages only in the sender's
  name. Display: chat text and names are escaped (`Utility.Escape`); chat lines in the chat frame use `Utility.ChatSafe`.
- Local data: `ui.chatSeen[orderID] = time of the newest message read`, pruned with the orders.

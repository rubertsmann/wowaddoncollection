# Wire protocol, compatibility and stored data

Applies from 0.3.0 (protocol 2.0, schema 2). Source of truth in code: `Core/Init.lua` (versions), `Core/Codec.lua`
(format), `Core/Guard.lua` (gate), `Core/Comm.lua` (transport), `Core/Sync.lua` (messages), `Core/Store.lua` (schema).
Tests: `tests/test_hardening.lua`.

## 1. Transport
- Addon-message prefix `TShare` (dev build `TShareDev`), channels `GUILD` and `WHISPER` only.
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

- **Major** (`ns.PROTO_MAJOR`): any breaking change: chunk header, serializer, compression/encoding, meaning or required
  fields of an existing message. Peers with a different major never exchange data. Bump it deliberately and say so in the
  CHANGELOG.
- **Minor** (`ns.PROTO_MINOR`): additive only: new optional fields, new message types. Receivers ignore unknown fields
  and unknown message types (already the behaviour: `Sync` drops unknown `t`, the sanitizers copy known fields only).
  Never remove, retype or repurpose a field inside a major.
- The payload also carries `v = major` (checked after decoding) so a header/payload mismatch is dropped.
- A notice is printed once per kind per session; the sender is recorded (bounded to `Guard.MAX_SEEN`) but never printed.
  `/ts comm` shows `protocol`, `rejected` and `incompatible peers`.
- Old clients cannot be told about newer ones (they cannot read the new header): the notice only works from 0.3.0 on.

## 3. Inbound gate (`Core/Guard.lua`)
Run first in `Comm.OnAddonMessage`; nothing from outside the guild is parsed, buffered or answered.
- `GUILD`: accepted (the server delivers it only to guild members).
- `WHISPER`: accepted only if the sender is in the cached guild roster (`Comm.roster`, refreshed on every roster update).
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
Display: every peer-originated string leaves `Core/Model.lua` escaped (`|` -> `||`).

## 5. Stored data (SavedVariables `TalentShareDB`)
`Store.SCHEMA`:
| Schema | Build | Notes |
|---|---|---|
| 1 | 0.1.0, 0.2.0 | records stored as received |
| 2 | 0.3.0 | all persisted peer data re-validated on load; invalid entries dropped |

- Migrations run stepwise in `Store.Migrate` (`MIGRATIONS[n]` = n -> n+1). Peer-derived caches (`chars`, `catalog`) are
  re-fetchable, so a migration may drop them; `orders` and the viewer's own record deserve care.
- **Downgrade guard:** if the saved `schema` is newer than this build, the file is **not touched**: `Store.Init` returns the
  original table (so the game writes it back unchanged), the session runs on a throwaway database (`readonly`), and the
  user gets one notice. A non-table or corrupt marker starts an empty database.
- Rules for changes: changing the stored shape -> bump `Store.SCHEMA` and add a migration + test; changing the wire ->
  decide major/minor first and write it in the feature's `spec.md` Decisions.

## 6. Version source
One source: the TOC `## Version` (`Core/Init.lua` reads it from addon metadata; a literal fallback exists for the offline
tests and is pinned to the TOC by a test). The release workflow refuses a tag that does not match the TOC version.

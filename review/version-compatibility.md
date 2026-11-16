# Review: version compatibility and migration

Date: 2026-11-16 · Scope: wire protocol, SavedVariables schema, version constants · Status: **R1-R6 implemented in feature 004** (`features/004-hardening-and-version-compatibility/`, protocol 2.0, schema 2); the sections below describe the state BEFORE that change. Current rules: `docs/protocol.md`

## 1. What exists today

| Concern | Mechanism | Where |
|---|---|---|
| Wire compatibility | Every message carries `v = ns.PROTOCOL` (currently `1`); `Codec.Decode` drops any message whose `v` is not **exactly equal** to the local value. `Sync:OnMessage` re-checks. | `Core/Init.lua:4`, `Core/Codec.lua:98,115`, `Core/Sync.lua:50` |
| Unknown message types | Dropped (`self["_on"..msg.t]` is nil -> `stats.dropped`). Unknown extra fields are tolerated by the serializer. | `Core/Sync.lua:55-60` |
| Local data schema | `Store.SCHEMA = 1`; `Store.Init` only does `sv.schema = sv.schema or SCHEMA`. **No migration code, no downgrade check.** | `Core/Store.lua:10,14` |
| Addon version | Hard-coded `ns.VERSION = "0.1.0"` **and** `## Version: 0.1.0` in the TOC (package script reads the TOC). | `Core/Init.lua:3`, `TalentShare.toc` |
| Tests | One test: a message encoded at protocol 1 is rejected at protocol 2. | `tests/test_core.lua:61` |

**Answer to "do only compatible versions talk to each other?"** Yes, today: a peer on a different `PROTOCOL` is ignored in both directions, and the offline suite (26 tests) passes. The guarantee is crude, though, and there is **no migration story at all** for stored data. Details below.

## 2. Gaps

### V1. The version is inside the compressed payload (Medium)
`msg.v` is only readable after chunk reassembly, inflate and deserialize. Consequences:
- A future protocol that changes the codec, compression or serializer can no longer be decoded by old clients, so they fail as `inflate failed` / `bad token`, not `protocol version`. The mismatch is indistinguishable from corruption.
- Mismatched peers still cost buffer memory, inflate and parse time before being dropped.
- Neither side can tell the user "some guild members run a newer/older TalentShare".

### V2. Exact-equality means every bump splits the guild (Medium)
There is no notion of a compatible range. A purely additive change (new optional field, new message type) must bump `PROTOCOL` to be safe, and then old and new clients stop syncing entirely. Guilds update unevenly, so this is the common case.

### V3. Silent failure, no user feedback (Medium)
Mismatches only increment `stats.dropped` and write a debug-ring line. A user with an outdated addon sees an empty guild and no explanation. There is no "newer version seen" hint.

### V4. No SavedVariables migration or downgrade protection (High for the first schema change)
- `Store.Init` does not look at `sv.schema` except to default it. The first time the shape of `chars`, `catalog` or `orders` changes, old files load into new code unmigrated.
- A user who installs an **older** addon over a **newer** `TalentShareDB` has it silently used (and possibly rewritten with a lower `schema` semantic mismatch).
- Persisted peer data (`chars`, `catalog`, `orders`) carries no per-record format version, and is **not re-validated on load**; hand-edited or corrupted files go straight into the UI.

### V5. Three sources of truth for the version (Low)
TOC `## Version`, `ns.VERSION`, and the git tag can drift. `.pkgmeta`/packager can substitute `@project-version@`, but the code does not use it.

### V6. Message-id reuse across `/reload` (Low)
`Comm.msgCounter` restarts at 0 on every reload, and reassembly buffers are keyed `sender:id`. A sender who reloads (typical during an upgrade) can reuse an id while a stale partial buffer from the previous session still exists (60 s expiry) with the same `total`. The chunks mix and fail decode. This self-heals, but it is noisy exactly when versions change. Add a random per-session salt to the id.

### V7. Limits are not derived from each other (Low)
`MAX_ENCODED = 60000` in `Codec.Decode`, but the transport can never deliver more than `MAX_PARTS (200) x CHUNK (225) = 45000` bytes. Derive one from the other so a future change to either cannot silently open a gap.

### V8. Untested paths (Medium)
No tests for: Sync dropping a mismatched `v`; two clients on adjacent protocols; schema migration; opening a newer-schema DB with older code; a chunk header from an unknown protocol.

## 3. Recommendations

### R1. Put a protocol version in the chunk header (fixes V1, V3, V6)
Keep the existing prefix, and change the header from `id|idx|total|part` to `proto|session+id|idx|total|part` (or register a new prefix per major, e.g. `TShare1`). The header is plain text and can stay stable for all future versions, so any client can read a peer's protocol *before* buffering or inflating.
- Reject chunks with `proto ~= PROTO_MAJOR` immediately; do not allocate a buffer.
- Record `Comm.seenNewer = max(seenNewer, proto)` and show **one** chat line per session: "Guild members are using a newer TalentShare protocol - please update."
- Include a random 16-bit session salt in the message id.

### R2. Split into PROTO_MAJOR and PROTO_MINOR (fixes V2)
- `MAJOR`: breaking changes; must match exactly.
- `MINOR`: additive only (new optional fields, new message types). Peers with different minors interoperate; unknown types and fields are ignored (already the case).
- Document the rule in `docs/protocol.md` (does not exist yet): what counts as additive, and that removing or retyping a field is a major bump.

### R3. Add a real migration path to `Store.Init` (fixes V4)
```lua
local MIGRATIONS = {            -- [n] migrates schema n -> n+1
    -- [1] = function(sv) ... end,
}
function S.Migrate(sv)
    local v = sv.schema or 1
    if v > S.SCHEMA then return nil, "newer" end   -- caller: keep file untouched, run with an in-memory DB, warn the user
    while v < S.SCHEMA do (MIGRATIONS[v])(sv); v = v + 1; sv.schema = v end
    return sv
end
```
- On "newer": do **not** overwrite; work on a throwaway table or disable the addon with a printed reason.
- Policy for peer-derived caches (`chars`, `catalog`): on any schema bump, **drop and refetch** them (they are re-gossiped via HELLO/WANT). Only `orders` (and `me`) need real migration. This keeps migrations tiny.
- After loading, run `ValidateChar` / order `sanitize` over persisted records and discard failures.

### R4. One version source (fixes V5)
Read the version from the TOC at runtime (`C_AddOns.GetAddOnMetadata(ADDON, "Version")` or the legacy `GetAddOnMetadata`) and remove the literal from `Init.lua`. Show `version`, `PROTO_MAJOR.MINOR` and `schema` in `/ts version`.

### R5. Tests (fixes V8)
Add to `tests/`:
1. Sync ignores a message with `v` != local and increments `dropped`.
2. Chunk header with a foreign protocol is dropped without creating a buffer.
3. Minor skew: v1.1 client accepts a v1.0 HELLO, and a v1.0 client ignores an unknown message type from 1.1.
4. `Store.Migrate`: n -> n+1 happy path; newer-than-known schema is not modified.
5. Persisted garbage in `chars` is discarded on load.

### R6. Release hygiene
Bumping `PROTO_MAJOR` or `SCHEMA` must be called out in the changelog and release notes. Add a `CHANGELOG.md` and make the release workflow fail if the tag does not match the TOC version.

## 4. Priority

| # | Item | Effort | Do when |
|---|---|---|---|
| R3 | Migration + downgrade guard | small | **before the first schema change / first public release** |
| R1 | Version in chunk header + "newer version" hint | small-medium | before first public release (changing the header later is itself a protocol break) |
| R2 | Major/minor | small | together with R1 |
| R5 | Tests | small | with each of the above |
| R4, R6 | One version source, changelog | trivial | before release |

Because R1 changes the wire format, do it **now**, while protocol 1 has no deployed users. Once it ships, every later change is paid for in stranded clients.

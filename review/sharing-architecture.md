# Review: how members share data (sync architecture) and whether it is best practice

Date: 2026-11-16 · Scope: `Core/Sync.lua`, `Comm.lua`, `Codec.lua`, `Guard.lua`, `Orders.lua`, `Offers.lua`, `Events.lua`, `docs/protocol.md` · Build: master @ 61eff86 (protocol 2.1, schema 3)

**Verified vs. only read.** Code was read in full for the files above; `luajit tests/run.lua` = 134 passed, 0 failed. Message sizes in
section 4 were **measured offline** with the real Codec and LibDeflate on synthetic data (random words, so compression is
pessimistic; real data is probably 2-3x smaller, the proportions hold). Nothing touching the game client was run: two-client sync
is still unverified (`docs/status.md`). External claims are cited in section 7; where a source was thin it says so.

"Cross guild" is read as "between the members of one guild". Sharing between *different* guilds is not supported by design
(section 6).

## 1. What the design is

Decentralised, serverless, pull-based gossip over hidden addon messages (prefix `TShare`), no coordinator, no backend.

| Data | Who writes | Announce | Transfer | Conflict rule |
|---|---|---|---|---|
| Character record (professions, recipes) | the character itself only (`SNAP.char.name == sender`) | `HELLO{rev}` on GUILD | `WANT` whisper -> `SNAP` whisper (record + catalog) | single writer, higher `rev` (server time, `max(now, old+1)`) wins |
| Recipe catalog (names, reagents) | anyone who knows the recipe | piggybacks on SNAP | first writer wins | none (cache) |
| Orders | any member | `ORDER` on GUILD; `HELLO{odig}` digest of newest 100 | `OPUSH` whisper (<=10 per message) | state-based CRDT merge (per-crafter claims, earliest close wins) |
| Offers + dibs (2.1) | the owning character only | `HELLO{orev}` | `WANTO` -> `OFFERS` whisper | single writer, higher `rev` replaces the record |

Around that: plain-text chunk header with version (`2.1|id|idx|total|part`) read before buffering; own bounded serializer ->
Deflate -> addon-channel encoding; token-bucket pacing (burst 5, 0.9/s); inbound gate (GUILD, or WHISPER from a roster member);
allow-list sanitizers on everything inbound and on load; storm control (random delays, 20 login replies/min, `wanted` de-dup 60 s).

## 2. Verdict

**The shape is right and matches what comparable addons converged on. Keep it.** Single-writer-per-record, a tiny advertisement
with a revision, pull on demand after a random delay, server timestamps, an unauthenticated-but-guild-scoped trust model and a
CRDT-style merge for the one multi-writer object are exactly the building blocks used by GuildCrafts and DeltaSync (section 7) and
are the standard way to avoid write conflicts (single writer means no conflict to resolve; LWW is only needed for orders).
No backend is the correct call for this problem.

**What is not best practice yet is the transfer layer**, not the architecture. In order of impact: a full snapshot is whispered to
every requester (O(members) per change), the catalog is resent every time and is ~97% of each snapshot, there is no retry or
periodic anti-entropy for characters (the soak test assumes one that production does not have), and the send pump does not handle
the newer `SendAddonMessage` result codes. All are fixable inside protocol 2.x (additive minor change) without changing the model.

## 3. What is confirmed good (keep)

- **Version in a plain header, checked before buffering** and a major/minor rule. Best practice for any gossip protocol; DeltaSync
  uses a `MINOR` feature check the same way.
- **Pull with random delay after a tiny advertisement.** GuildCrafts does the same (revision-only advert, pull after 1-5 s jitter);
  its changelog shows the opposite (re-broadcasting data to the guild channel) had to be fixed.
- **Serialize, compress, encode before sending**: the Warcraft Wiki says to, because the server throttle is strict.
- **Own bounded serializer instead of `loadstring`**: safer than the wiki's alternatives and fine; no change needed.
- **Pacing below the documented limits**: per prefix 10-message allowance, +1/s (wiki). 5 burst / 0.9 per s stays under it.
  Result code `3` is already handled by re-queueing.
- **Server time as the version clock** (`GetServerTime`), not the local clock; `Horizon` rejects far-future values.
- **Sender gate and "author writes own record"**: stricter than either comparable addon (both describe no sender authentication).
- **Self-healing orders**: digest in HELLO + `OPUSH` is real anti-entropy for orders.

## 4. Findings

### A1. Full snapshot per requester: O(members) cost per change (High, scalability)
`Sync._onWANT` whispers the whole record **and the catalog entry of every recipe** to each peer that asks. A change is announced by a
GUILD `HELLO`, so every online member with an older copy asks. Measured (`SNAP`, 29 requesters = a 30-member guild):

| Recipes | Encoded | Chunks | One snapshot @0.9 chunk/s | 29 requesters |
|---|---|---|---|---|
| 50 | 5.9 KB | 27 | 30 s | 783 chunks, 15 min |
| 150 | 17 KB | 76 | 84 s | 2204 chunks, 41 min |
| 300 | 35 KB | 158 | 176 s | 4582 chunks, 85 min |
| 600 | 72 KB | **321** | - | over `MAX_PARTS` (200): dropped, only `Debug.Log("comm.toobig")` |
| 300, **no catalog** | 0.9 KB | **5** | 6 s | 145 chunks, 2.7 min |

Also the queue cap (600 chunks, `Comm.Send`) rejects whole messages, so a second burst of requesters is silently dropped.
This is realistic with a guild evening: someone learns a recipe, every member's client asks for a 76-158 chunk snapshot.
**Fix (additive, 2.2):**
1. Send the **record without catalog** (5 chunks for 300 recipes). The receiver computes the recipe ids it lacks in its catalog and
   asks `WANTC{ids<=100}`; **any** member who knows those recipes may answer `CATALOG{entries}` (entries are sanitized and
   cache-only; this also spreads the load and means a new install pulls each catalog entry once, not once per peer).
2. For the change path, **broadcast the small record once on GUILD** instead of N whispers (keep whisper pull for catch-up), or at
   least coalesce all `WANT`s that arrive within the random window into one GUILD `SNAP`.
3. Keep the 200-chunk limit but make "too big" visible (`/ts comm` counter) instead of a debug-log line.

### A2. No retry and no periodic anti-entropy for characters (Medium, convergence)
`Comm.RequestHello` is called on login, local change, offers change, `/ts clean`, `/ts hello` and window open. There is **no timer**
(the 60 s ticker only expires buffers, refreshes the roster and prunes orders). `WINDOW_OPENED` sends `login=false`, which peers do
not answer, and a requester that sent `WANT` never re-sends it. A lost `SNAP` (chunk loss, queue full, throttle, an instance, a
reload mid-transfer) is therefore healed only at the sender's next change or the receiver's next login. Orders are fine (digest).
`tests/test_soak.lua` hides this: its comment "periodic anti-entropy" calls `sync:Hello()` every simulated minute, which production
never does, so the "30 peers converge at 10% loss" result does not describe the shipped behaviour for characters.
**Fix:** (a) low-rate heartbeat `HELLO` every 10-15 min with +-20% jitter (GuildCrafts/DeltaSync both rely on one), (b) re-`WANT`
once or twice (e.g. after 90 s, bounded) when a `WANT` produced no `SNAP`, (c) make the soak test call the production timer path.

### A3. Send pump ignores most result codes (Medium, silent loss; needs in-game check)
`Comm.pump` re-queues only on `res == 3`. Per the wiki the enum now also has `8 ChannelThrottle`, `10 NotInGuild`, `11 AddOnMessageLockdown`,
`12 TargetOffline` (and `5/6/7/9` errors), and "success" only means *queued*. Every other non-zero code is counted as `chunksSent`
and the message is lost; a half-sent message is then discarded by the receiver after 60 s. WoW Forever shares the Midnight-era
restrictions (secret values; addon-message lockdown is a 12.0 enum value), and GuildCrafts had to add a sync pause policy for
combat/instances/zone changes. What `11` means exactly is **not documented** on the wiki; check on a live client.
**Fix:** switch on the result: `0` ok, `3/8` retry later, `11` pause the queue until the restriction ends (flush later, do not drop),
`10/12` drop that whisper target for a while, others drop with a counted, visible reason. Also treat a boolean `false` (Classic-style
return) as failure. Pause bulk traffic (SNAP/OFFERS/OPUSH) in combat and instances; HELLO/WANT may stay (GuildCrafts found that
pausing heartbeat/hello caused split-brain).

### A4. HELLO fan-out: forced, unbounded, carries a digest every time (Medium)
- `LOCAL_CHANGED` and `OFFERS_CHANGED` call `RequestHello(false, true)`: `force` bypasses the 30 s limit. Any bag change that alters the
  recipe-item set (looting, crafting, AH, bank) is a GUILD broadcast after a 1.5 s debounce, then **every peer whispers `WANTO`** and
  receives an `OFFERS` record (up to 300 items): the same O(members) pattern as A1.
- `HELLO` is documented as "single chunk" and queued ahead of everything, but with `odig` it is not: measured **1 chunk with 0 orders,
  2 with 20, 4 with 50, 7 with 100**. It is sent on each of those events.
**Fix:** trailing debounce of 30-60 s for offers, never `force` for them; replace `odig` by a short digest hash `ohash` in HELLO and
exchange the full digest only on mismatch (DeltaSync: version + hash broadcast, data on request).

### A5. Offline members are not propagated (Medium, functional gap, already noted in `docs/status.md`)
A member's data reaches you only if they were online while you were. Peers do not relay. Both comparable addons add relaying
(GuildCrafts: designated router + "touch" messages; DeltaSync: peer catch-up). The single-writer rule is what prevents relaying today.
Options, cheapest first: (1) accept it and say so in the README; (2) HELLO carries a compact `name -> rev` digest of known
characters and any member with a newer copy than the sender answers (relay); this **weakens "a peer authors only its own record"**:
under the agreed trust model (guild members trusted) that is acceptable, but then keep the owner's own SNAP authoritative and cap
accepted `rev` at `now` so a relayed forgery cannot block the owner's real update. Do not do (2) before A1/A2.

### A6. Old orders can be re-introduced (Low)
`Orders.Merge` has no age check; `Prune` runs only from the 60 s ticker. A member who logs in with orders older than the prune horizon
sends them in `OPUSH` within seconds (login HELLO exchange), peers merge them, and each prunes them again up to 60 s later: flicker
and avoidable traffic (GuildCrafts needed tombstones for the same class of problem). **Fix:** reject in `Orders.Sanitize` (or `Merge`)
anything past the prune horizon (`createdAt` > 30 d, `closedAt` > 7 d old) and prune once at load. Add a test.

### A7. Own pacing instead of ChatThrottleLib/AceComm (Low, optional)
The wiki says to use ChatThrottleLib or AceComm to queue messages, and warns that too much data across multiple prefixes can
disconnect the client. The own bucket is fine for this addon alone but does not share a budget with other addons. Also the wiki states
whispers outside instances are exempt from the per-prefix allowance, so the whisper path is paced far below what is allowed
(~200 B/s). Do not loosen it before A1 is done and measured in game; if the transfer time still matters afterwards, switch to a
byte-based budget or vendor ChatThrottleLib. (Source for the exact ChatThrottleLib rates could not be fetched; do not rely on numbers.)

### A8. Smaller points
- Catalog is first-writer-wins: a wrong or poisoned entry for a recipe nobody else has stays until `/ts clean`. Accepted under the trust
  model, but A1's `CATALOG` reply makes "prefer the entry that most members agree on" cheap; consider a per-entry hash.
- `Comm.Send` inserts "control" chunks one by one at position 1, so a multi-chunk HELLO is queued in reverse order. Harmless (reassembly
  uses `idx`) but surprising; insert as a block.
- Trial/veteran accounts cannot send addon messages on Forever (1.60.1, wiki): such members will look "silent". Mention it in the README.
- `GetGuildTradeSkillInfo` (documented for Forever 1.60.1) lists which guild members have which profession and at what skill, **without
  recipes**. Useful to show non-addon members as "has Alchemy 287" next to addon data; not a replacement for recipe sync.

## 5. Priority

| # | Item | Severity | Effort | Needs game client |
|---|---|---|---|---|
| A1 | Snapshot without catalog + `WANTC`/`CATALOG`, coalesced SNAP | High | M | final check yes |
| A2 | Heartbeat HELLO + bounded re-WANT, fix soak test | Medium | S | no |
| A3 | Result-code handling, pause in combat/instances | Medium | S-M | yes |
| A4 | Debounce offers HELLO, `ohash` instead of `odig` | Medium | S | no |
| A6 | Reject over-age orders | Low | S | no |
| A5 | Relay of offline members | Medium | L | no, but trust decision |
| A7/A8 | CTL / byte budget, catalog agreement, README notes | Low | S | partly |

A1, A2 and A4 are additive minor changes (protocol 2.2, new message types and optional fields; 2.0/2.1 peers ignore them), so no
schema or major bump is needed. Start via `feature-workflow` (new folder under `features/`) and add tests first: a size/chunk budget
test for SNAP, a 30-peer fan-out test that counts chunks, and the soak test using the real timer path.

## 6. Alternatives to this way of sharing (and sharing across guilds)

| Option | Verdict |
|---|---|
| **Addon-message gossip (current)** | Best fit: no backend, no accounts, works offline from any server, same approach as comparable addons. Keep; fix the transfer layer. |
| Guild/officer note as a data channel | Not recommended: tiny (31 characters, from memory, not re-checked), editable by anyone with rank rights, no recipes. |
| Custom chat channel (`CHANNEL`) | Not recommended: per the wiki Retail-only and disabled on Classic, any player can join (weaker than the guild gate). |
| `GetGuildTradeSkillInfo` | Use as a supplement (professions + skill of members without the addon); no recipe data. |
| External backend / companion app (SavedVariables upload) | Only if you need offline members or cross-guild at scale. SavedVariables are written only at logout/reload (stale), it adds accounts, hosting, abuse handling and a trust boundary. Not worth it for guild-only. |
| **Cross-guild sharing** | Not supported and the gate forbids it (GUILD channel is per guild; whispers need a roster entry). If wanted: explicit opt-in allow-list of character names per partner guild (the roster API cannot prove membership of another guild), send only the small record (A1 first), keep the single-writer rule. DeltaSync mentions GreenWall as a relay between allied guilds, which is the established pattern. Treat as a new feature with its own trust decision; do not weaken `Guard.Accept`. |

## 7. Sources (checked 2026-11-16)

- [Warcraft Wiki: C_ChatInfo.SendAddonMessage](https://warcraft.wiki.gg/wiki/API_C_ChatInfo.SendAddonMessage): 255-byte message, 16-char prefix; allowed
  channels; per-prefix allowance 10, +1/s, result `3`; whispers outside instances exempt; "success" only means queued; result enum
  incl. `10/11/12`; use ChatThrottleLib/AceComm; serialize+compress first; Forever trial-account restriction.
- [Warcraft Wiki: SendAddonMessageLogged](https://warcraft.wiki.gg/wiki/API_C_ChatInfo.SendAddonMessageLogged): same throttle; `AddOnMessageLockdown`
  listed but **not explained**.
- [Warcraft Wiki: Patch 1.60.1 API changes](https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes/notes): Forever shares Mainline UI/API, Midnight restrictions apply
  (secondary summary; provisional).
- [Warcraft Wiki: GetGuildTradeSkillInfo](https://warcraft.wiki.gg/wiki/API_GetGuildTradeSkillInfo): exists on Forever 1.60.1; professions and skill, no recipes.
- [GuildCrafts (CurseForge)](https://www.curseforge.com/wow/addons/guildcrafts/files/8836557): revision advert + jittered pull, designated router,
  version vectors, tombstones, pause policy, backoff, partial-scan guard. Inferred from changelog text, not from source.
- [DeltaSync (CurseForge)](https://www.curseforge.com/wow/addons/deltasync): version+hash broadcast, deltas, delivery verdicts, no signing,
  whisper caveats on some private cores, GreenWall relay. Author's own description.
- [AceComm-3.0](https://wowace.com/projects/ace3/pages/api/ace-comm-3-0): multipart splitting over ChatThrottleLib, priorities.
- Background on anti-entropy / LWW / state-based CRDTs: search results only (no single authoritative source); the single-writer
  argument in section 2 is my own reasoning.
- Not confirmable online: ChatThrottleLib's current numeric rates, and what `AddOnMessageLockdown` covers on Forever.

# Diagnosis: in 0.4.0 orders sync, but known recipes and available recipe items do not

Date: 2026-11-16 · Build analysed: master @ 7c0a09b (v0.4.0, protocol 2.1, schema 3) · Fixes and instrumentation: feature 008.

**Evidence level.** User report from a live guild (orders reach the others but show a wrong name; recipes and the Available tab
never arrive). Code read in full: `Core/Net/Communication.lua`, `Sync.lua`, `Codec.lua`, `Guard.lua`, `Store.lua`, `Util.lua`, `Events.lua`,
`Orders.lua`. Nothing was run in the game client. The **cause** below is reasoned from code plus the symptom pattern
(READ-ONLY); the **exact failing string** needs one `/ts export` from two members (section 5).

## 1. The symptom pattern points at one thing: whispers

| Data | How it travels | Channel | Reported state |
|---|---|---|---|
| Orders | `ORDER` broadcast on every change | **GUILD** | arrives |
| Orders catch-up | `HELLO{odig}` (GUILD) -> `OPUSH` | WHISPER | (masked: the GUILD broadcast already delivered them) |
| Known recipes | `HELLO{rev}` (GUILD) -> `WANT` -> `SNAP` | **WHISPER** both ways | never arrives |
| Available tab | `HELLO{orev}` (GUILD) -> `WANTO` -> `OFFERS` | **WHISPER** both ways | never arrives |

Everything that works is a single GUILD broadcast. Everything that fails needs a whisper round trip. So the failure is not in
the record format, the codec or the stores (the same codec carries `ORDER` fine); it is on the whisper path.

## 2. The whisper path has five points that compare player-name strings

A name reaches the addon from three independent client sources, and the whisper path only works if all three spell a
character **identically**:

* **me:** `UnitName("player") .. "-" .. GetNormalizedRealmName()` (`Api.GetPlayerInfo`, `Util.FullName`)
* **sender:** the `sender` of `CHAT_MSG_ADDON`, completed with `GetNormalizedRealmName()` only if it has no `-`
* **roster:** `GetGuildRosterInfo(i)`, same completion

| # | Where | Compares | Fails silently when |
|---|---|---|---|
| 1 | `Comm.pump` -> `Util.WhisperTarget` | target string the server must resolve | 0.4.0 trusted `Ambiguate(full, "none")` first; if Forever's `Ambiguate` does not treat the normalized realm as "mine" it returns `Name-Realm` unchanged, and the server answers "no player named Name-Realm is online" (the 0.3.2 bug, still present for addon whispers) |
| 2 | `Guard.Accept` (WHISPER gate) | `sender` vs **roster** set | the two sources spell the realm differently: every `WANT`, `SNAP`, `WANTO`, `OFFERS`, `OPUSH` is rejected before parsing, counted only in `/ts comm rejected=` |
| 3 | `Sync._onWANT` / `_onWANTO` | `names[1]` (the **asker's** view of my name) vs **me** | asker builds my name differently: no reply, no log |
| 4 | `Sync._onSNAP` / `_onOFFERS` | record name (**sender's me**) vs **sender** as I see it | `error("char/sender mismatch")`, only a `sync.error` debug line |
| 5 | `Store.Prune` on every roster update (~5 min) | stored keys vs **roster** | records that DID arrive are deleted again if their key is not spelled like the roster |

Point 1 is consistent with the second symptom too: lists display names through `ShortName = WhisperTarget`, so a requester
shown as `Name-Realm` instead of `Name` ("orders with the incorrect name") is the same `Ambiguate` result that breaks the
whisper target.

## 3. A second, independent cause of a wrong name in orders

An order carries only `recipeID`. Its display name comes from the catalog (`Store.GetRecipe`), and the catalog is filled
**only by `SNAP`**, which never arrives (section 1). The fallback is `Names.Recipe -> C_Spell.GetSpellInfo(recipeID)`. On
Forever recipe ids are not spell ids (`docs/api-findings.md`: "recipeID is NOT a spell ID in the Classic sense"), so the
lookup can return an unrelated spell's name. The new report prints, for every order, `catalog name=` and `spell lookup=`
side by side, so one export tells which of the two "incorrect names" the guild sees.

## 4. Real bugs found on the way (fixed in feature 008)

| ID | Severity | Bug | Fix |
|---|---|---|---|
| B1 | High (probable cause) | `Util.WhisperTarget` let `Ambiguate` decide for my own realm; a client whose `Ambiguate` does not know the normalized realm sends every addon whisper to `Name-Realm` | own-realm comparison first (the same string `FullName` appended), `Ambiguate` only for other realms. Test `whisper: my own realm is stripped even when Ambiguate returns the full name` |
| B2 | Medium | Stale identity: `Comm.Start` captured `me` once and could run before `PLAYER_LOGIN` (from `PLAYER_GUILD_UPDATE` / `GUILD_ROSTER_UPDATE` during loading). `SavedVariables` are account-wide, so `db.me` is then the **previously played character**: the alt answers `WANT`s as the other character, ignores its own, and its `HELLO` advertises the other character's rev | `Comm.ready` set at `PLAYER_LOGIN`, `Comm.Start` refuses before; Sync reads `me` through a function at use time; the name is rebuilt 3 s after login (realm can be empty very early) and a change is traced |
| B3 | Medium (observability) | Every failure on the whisper path was silent: gate rejections only counted, name mismatches not logged at all, `SendAddonMessage` result codes other than 3 (throttle) counted as sent, too-big/queue-full snapshots only a debug line, incomplete multi-chunk transfers discarded without a trace | network trace (section 6) |

## 5. What to collect now (one session, two members)

1. Both install the build with feature 008 and log in.
2. Member A: `/ts`, **Debug** tab, filter **Problems**. Member B: `/ts hello` (or the **Send HELLO** button).
3. Both: **Export report** (or `/ts export`), Ctrl+A, Ctrl+C, paste to the author.

How to read it:

| Report shows | Meaning | Next fix |
|---|---|---|
| `identity` warn "my name ... is not in the guild roster", or `me in cached roster: NO` with "roster names with my character name: ..." | roster and `me` spell the realm differently (points 2, 3, 5) | canonical name key (section 7, R1) |
| out `WANT`/`SNAP` `[sent]` with `(to Name)` on A, nothing `<-` on B | server did not deliver the whisper: target or server-side restriction on addon whispers | compare B's `(raw ...)` sender form; if whispers never arrive at all, move pulls to GUILD (R3) |
| `<- WHISPER ... [rejected] not in roster as X; roster has Y` | point 2, the exact two spellings are printed | R1 |
| `<- WANT [ignored] asked for X but I am Y (name mismatch)` | point 3 | R1 |
| `<- SNAP [error] char/sender mismatch: record X from Y` | point 4 | R1 |
| `-> SNAP [dropped] too big` or `<- [dropped] incomplete: got n of m chunks` | size/loss (section 7, R4) | R4 |
| `-> ... [failed] TargetOffline / GeneralError / NotInGuild` | the client refused the whisper | target form or server restriction |
| `** warn prune: not in guild roster: ...` | point 5: records arrived and were deleted | R1 |
| orders: `catalog name=- spell lookup=<other spell>` | section 3 | resolved by fixing SNAP; R5 |

## 6. Instrumentation added (feature 008)

* **Network trace** (`Core/Debug/Trace.lua`): one entry per message in and out, persisted (last 400, survives `/reload`):
  time, direction, channel, peer, raw sender form, whisper target actually used, type, chunks/bytes, payload summary
  (revs, record names, counts; never the full payload), status and **reason**. Outbound entries move `queued -> sent | failed`
  with the decoded `SendAddonMessage` result name; inbound entries carry Sync's decision ("char: have 0 < 1763299950 -> WANT",
  "asked for X but I am Y (name mismatch)", "stored", "not newer than what I hold").
* **Local events** in the same trace: sync start (identity, protocol, roster size), roster loaded (me found or not), identity
  mismatch (+ one chat warning per session), identity change after login, records deleted by a roster prune, multi-chunk
  transfers that never completed, prefix registration failure.
* **Debug tab** in the window: scrollable trace, newest first, filter All / Incoming / Outgoing / System / Problems,
  live status line (queue, incomplete transfers, roster size, "me in roster", send failures), Send HELLO, Clear, Export.
  Hover a row for the full line.
* **Export** (`/ts export` or the button): a copyable report with addon/protocol/schema, every identity source
  (`UnitName`, `UnitFullName`, `GetRealmName`, `GetNormalizedRealmName`, built name, `Ambiguate`, how the roster spells me,
  a raw roster sample), transport counters, incomplete transfers, pending pulls, every character/offer record held with its
  rev, every order with the source of its name, the trace and the debug log.
* Commands: `/ts trace [n] [problems]`, `/ts ident`, `/ts export`, `/ts debug [n]`; `/ts comm` gained `send failures`.

## 7. Recommended changes after the export confirms the cause

| ID | Change | Why | Protocol |
|---|---|---|---|
| R1 | **One canonical player key**: a single `Util.Canon(name)` applied to `me`, every sender and every roster name (strip spaces/apostrophes in the realm, compare case-insensitively, and on a single-realm server key by character name only). Migrate stored `chars`/`offers` keys on load. | removes points 2-5 in one place instead of five | none (local key only) if the wire keeps sending the raw name |
| R2 | Whisper target from the **roster's own spelling** of that member (keep `roster[canon] = rawRosterName`) | the server resolves the form it reports itself | none |
| R3 | If addon whispers turn out not to be delivered on Forever at all: answer `WANT` with a **GUILD** `SNAP` (coalesced: one broadcast serves every asker) | also fixes the O(members) cost from `review/sharing-architecture.md` A1 | additive (2.2): receivers already accept SNAP from any channel; only the sender changes |
| R4 | Send the record **without the catalog**, catalog entries on demand (`WANTC`/`CATALOG`) | SNAP is ~97% catalog; 600+ recipes exceed `MAX_PARTS` and are dropped (`review/sharing-architecture.md` A1) | additive 2.2 |
| R5 | Put the recipe **name snapshot into the ORDER** (`name`, `loc`), used when the catalog lacks the recipe | orders read correctly even before any SNAP arrives; no spell-id lookup with a recipe id | additive (optional field) |
| R6 | Retry/anti-entropy: re-HELLO every ~10 min while a pull is outstanding (`review/sharing-architecture.md` A2) | a lost whisper is never retried today | none |

R1 is the most likely fix; R2/R3 depend on what the export shows about delivery.

## 8. ROOT CAUSE CONFIRMED (first export, 2026-11-16)

The first `/ts export` (one member, dev build) settled it, and it was none of the guessed realm spellings: **characters on
Forever have surnames**. `UnitName("player")` returns `"Drakk", "Nuk"` (surname in the slot retail uses for the realm); the
roster and every chat sender say `"Drakk Nuk"`; the realm is `"CAMWOW EU4 Realm 5 PvE"` for everyone.

| Source | 0.4.0 made of it | Result |
|---|---|---|
| me (`UnitName` + realm) | `Drakk-CAMWOWEU4Realm5PvE` | surname dropped |
| roster `"Drakk Nuk"` | `Drakk Nuk-CAMWOWEU4Realm5PvE` | |
| sender `"Drakk Nuk"` | `Drakk Nuk-CAMWOWEU4Realm5PvE` | |

So roster and senders agreed with each other (the whisper gate, point 2, passed), but **my own name disagreed with both**:
point 3 (`WANT` for "Drakk Nuk" never answered by "Drakk"), point 4 (`SNAP` record "Drakk" from sender "Drakk Nuk" refused),
and my own GUILD echo was taken for a second player, so the client tried to pull records from itself (visible in the export:
`pulled record of Drakk Nuk-...`). Orders worked because nobody compares names on that path; they showed the first name only.

Fix (feature 008): `Api.MyBaseName` builds `"First Surname"` from the two `UnitName` values; `Util.Canon` completes a bare
first name with the surname when the roster has exactly one member with that first name, so records and keys written by
0.4.0 (`"Drakk-Realm"`, `"Mira-Realm"`) move to the full names on load. Pinned by `tests/test_forever_names.lua`, built
from the export's values; mutation check (surname detection off) -> 4 FAIL.

## 9. Implemented (feature 008, protocol 2.2) and what is still open

On the user's request R1, R2, R3, R5 and R6 were built before an export, designed to cover every spelling difference the
code can meet instead of one guessed difference:

| ID | Built as | Covers |
|---|---|---|
| R1 | `Util.Canon` + `Store.Recanon`; realm spellings folded (case, spaces, `'`, `-`); the roster's spelling of my own character and the sender of my own GUILD echo (recognised by this session's id salt; GUILD only) are learned as my realm | points 2-5 for any spelling of MY realm, whichever source differs |
| R2 | `WhisperTarget` strips every known spelling of my realm | point 1 |
| R3 | retry after 45 s / 90 s on GUILD with `via = "GUILD"`, answered on GUILD, deduplicated per rev | whispers not delivered at all, or delivered to the wrong target |
| R5 | `name`/`loc` on orders | section 3 |
| R6 | the retries above + a HELLO every 15 min | lost messages |

Not built: R4 (catalog split; scalability, not this bug). Still unproven: which of the points actually fired on Forever.
The exports (section 5) now show it directly: `learned my realm spelling ...` / `names normalized ...` lines, `via=GUILD`
requests and GUILD `SNAP`s in the trace, and `my realm: ... | learned spellings of it: ...` in the identity section.
Remaining gap: if the server spells realms of OTHER members differently from mine in a way none of the sources reveal
(cross-realm guilds), those members still meet only through R3 (GUILD) and are keyed by their own spelling.

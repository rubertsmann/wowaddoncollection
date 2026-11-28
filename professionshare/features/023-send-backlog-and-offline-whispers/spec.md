# 023 Send backlog and offline whispers: spec

- Status: done
- Created: 2026-11-23
- Target version: ProfessionShare 1.2.1, GuildGames 0.4.1, LibGuildSync MINOR 5
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
Stop the game message "Momentan ist kein Spieler mit dem Namen ... online" caused by addon whispers that waited in an
ever-growing send queue until their recipient had logged out.

## Requirements
- R1: A newer record answer (ProfessionShare SNAP, OFFERS, ACCESS; GuildGames GAMES) to the same recipient on the same
  channel replaces one still waiting, as long as none of its chunks was sent. Other types are never replaced.
- R2: A queued whisper is dropped (not sent) when the last guild roster shows its recipient offline and nothing was
  heard from them in the last 120 s. Unknown names and missing roster data keep the old behaviour (send).
- R3: ProfessionShare announces its own changes (record, offers, access) coalesced: at most one HELLO per
  `Channel.HELLO_INTERVAL_SECONDS` (30 s), like GuildGames already does.
- R4: Dropped and replaced messages are visible in the trace (`dropped` / `replaced` with the reason).

## Non-goals
- No wire change (protocol stays ProfessionShare 2.4, GuildGames 1.2); no stored-data change.
- No change to the send rate (0.9 chunks/s) or the record size.

## Design
- `libguildsync/LibGuildSync/Guild.lua`: `GetGuildRoster` records the 9th `GetGuildRosterInfo` value (online) per
  canonical name; `Guild.IsOnline(name)` -> true/false/nil.
- `libguildsync/LibGuildSync/Channel.lua`: option `replaceableTypes`; `Channel.RemoveWaiting`, `Channel.RecipientOffline`,
  `Channel.DropWhispersTo`, `Channel.SendChunk` (split out of `SendQueued`); `channel.lastHeardAt[sender]` set for every
  accepted inbound message. MINOR 4 -> 5 in every file.
- `professionshare/Core/Game/Api.lua`, `guildgames/Core/Game/Api.lua`: `Api.IsOnline` delegate (the channel's guild access).
- `professionshare/Core/Net/Communication.lua`: `replaceableTypes` SNAP/OFFERS/ACCESS; WANTA joins the priority types.
- `guildgames/Core/Net/Communication.lua`: `replaceableTypes` GAMES.
- `professionshare/Core/Game/Events.lua`: LOCAL_CHANGED / OFFERS_CHANGED / ACCESS_CHANGED -> `RequestHelloSoon`.

## Tasks
- [x] T1 (M): library replace + offline drop + roster online flag. Verify: `libguildsync/tests/test_channel.lua` (3 new tests).
- [x] T2 (S): addon wiring (Api.IsOnline, replaceableTypes, coalesced HELLO). Verify: `professionshare/tests/test_send_backlog.lua`, `test_load.lua`; `guildgames/tests/test_send_queue.lua`.
- [x] T3 (S): docs, changelogs, release.

## Review Focus (failure modes a happy-path test would miss)
1. RF1: a message partly sent is replaced -> the receiver keeps a half buffer and never gets the record. Pinned: replace only when `sentParts == 0` (test_channel "replaces ... none of it sent").
2. RF2: the roster is older than a member's login -> a whisper to an online member is dropped. Pinned: heard within 120 s counts as online (test_channel "unless heard from recently").
3. RF3: client throttle while dropping/sending -> the chunk is lost. Pinned: `SendChunk` returns false, the chunk stays first (existing throttle test).
4. RF4: a dib toggle now reaches others up to 30 s later (coalesced HELLO). Accepted: the record answer itself is unchanged.

## Cross-cutting checklist (answer every line; "n/a: reason" is fine)
- [x] Protocol: unchanged (no message shape change).
- [x] Stored data: n/a, nothing stored.
- [x] Trust model: n/a, outbound only; inbound gate unchanged (lastHeardAt only for accepted senders).
- [x] Localization: n/a, no UI text.
- [x] Load order: n/a, no new files in the TOCs.
- [x] Packaging: library files are copied through the Libs link as before.
- [x] Tests: listed in T1/T2.
- [x] Docs: libguildsync CHANGELOG, both addon CHANGELOGs and RELEASE_NOTES, doc.md.

## Decisions (user answers and design choices, newest last)
- 2026-11-23: Evidence from the live SavedVariables (1.0.2): 434 chunks waiting at session end, oldest 756 s, 53 waiting answers already outdated, 19 own revisions in 814 s while levelling a profession (each skill-up = new rev = forced HELLO = every member pulls 7-8 chunks).
- 2026-11-23: User approved fixes A (replace), B (offline drop), C (coalesced HELLO) and the releases ("do it").
- 2026-11-23: 120 s "recently heard" window: the roster refreshes every 5 minutes and on roster events, so a fresher sign of life wins.

## Open questions
- Does Forever fire GUILD_ROSTER_UPDATE when a member logs out (fresh online flags)? (needs: game)

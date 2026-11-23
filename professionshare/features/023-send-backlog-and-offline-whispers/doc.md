# Send backlog and offline whispers

Status: verifying | Since version: ProfessionShare 1.2.1, GuildGames 0.4.1, LibGuildSync MINOR 5 | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
Fewer and fresher sync messages: while you craft, your changes are announced at most every 30 seconds, an answer that a
newer one replaces is no longer sent, and nothing is whispered to a guild member who has gone offline. The game message
"no player named ... is online" no longer appears because of the addon.

## How it works
- LibGuildSync Channel: option `replaceableTypes`; a newer message of such a type to the same recipient on the same
  channel removes a waiting one with no chunk sent (trace `replaced`). Before a whisper chunk goes out, the roster's
  online flag (`Guild.IsOnline`, read in `GetGuildRoster`) is checked; offline and not heard from for 120 s -> all its
  waiting whispers are dropped (trace `dropped`, "recipient offline (guild roster)").
- ProfessionShare: SNAP, OFFERS, ACCESS replaceable; own changes use `RequestHelloSoon`. GuildGames: GAMES replaceable.
- No wire or stored-data change.

## Limits and known issues
- The online flag is as fresh as the last roster update (every 5 minutes, and whenever the game sends one).
- A dib or offer change reaches other members up to 30 s later than before.

## Changelog line
- Sync sends fewer, fresher messages and no longer whispers members who went offline.

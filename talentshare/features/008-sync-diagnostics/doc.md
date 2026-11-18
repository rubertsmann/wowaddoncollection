# Sync diagnostics

Status: verifying | Since version: 0.4.1 (unreleased) | Spec: [spec](spec.md) | Verification: [verify](verify.md) | Analysis: [review/sync-0.4.0-diagnosis.md](../../review/sync-0.4.0-diagnosis.md)

## What it does
Records every sync message this client sends and receives, with the reason for what happened to it, and shows it in a
**Debug** tab. One button (or `/ts export`) produces a copyable report that a guild member pastes to the addon author, so a
sync problem can be explained from the report instead of guessed. It also warns once in chat when this character's name
does not match the guild roster (the condition that silently stops recipe and item sync).

## How to use
- UI: `/ts` -> **Debug** tab. `Show:` cycles All / Incoming / Outgoing / System / Problems. Hover a row for the full line.
  **Send HELLO** asks the online guild to compare data now. **Export report** opens the copy window (Ctrl+A, Ctrl+C).
- Name check: Debug tab -> **Name check** shows every name source as Status / Method / Value / Expected / Behaviour (location in the tooltip); same table in `/ts ident` and in the export.
- Commands: `/ts export` (report window), `/ts trace [n] [problems]` (last n trace lines in chat), `/ts ident` (name check; identity
  sources), `/ts debug [n]`, `/ts comm` (now with send failures). Dev build: `/tsd`.

## How it works
- Data (SavedVariables): `db.trace` = ring of the last 400 entries `{ seq, t, dir, ch, peer, raw, via, mt, st, why, info, parts, bytes }`;
  emptied by `/ts clean`, sanitized on load. Schema stays 3.
- Messages: protocol 2.2 (`via` on WANT/WANTO, recipe name on orders; see docs/protocol.md section 8).
- Modules: `Core/Trace.lua` (ring, summaries, formatting; pure), `Core/Comm.lua` (records in/out, decodes
  `SendAddonMessage` results, gate reasons, incomplete transfers, identity check), `Core/Sync.lua` (returns status + reason per
  message), `Core/Diag.lua` (report, `/ts ident`, `/ts export`), `Core/Api.lua` (`IdentityInfo`), `UI/Window.lua` (tab, export window).
- Statuses: out `queued -> sent | failed | dropped` (`sent` = accepted by this client, not proof of delivery); in `ok | ignored |
  dropped | rejected | error`; local `info | warn`.

## Localization
Tab labels, buttons, the status line and the chat warning are translated (deDE). Trace lines and the report are English on
purpose: they are evidence for the author and are compared across clients of different languages.

## Limits and known issues
- `sent` means the client accepted the chunk; whether it arrived is only visible in the receiver's report.
- Times are UTC (server time modulo one day).
- The report contains character names of guild members (needed to explain name mismatches); share it only with the author.

## Changelog line
- Debug tab with the network trace, `/ts export` diagnostic report, identity warning; fixes for stale identity on alts and same-realm whisper targets.

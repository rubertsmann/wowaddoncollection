# Naming, types and logging overhaul

Status: verifying | Since version: next release | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
Internal. The rules are in [docs/coding-conventions.md](../../docs/coding-conventions.md): full-word names with one
shared vocabulary, LuaLS annotations, and one logging helper (`Core/Base/Log.lua`).

## For players
`/ts debug [lines]` and the `/ts export` report show log lines like
`2026-11-17 10:42:07 ERROR [communication.send] the client refused an addon message :: channel=GUILD reason=... target=-`.
More failures are recorded than before (saved-data migration, event handlers, sends, whispers, profession window reads).

## Compatibility
Wire protocol (2.2), saved data (schema 3) and slash commands are unchanged; this build talks to 0.4.x / 0.5.0 clients as before.

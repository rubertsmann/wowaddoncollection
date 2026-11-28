# 054 Party and raid portrait key icon: spec

- Status: planned
- Created: 2026-11-28
- Target version: next
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
A small key icon on party and raid frames for members who hold a key or attunement, with a tooltip listing them.

## Requirements
- R1: Option (off by default) in the settings page.
- R2: When on, a member of my party/raid who holds any key gets a small icon on their unit frame; hover lists the keys.
- R3: No secure-frame changes; no Lua error in combat or when the frames are missing.

## Non-goals
- <what this deliberately does not do>

## Design
- Deferred from 022 (R8 / T7). Forever's party/raid frames are unknown, so check the frame names in game first.
- Files: `UI/GroupIcons.lua` (new): non-secure textures anchored to party/raid unit frames; TOC entry; option in the grouped settings page.
- Data shape change: none (uses the synced access records). Message shape change: none.

## Tasks
- [ ] T1 (S): probe the party/raid frame names on Forever (dev command). Verify: user output.
- [ ] T2 (M): `UI/GroupIcons.lua` + option + deDE. Verify: test_load.
- [ ] T3 (S): in game in a group. Verify: user.

## Review Focus (failure modes a happy-path test would miss)
1. RF1: <input/condition> -> <expected behaviour>. Pinned by: T?

## Cross-cutting checklist (answer every line; "n/a: reason" is fine)
- [ ] Protocol: `ns.PROTOCOL` decision: <unchanged | bump | additive>, reason:
- [ ] Stored data: `Store.SCHEMA` decision + migration: 
- [ ] Trust model: peer data validated by allow-list; peer strings escaped before display:
- [ ] Localization: only IDs stored/sent; UI text through `ns.L`; notes limited in bytes (UTF-8 safe):
- [ ] Load order: TOC updated, new file position justified:
- [ ] Packaging: `.pkgmeta` / `tools/package.ps1` still include/exclude correctly:
- [ ] Tests: new `tests/test_<slug>.lua`, adversarial cases listed:
- [ ] Docs: README, CHANGELOG, docs/status.md, doc.md:

## Decisions (user answers and design choices, newest last)
- 2026-11-28: moved out of 022 (deferred stretch R8/T7) when 022 was closed as done.
- 2026-11-28: still wanted (user: "054 yes").

## Open questions
- Which party/raid frames does Forever use (Blizzard default, compact raid frames)? Answered by T1. (needs: game)

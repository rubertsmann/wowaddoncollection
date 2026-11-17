# {{ID}} {{TITLE}}: spec

- Status: planned
- Created: {{DATE}}
- Target version: <x.y.z>
- Owner: <user | claude>
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
<one sentence>

## Requirements
- R1: <testable statement>
- R2:

## Non-goals
- <what this deliberately does not do>

## Design
- Files touched: `<path>` (new|changed): <why>
- Data shape change: <none | describe>
- Message shape change: <none | describe>
- Pure logic lives in: <module>; WoW calls only in `Core/Game/Api.lua`.

## Tasks
- [ ] T1 (S): <task>. Verify: <test name or in-game step>
- [ ] T2 (M):

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
- {{DATE}}: <decision> (why)

## Open questions
- <question> (needs: user | game | second player)

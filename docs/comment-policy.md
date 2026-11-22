# Comment policy (all addons)

A comment must be **true** and must say something the code cannot. Names carry the *what*; comments carry the *why*.
`tools/comment-audit.lua` checks the mechanical part; the rest is checked in review.

## Keep

| Kind | Example |
|---|---|
| Why the code does something surprising | `-- tonumber("1e999") is +inf: peers must not smuggle non-finite values past the serializer` |
| A client (WoW API) fact: taint, protected calls, event order, secret values | `-- the client may hide the health in combat; then the throw rolls as at THROW_HEALTH` |
| A contract with data outside the code: wire fields, saved fields, slash words | `---@field disp integer CreatureDisplayInfo ID, 0 when unknown` |
| A short module header: what the module does, what it must not do (at most ~5 lines) | `-- PURE Lua: no WoW calls. Clocks and random numbers are parameters.` |
| LuaLS annotations (`---@param`, `---@return`, `---@class`, `---@field`) | must match the code: names, order, optionality |
| The unit of a number when the name has none | `MAXIMUM_TICK = 5 -- seconds` |

## Remove

| Kind | Why | Where it goes instead |
|---|---|---|
| Who asked and when: `(user 2026-11-20)`, quoted requests | history, not behaviour | `git log`, `features/<id>/log.md` |
| Feature / requirement / task ids in code: `feature 018`, `R10`, `RF2`, `T3`, `spike S3` | they rot when the spec is renumbered | the feature's `spec.md` and `verify.md` (tests may name them) |
| Restating the code: `-- clear the table` above `wipe(t)` | noise; drifts from the code | nothing |
| Long design write-ups in a module header | too long to keep true | `features/<id>/doc.md`, `docs/*.md` |
| Commented-out code | git has it | git |

## Prefer a name over a comment

- A block comment over a chunk of a function: move the chunk into a `local function` named after what it does.
- A comment explaining a condition: a named local (`local isInsideCatchWindow = ...`).
- A new constant carries its unit in the name (`_SECONDS`, `_COPPER`). Existing public constants are not renamed
  only for this (other modules, tests and UI use them); their unit comment stays.
- **Never rename** what leaves the code: SavedVariables keys, wire fields, LibGuildSync's public API, slash words,
  locale keys, globals and frame names used by XML/TOC/bindings.

## Wrong comment = possible bug

When a comment and the code disagree, find out which is right before editing either (tests, spec, git log). Fix the
comment if the code is right; if the code is wrong, report it and fix it in its own commit with a test.

## Checking

```
luajit tools/comment-audit.lua guildgames professionshare libguildsync fpvcigarette foreverbetteruiplus
```

`--strict` exits 1 on any finding. Checks: provenance, paths that do not exist, `Module.Name` where `Name` is defined
nowhere, `---@param` names that are not parameters of the function below.

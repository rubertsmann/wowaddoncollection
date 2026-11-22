# Comment audit and reduction

Status: verifying | Since version: none (developer tooling; ships with nothing) | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
Every code comment in the monorepo (five addons, their tests and tools) was read against the code it describes. Wrong
and stale comments were corrected; history (who asked, when, feature and requirement ids) was removed from code. A
policy and an audit tool keep it that way: each addon's offline suite now fails on a comment the tool can prove wrong.

## How to use
- Policy: [docs/comment-policy.md](../../../docs/comment-policy.md) (keep / remove / prefer a name / never rename).
- Audit one or more addons from the monorepo root: `luajit tools/comment-audit.lua guildgames professionshare`
  (`--summary` for counts only, `--strict` to exit 1 on findings).
- Prove a change touched comments only: `luajit tools/comment-audit.lua --code-only HEAD` (or any revision).
- The suites run it: `tests/test_comments.lua` (guildgames, professionshare, libguildsync) and an inline test in
  fpvcigarette and foreverbetteruiplus.

## How it works
- `tools/comment-audit.lua` lexes Lua (strings and long brackets are skipped), then checks every comment:
  provenance patterns (outside tests), `*.lua/*.toc` paths that exist nowhere, `Module.Name` where `Module` is a table
  of the addon (or LibGuildSync) and `Name` is defined nowhere, and `---@param` names that are not parameters of the
  function below. `--code-only` blanks every comment, squeezes whitespace and compares with the revision.
- Data, messages, protocol, SavedVariables: no change.

## Results
| Addon | Comments | Wrong or stale comments fixed (examples) |
|---|---|---|
| libguildsync | 965 | Locale header named a non-existent `Register`; `/x trace` order; Trace and Channel status lists; CanonicalName ignored realm-free names |
| guildgames | 3018 | combat log named on a client that forbids it; ProfessionShare's minimap angles; coin flip axis; Survivor's weapons and factors; five doc blocks above the wrong function; test clock date |
| professionshare | 1990 | trace header; Store schema list; tryCall; resizable list width; `ns.BUILD` |
| fpvcigarette, foreverbetteruiplus | 181, 91 | Fader's hover call; a missing class field; runner folders |

Code findings, each in its own commit: dead `HOSTILE_FLAG` (Catcher.lua), dead `Link` (guildgames/tools/deploy.ps1),
two tests that no longer tested what their comments said (professionshare test_hardening, test_orders), a misnamed
libguildsync test. The fixes are listed per commit message, not counted one by one; verify.md says how each file was
checked.
Pilot refactor: `AzeCaught.Tick`'s commented sections and `NoteFound`'s eviction block became named local functions.

## Limits and known issues
- Comment VOLUME barely changed (comment text -2.2%, line count flat): almost every comment here explains a why, a
  client fact or a data contract, which the policy keeps. Provenance was mostly a clause inside such a comment, so
  removing it shortened lines rather than deleting them. A further cut needs more "name instead of comment" refactors
  like the AzeCaught pilot (code changes, one module per commit).
- The member/path checks are heuristic: a comment naming a field of a non-module table is not checked.
- lua-language-server is not installed; the audit's own `param` check stands in for `--check` (no type checking).
- Public constants were not renamed to carry units (decision in spec.md); their unit comments stay.

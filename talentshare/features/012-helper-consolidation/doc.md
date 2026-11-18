# Helper consolidation

Status: verifying | Since version: next release | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
Internal refactor, no player-visible change. Helpers that several modules had re-implemented (with small, drifting
differences) now exist once. Where the copies differed, the safer behaviour won.

## Shared helpers
| Helper | Replaces | Note |
|---|---|---|
| `U.Count(t)` | `count` in Diag and Trace, inline loops in Store/Offers/DevProbe | non-table -> 0 |
| `U.SortedKeys(t)` | `Diag.sortedKeys`, key-collect+sort in Scanner, Offers, Util, Init, DevProbe | numbers, then strings; never errors |
| `U.Wipe(t)` / `U.Refill(t, from)` | inline loops and `refill` in Store, the loop in Comm.Recanon | in place |
| `U.SanitizeMap(map, fn, keyOk)` | per-map pcall loops in Store and Offers `SanitizePersisted` | returns map, dropped |
| `U.Me()` | `me()` in Comm, Alerts, Window; inline in Events | safe before Store.Init |
| `U.ChatSafe(s)` | the pattern inside `Model.ChatText` | sits next to `U.Esc` |
| `Store.Knows(rec, id)` | `knows` in Model and Notify | false on malformed records |
| `Store.RecipeCount(rec)` | Diag `recipes`, `/ts chars`, Trace SNAP summary, Store.Counts | |
| `itemIDOf(link)` (Api.lua, local) | `itemIDFromLink` | nil for non-strings |

Rule for new code: use these instead of writing the loop again.

## Not merged on purpose
Same name, different job: `signature` (Scanner vs Offers), `Counts` (Store/Offers/Trace), `Recanon` (Comm calls Store's),
`SanitizePersisted` per module (Trace's is a ring buffer), `Get`/`List`/`New`, `isSel` closures in Window.

## Limits and known issues
- `/ts export` lists numeric keys in numeric order now (was text order); cosmetic.

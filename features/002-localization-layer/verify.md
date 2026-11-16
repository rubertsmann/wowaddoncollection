# 002 Localization layer: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` | `MULTI-CLIENT` | `READ-ONLY` | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> 30 passed, 0 failed
Result after work:    `luajit tests/run.lua` -> 51 passed, 0 failed

| ID | Requirement / Review Focus | How verified | Level | Evidence | Result | Date |
|---|---|---|---|---|---|---|
| R1 | One profession across languages and 0.1.0 records | `names: ProfKey merges ...`, `model: mixed-language guild shows ONE Cooking entry ...` | OFFLINE | tests/test_localization.lua | pass | 2026-11-16 |
| R2 | Profession display order | `names: profession display follows the viewer's language`, `names: a name learned ...` | OFFLINE | tests/test_localization.lua | pass | 2026-11-16 |
| R3 | Recipe/reagent names for the viewer | `names: recipe name ...`, `model: reagent names come from the viewer's client ...` | OFFLINE | tests/test_localization.lua | pass; whether Forever's spell name equals the window's recipe name is NOT-VERIFIED (checklist) | 2026-11-16 |
| R4 | All UI text through L, deDE complete, placeholders | `locale files: ...` (3 tests) + `ui lint: no hardcoded user-facing text` | OFFLINE | tests/test_locale_files.lua | pass | 2026-11-16 |
| R5 | `/ts locale` override | code read (`Core/Locale.lua`, `Core/Events.lua`); `locale: missing translations ...` covers `SetUI` | READ-ONLY | slash handler not executed | not run in game | 2026-11-16 |
| R6 | Case/accent-insensitive search and sort | `utf8: Fold and SearchKey ...`, `model: search and sort ignore case and accents ...` | OFFLINE | tests/test_localization.lua | pass | 2026-11-16 |
| R7 | Note byte limit, UTF-8 safe | `orders: notes are byte-limited ...`, `utf8: TruncateUtf8 ...`; `SetMaxBytes` on the EditBox not run | OFFLINE (logic) / READ-ONLY (EditBox) | tests/test_localization.lua | pass | 2026-11-16 |
| R8 | Buttons fit translated labels | code read (`setLabel`) | READ-ONLY | n/a | layout never seen | 2026-11-16 |
| R9 | Wire compatible with 0.1.0 (PROTOCOL unchanged) | `store: hostile id/loc/name ...`; old-record merge tested; no real 0.1.0 client run | OFFLINE (partial) | tests/test_localization.lua | pass; MULTI-CLIENT with live 0.1.0 NOT-VERIFIED | 2026-11-16 |
| RF1 | Mixed-language peers converge | see R1 | OFFLINE | tests | pass | 2026-11-16 |
| RF2 | Multi-byte notes never half-cut, accepted by peers | see R7 | OFFLINE | tests | pass | 2026-11-16 |
| RF3 | Missing translation/unknown locale never nil | `locale: missing translations ...` | OFFLINE | tests | pass | 2026-11-16 |
| RF4 | Placeholder mismatch caught | `locale files: translations keep exactly the placeholders` | OFFLINE | tests | pass | 2026-11-16 |
| RF5 | Client language switch keeps recipes | `scanner: records id/loc, upgrades ..., survives a client language switch` | OFFLINE | tests | pass | 2026-11-16 |
| RF6 | Hostile id/loc/name rejected | `store: hostile id / loc / name fields are rejected` | OFFLINE | tests | pass | 2026-11-16 |
| LOAD | All files load in TOC order for live and dev identities | `load: ...` (2 tests); mutation check (remove Names from the TOC -> 2 failures) | OFFLINE | tests/test_load.lua | pass; stubs only, not the real client | 2026-11-16 |

## In-game checklist (things only the user can do)
- [ ] `/reload` with the dev addon, no Lua error on login (`/console scriptErrors 1`).
- [ ] Open the cooking window once, then `/tsd i18n` and paste all lines. Expected: `profession Kochkunst id=185 | static name: Kochkunst`, a `professionID=...` line, and for 3 recipes the window name equal to the spell name.
- [ ] `/tsd`: window opens; German client shows German labels (Rezepte, Bestellungen, ...); no clipped button text; the profession filter lists each profession once.
- [ ] `/tsd locale enUS`, `/reload`, `/tsd`: English labels; then `/tsd locale auto`, `/reload`: German again.
- [ ] Request a recipe with a long note of umlauts (about 40 characters): the order appears, the note shows without broken characters, and the note box stops at 80 bytes.
- [ ] Search "KÜRSCH" and "kursch" both find Kürschnerei recipes.
- [ ] (needs a second player) a guildmate on another client language and one on live 0.1.0 both appear with one Cooking entry. Impossible with the dev prefix: use two live-prefix builds.

## Accepted gaps
- none yet

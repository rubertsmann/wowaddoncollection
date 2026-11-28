# 042 Companion nicknames: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-27 07:38 | PLAN | Feature created
- Did: scaffolded `features/042-companion-nicknames/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-27 07:38 | PLAN | Spec written, size estimate
- Did: read the roster code (AzeCaught.lua freshCompanion/sanitizeCompanion/BuildSection), the arena fighter build and cleaner (Arena.lua:211/:258), and every display site of `companion.n`/`fighter.n`; filled spec.md (R1-R6, T1-T6, RF1-RF5)
- Result: small-to-medium feature: 6 tasks (3 S, 3 M); additive data field (schema stays 3) and additive wire field `nk` (protocol 1.7 if shipped with 041)
- Evidence: spec.md
- Next: user answers the open questions (guild-visible?, ship with 041?, 24 bytes?), then T1 tests first

## 2026-11-27 07:40 | DECISION | Nickname in fights, species on hover, ids as reference
- Did: user decided fights show the nickname with the original species name on hover, and ids are always the reference point; spec gained R3a, R3b, T5b (fight history stores npc ids + nk instead of name text, Arena.lua:1059) and RF6 (duplicate nicknames)
- Result: guild-visible nicknames confirmed; remaining open: ship with 041 or after, 24-byte limit
- Evidence: spec.md Decisions
- Next: answer the two remaining questions (defaults: build on top of 041 in 0.12.0, 24 bytes), then T1 tests first

## 2026-11-27 07:43 | PLAN | Name sweep, catch origin added
- Did: swept Core/, UI/, Locales, tests for every copy/store/display of the species name; added the sweep table to spec.md; added R7/R8 (catch time `ct` + uiMapID `cm`, zone name resolved at display), T5c/T5d, RF7/RF8
- Result: no static files or helpers keyed by name; lookups already use uid/npc. Name-bound spots: sanitizeCompanion (drops unknown fields), roster sort, fight history text, dev dummy suffix, ~15 display sites. No per-companion catch time/place exists today (only per-species first/last seen), so old companions get "unknown"
- Evidence: spec.md "Sweep" table
- Next: answer open questions (origin guild-visible?, ship with 041?, 24 bytes), then T1 tests first

## 2026-11-27 08:01 | DECISION | Origin local only, ship with 041, 24 characters, info sub-table
- Did: user answered: catch origin only for me; ship in 0.12.0 with 041 (protocol stays 1.7); max 24 characters; the nickname sits with the catch facts (one `info = { nick, at, map }` per companion)
- Result: no open questions
- Evidence: spec.md Decisions
- Next: T1 tests first

## 2026-11-27 08:01 | BUILD | T1-T6 implemented
- Did: AzeCaught.lua (info sub-table, NormalizeNickname/CleanNickname/CleanInfo/ShownName/SpeciesName/HasNickname/SetNickname/CatchOrigin, origin stamped in recordCatch, nk in BuildSection + cleaner, sanitizer keeps info, roster sort by shown name); Arena.lua (fighter nk + cleaner, history mi/mk/ti/tk, dummy as nickname "Dummy n"); Api.lua (PlayerMapID, MapName); Catcher.lua (map in throw/trap targets, /gg caught name, Catcher.Rename, shown name in chat); Model.lua (rows with species/nicknamed/origin, CatchOriginText); UI: AzeCaughtPanel (rename button + edit box, ShowCompanionTooltip, roster row tooltip, confirms), TeamDialog (AddFighterName, row tooltip, card), ArenaView (team line, replay name + hover, event lines), PetView, Window minimap tooltip; deDE 9 strings; README, CHANGELOG, docs/protocol.md, Init.lua protocol comment
- Result: suite green; UI files compile (luajit -bl)
- Evidence: `luajit tests/run.lua` -> 215 passed, 0 failed (baseline 198)
- Next: VERIFY in game (verify.md checklist), then the two-client row

## 2026-11-27 08:01 | DEVIATION | Origin in tooltips, dummy nickname
- Did: the origin is shown in the tooltips (name hover, roster rows, team picker rows), not as a new panel line, because the companion view has no free line. The dev dummy's " (Dummy)" suffix became the nickname "Dummy 1..3". Spec R8 and Decisions updated
- Result: spec matches the code
- Evidence: spec.md
- Next: in-game checklist in verify.md (user)

## 2026-11-27 08:01 | BLOCKED | In-game and two-client checks
- Did: wrote the in-game checklist (verify.md)
- Result: R3, R3a, R4, R8 (UI), RF4, RF8 and the two-client R5 row need the game
- Evidence: verify.md
- Next: user runs the checklist with the dev build (`powershell tools/deploy.ps1`) and reports; then set rows and move to done

## 2026-11-27 08:19 | BUILD | T4b Rename button in Collection > Caught, naming once
- Did: user asked for a Rename button for the selected roster companion, shown only without a nickname, replaced by a box with tick and cross; the tick renames and sets everything up. AzeCaught.SetNickname now refuses "named" and "empty"; new CanRename and ClearNickname; Catcher.Rename returns the refusal line and Catcher.RenameRefusalText; dev /ggd caught unname; AzeCaughtPanel: RefreshRosterRename (hooked into the switch/release refresh), Start/Confirm/CancelRosterRename and the editor under the list; the companion-view name click is once-only too; deDE strings; README, CHANGELOG, spec R1/R4, doc.md, verify.md
- Result: suite green, files compile
- Evidence: `luajit tests/run.lua` -> 217 passed, 0 failed
- Next: in-game checklist in verify.md (user)

## 2026-11-27 08:26 | DEVIATION | Rename button under Make companion
- Did: user asked to place Rename below Make companion. UI/AzeCaughtPanel.lua: the column is now Make companion (-258), Rename (18 px), Release (18 px), each in its own slot; the edit box with tick and cross takes the Rename slot and reaches 190 px to the left under the list; the status line moved to -328 and the hint to -342. spec R4, README, verify.md updated
- Result: suite green, file compiles
- Evidence: `luajit tests/run.lua` -> 217 passed, 0 failed
- Next: in-game checklist in verify.md (user), check that the status line and hint still fit the 376 px stage

## 2026-11-27 08:28 | DEVIATION | Rename button above Make companion
- Did: user asked to move Rename above Make companion. Column is now Rename (-258, 18 px), Make companion (22 px), Release (18 px), each in its own slot; editor stays in the Rename slot; status/hint positions unchanged (-328/-342). spec R4, README, verify.md updated
- Result: suite green, file compiles
- Evidence: see the TEST line below
- Next: in-game checklist in verify.md (user)

## 2026-11-27 08:28 | TEST | Suite after the button move
- Did: ran the offline suite and compiled UI/AzeCaughtPanel.lua
- Result: green
- Evidence: `luajit tests/run.lua` -> 217 passed, 0 failed; `luajit -bl UI/AzeCaughtPanel.lua` ok
- Next: in-game checklist in verify.md (user)

## 2026-11-27 08:30 | NOTE | Released in 0.12.0
- Did: cleanup (line endings back to LF, one nickname lookup helper in AzeCaught), released with 041 as GuildGames 0.12.0 (protocol 1.7, schema 3)
- Result: status stays verifying until the in-game rows are checked
- Evidence: `luajit tests/run.lua` -> 217 passed, 0 failed
- Next: in-game checklist in verify.md (user)

## 2026-11-28 11:55 | DONE | closed at the status review
- Did: user reviewed the feature's state
- Result: status done
- Evidence: user: "works" (2026-11-28)
- Next: none

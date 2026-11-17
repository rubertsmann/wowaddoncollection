# 014 Guild game base: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-17 12:02 | PLAN | Feature created
- Did: scaffolded `features/014-guild-game-base/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-17 12:05 | DECISION | Scope, shape, hidden info, theme
- Did: asked the user 4 questions after an online survey of WoW card/board game addons and animation APIs (AnimationGroup, OnUpdate, LibAnimate, PlayerModel)
- Result: base + tiny demo game; async guild-wide; open information only; theme decided later (feature 015)
- Evidence: answers recorded in spec.md "Decisions"
- Next: write spec.md

## 2026-11-17 12:06 | PLAN | Spec written, incl. offline testing layers
- Did: filled `features/014-guild-game-base/spec.md`: R1-R9, design (new `Core/Play/`, `UI/Animate.lua`, `UI/GamesTab.lua`, protocol 2.3, schema 4), testing layers L1-L5, T1-T11, RF1-RF6, cross-cutting checklist
- Result: plan ready for user review; no code changed
- Evidence: n/a
- Next: user reviews spec.md and answers the 2 open questions (demo name, week vs day); then T1 (Random.lua + tests)

## 2026-11-17 12:20 | PLAN | Animation study + local UI preview idea
- Did: desk research on WoW animation APIs (AnimationGroup types, easing, looping, FlipBook, pitfalls, LibAnimate, OnUpdate); scanned the local Forever install (no exported Blizzard UI, fonts are .slug, Auctionator/LibDBIcon use Rotation/Alpha); wrote `evidence/animations-research.md` with probe questions P1-P8; T7 rewritten to answer them; local-preview proposal added to spec "Open questions"
- Result: nothing verified in game; Forever build 1.60.1 (69913) suggests the retail-era API
- Evidence: `features/014-guild-game-base/evidence/animations-research.md`
- Next: user decides (a) local preview as separate feature 015 with LÖVE vs Python, (b) demo name + week/day; optionally export Blizzard UI code/art at the login console. Then T1.

## 2026-11-17 12:45 | DECISION | Demo game = coin flip with gold stake
- Did: user chose an animated coin flip where the player enters gold; every win/loss amount shows on the leaderboard. Defaults recorded in spec section 9: house opponent 50/50, gold is bookkeeping only (never read or moved), self-reported results validated for shape/bounds/consistency, ISO-week + all-time leaderboard
- Result: Rune Flip, shared seed and replay verification dropped
- Evidence: spec.md section 9
- Next: rewrite spec for hand-off

## 2026-11-17 12:50 | PLAN | Spec complete for hand-off to an implementing agent
- Did: rewrote `spec.md` (read-me-first, R1-R11, file table with insert points, data/wire shapes, pure API, coin pose math, sync 2.3 + coalesced HELLO, Animate helper, tab layout, locale strings, test cases, T1-T12, RF1-RF6, checklist); filled `verify.md` rows and the in-game checklist
- Result: plan ready; no code changed
- Evidence: baseline `luajit tests/run.lua` -> 209 passed, 0 failed
- Next: start T1 (`Core/Play/Games.lua` + `tests/test_games.lua`); T6 probe can be built early and handed to the user to run in game

## 2026-11-17 13:00 | BUILD | T1-T5 pure layer
- Did: `Core/Play/Games.lua`, `Core/Play/CoinFlip.lua` (TOC + `tests/run.lua`), `tools/coinflip.lua`; Store schema 4 (migration 3, re-validation, clean/reset/prune/canonicalize for `games`); Sync 2.3 (`grev`, `WANTG`, `GAMES`, `RECORD_KINDS.games`), `PROTOCOL_MINOR = 3`, `Communication.RequestHelloSoon` + `SendDueHello` in the pump, `GAMES_CHANGED` event, `Api.Random/CoinSoundKit/PlaySound`; Model leaderboard/feed/winner rows. Tests: `test_games.lua`, `test_coinflip.lua`, `test_games_sync.lua`, `test_games_model.lua`, `test_hardening.lua` (+2), `test_offers.lua` (schema expectation = `Store.SCHEMA`)
- Result: pure layer done; one test expectation corrected (10 flips/min -> 3 HELLOs, see spec Decisions), soak quiet phase lengthened to cover the retry schedule
- Evidence: `luajit tests/run.lua` -> 234 passed, 1 failed (only the stale generated dev TOC); `luajit tools/coinflip.lua H 2000` -> heads 47.25%, record valid for peers: true
- Next: client side T6-T10

## 2026-11-17 13:00 | DEVIATION | T7 before the T6 probe answers; small API additions
- Did: built `UI/Animate.lua` with fallbacks for every effect before the in-game probe ran; spec section 9 lists all deviations (new test file, extra helpers, Store housekeeping for `games`, Games tab built inside `Log.Protected`)
- Result: spec updated in the same step
- Evidence: spec.md section 9, last entry
- Next: T8-T10

## 2026-11-17 13:00 | BUILD | T6-T10 client side
- Did: `UI/Window.lua` tab list (`tabDefinitions()`), `UI.Widgets` export, `UI.CurrentTab`, Games tab frame; `UI/Animate.lua`; `UI/GamesTab.lua`; deDE strings; TOC (`UI\Animate.lua`, `UI\GamesTab.lua` after `UI\Window.lua`); `UI/DevProbe.lua`: `DevProbe.AnimationProbe` (P1-P8 + texture/sound check), `/tsd anim`, `/tsd anim speed <x>`, `/tsd game sim <n>`; `tests/test_games_ui.lua` (7, recording widget stub), `tests/test_load.lua` (games tab + dev commands); `powershell tools/deploy.ps1` regenerated `TalentShare-Dev.toc`
- Result: everything builds and runs against stubs for both identities
- Evidence: `luajit tests/run.lua` -> 242 passed, 0 failed (6 runs)
- Next: T11 docs

## 2026-11-17 13:00 | DOC | T11
- Did: `docs/protocol.md` section 9 (2.3 + schema 4; version source is now section 10), README (Games tab, Core/Play, trust model), CHANGELOG (Unreleased), `docs/status.md`, `doc.md`; verify.md rows filled (OFFLINE where the suite proves it); INDEX + spec status `verifying`
- Result: docs match the code
- Evidence: this commit's diff
- Next: see BLOCKED below

## 2026-11-17 13:00 | BLOCKED | In-game probe and checklist need the user
- Did: nothing further possible offline
- Result: waiting on the user
- Evidence: verify.md "In-game checklist"
- Next (superseded by the next entry for the coin look): user: restart WoW (TOC changed), `/console scriptErrors 1`, `/tsd anim` -> send the `anim P1..P8` and `anim tex` lines + screenshots of P5/P8; then the checklist in verify.md (flips, double click, `/reload` mid-flip, `/tsd game sim 12`, `/tsd anim speed 0.25`). Then: adjust `UI/Animate.lua` to the answers, record them in `docs/api-findings.md` and the study, two clients (L5), `review-talentshare`, then `done`

## 2026-11-17 13:20 | DEVIATION | Two-sided 2.5D coin (user feedback)
- Did: user tested in game: the flip works, but the coin always shows the same gold icon (INV_Misc_Coin_01 and _02 look alike) and should be 3D. `UI/GamesTab.lua` now draws the coin from layered round-masked textures, flipped end over end: back ellipse + band = rim/thickness, face = rim ring + inner disc + emblem (heads = my portrait desaturated and tinted gold, tails = INV_Crown_01), light falls off as the face turns away, a glint near 25 degrees, a ground shadow that shrinks with height. `CoinFlip.Pose` gained `edge = sin(angle)`. A true 3D model was not used: no coin model file is known on Forever and model frames only take Alpha animations; layered textures work on any client
- Result: tests updated (both faces alternate in flight, the landing face is the outcome, width/edge are cos/sin of one angle); the probe's `tex` line now checks the mask, crown and head paths
- Evidence: `luajit tests/run.lua` -> 242 passed, 0 failed
- Next: user `/reload` (no TOC change) and flip: confirm the two faces, rim and shading look right (screenshot); then the remaining checklist in verify.md and `/tsd anim`

## 2026-11-17 15:04 | BUILD | Stakes in gold/silver/copper; commit; slot machine as a second game
- Did: (user) stakes in g/s/c: all amounts in copper, field `g` -> `c`, three stake boxes with coin icons, `Model.MoneyText`; committed 47acb0f on new branch `feature/014-guild-games` (user asked to commit before the slot machine). Then (user) slot machine as a sub-section of the Games tab with its own leaderboard: game selector + per-game panels and boards (`UI/GamesTab.lua`), `Core/Play/Slots.lua`, `UI/SlotMachine.lua`, optional `slots` section in the game record (`Games.Section/RecordPlay/EntryNet`), Model functions take a game key; TOC + `tests/run.lua` + `tools/deploy.ps1`; docs (protocol section 9, README, CHANGELOG, doc.md, spec decisions, verify R12)
- Result: slot rules 93.8% return (simulated 93.6%), 11% hit rate; everything passes offline
- Evidence: `luajit tests/run.lua` -> 254 passed, 0 failed
- Next: user: restart WoW (TOC changed: Slots.lua, SlotMachine.lua), Games tab -> Slots, spin; check reels, lines, glow, count-up, coin shower (screenshot), `/tsd anim` `tex` line for the slot icons; then the rest of verify.md

# 057 Shared model view: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> 241 passed, 0 failed
Result after work:    `luajit tests/run.lua` -> 255 passed, 0 failed

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence (output line, file, screenshot) | Result | Date |
|---|---|---|---|---|---|---|
| R1 | one module drives every shown model | test_model_view "no other file creates or drives a model frame" + planted violations; subagent grep | OFFLINE | 255 passed; planted lines reported; review: "SPLIT CLEAN: yes" | pass | 2026-11-28 |
| R2 | New(options) + bound dot functions | test_model_view (all), test_games_ui, test_load | OFFLINE | 255 passed | pass | 2026-11-28 |
| R3 | display id, else npc id; same = no-op; nil clears | "a creature loads by display id ..." | OFFLINE | 255 passed | pass | 2026-11-28 |
| R4 | one catalogue, one pick rule | "the first animation the model has ..." | OFFLINE | 255 passed | pass | 2026-11-28 |
| R5 | poses, back timers, emotes | "a load ... plays the loop again", "back to idle after an action ...", test_load care emote | OFFLINE | 255 passed | pass | 2026-11-28 |
| R6 | death once, revive | "a dead view stays dead ...", test_load arena re-watch | OFFLINE | 255 passed | pass | 2026-11-28 |
| R7 | companion views (max + mini) share sleep/ambient/reload | "a companion view sleeps ...", "ambient emote ...", "hidden view only forgets ...", test_load | OFFLINE | 255 passed; review: "REUSE GUARANTEED: yes" | pass | 2026-11-28 |
| R8 | turn, zoom memory, pad, fallback, afterLoad, RefreshAll | "the wheel zooms ...", "stand-in icon ...", "framed by their size ...", "window scaling ..." | OFFLINE | 255 passed | pass | 2026-11-28 |
| R9 | no visible change | the user started the dev build on the branch and looked at the views | IN-GAME | user: "ive started it ingame everything looks fine" | pass | 2026-11-28 |
| RF1 | async load resets the animation | "a load (also a late one) plays the loop again" | OFFLINE | 255 passed | pass | 2026-11-28 |
| RF2 | stale timer / fell asleep meanwhile | "back to idle ...", "an emote's timer after the companion fell asleep ..." | OFFLINE | 255 passed | pass | 2026-11-28 |
| RF3 | client without optional calls | "a client without the optional calls is fine", "SetScript or HookScript fails" | OFFLINE | 255 passed | pass | 2026-11-28 |
| RF4 | re-watched fighter stands | test_load arena "a re-watched fighter is alive" | OFFLINE | 255 passed | pass | 2026-11-28 |
| RF5 | hidden view during scale change | "window scaling frames shown views again, hidden ones on their OnShow" | OFFLINE | 255 passed | pass | 2026-11-28 |

## In-game checklist (things only the user can do)
- [ ] Restart the game (new file in the TOC). Companion view: model loads, idle/asleep pose, a care button plays its emote then idle, right-drag turns, wheel zooms
- [ ] Pet view (mini view): model shown, clicks and drag still work on it (it must not take the mouse), sleeps/wakes with the companion
- [ ] Collection > Caught preview and Guild preview: models load, hover shows the info panel
- [ ] Arena: watch a fight: both fighters stand ready, attack/hurt, the loser dies and lies; watch it again: both stand
- [ ] Team dialog: carousel models face each other
- [ ] Companion Dash (runner + monsters run, jump, hurt) and Survivor (companion in the tower, attacks, back to ready)
- [ ] `/gg caught model` twice: one probe, hidden 15 s after the last call; `/ggd caught emote`: an emote within a second
- [ ] Any Lua error: `/gg caught log 20 model` and `/gg debug`

## Accepted gaps
- Checklist items not named one by one (arena re-watch, `/ggd caught emote`): covered OFFLINE (test_load re-watch, test_model_view forced emote); the user asked to merge and release after the in-game look (2026-11-28).

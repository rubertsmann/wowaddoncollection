# 020 Companion arena: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-21 01:43 | PLAN | Feature created
- Did: scaffolded `features/020-companion-arena/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-21 01:58 | BUILD | arena built (T1-T5)
- Did: user: "using the skill create a fully new async battle system for the companion - use the stats system and level system and make them trainable - keep track of wins and loss - let them bet - let them bet against who is winning let the person who has been requested accept or decline the fight. Implement depth but fully hands off auto battler", then "dont stop till the fighting system is fully implement" (decisions in spec.md). New Core/Minigames/Arena.lua (fighter, training, levels, deterministic battle with 9 abilities, odds, record section + sanitizer, challenge/answer/bet/settle, persistence), UI/ArenaView.lua (Fighter and Fights pages, replay with models, health bars, floating damage, shakes, burst). Core/Data/Games.lua: SetSection("arena"), arena dropped alone. Core/Game/Catcher.lua: ArenaTick every 5 s (training done, settlement, chat notices), PublishArena, /gg arena. UI/AzeCaughtPanel.lua: 4th tab, Challenge box + arena W/L in the Guild view, Panel.CreateModel/ShowModel shared. Init: protocol 1.2. TOC: Arena.lua, ArenaView.lua. deDE: 98 keys. Balance pass (see Decisions). Docs: doc.md, verify.md, protocol.md, README, CHANGELOG, INDEX. Ran deploy.ps1 (dev TOC).
- Result: built; offline verified; needs the game and a second player.
- Evidence: luajit tests/run.lua -> "133 passed, 0 failed" (new tests/test_arena.lua: 7 tests; test_load drives the arena view: train, accept, watch, steps, tick + settlement)
- Next: user: restart the game (TOC changed), run the in-game checklist in verify.md; then a fight with a guild member on this build (MULTI-CLIENT row).

## 2026-11-21 02:01 | BLOCKED | in-game and two-player verification
- Did: everything that can run offline is built and tested (afe97cb). The remaining verify.md rows (R9-R11 look in game, MC two real players) need the WoW client and a second guild member; Claude cannot start or drive the game. The requested PC sleep timer was refused by the permission check (not worked around).
- Result: waiting on the user.
- Evidence: luajit tests/run.lua -> "133 passed, 0 failed"
- Next: user: restart the game, run the in-game checklist in verify.md (/ggd arena, train, challenge a guild member on this build, accept, bet, watch); report or /reload so the journal (arena.* lines) can be read from SavedVariables.

## 2026-11-21 06:53 | DEVIATION | guild view fight rework (challenge modal) and dev dummy (R10, R12)
- Did: user feedback: the guild view's wager box, Challenge button and status overlapped. `UI/AzeCaughtPanel.lua`: a click selects a pet (selected highlight), one fight icon on the preview model (only for another member's pet, pulses in), `Panel.SelectGuildRow`, `Panel.Challenge` opens the modal; the old box/button are gone. `UI/ArenaView.lua`: `BuildChallenge`/`OpenChallenge`/`ShowChallengeStep`/`ChallengeNext`/`ChallengeBack`/`ReadWager`/`SetWager` (matchup, wager presets + custom, confirm, sent; step track; shake on a refusal). `Core/Minigames/Arena.lua`: `DummyRecord`, `DummyRespond`, `DummyChallenge`; Settle no longer refunds a settled fight. `Core/Game/Catcher.lua`: dev `/ggd arena dummy [off]`, `/ggd arena request [gold]` (also under `/ggd caught`), the dummy answers on the arena tick. 18 deDE keys; the unused "Challenge" key removed. Tests: dummy flow + refund guard (test_arena), modal steps and the fight icon (test_load; the widget stub now keeps text).
- Result: offline suite green.
- Evidence: luajit tests/run.lua -> "134 passed, 0 failed"
- Next: user: /reload (no TOC change), `/ggd arena dummy`, AZEcaught > Guild: click the dummy, the fight icon, go through the modal; `/ggd arena request 1` and accept under Arena > Fights; watch after 5 minutes. Then the in-game rows in verify.md.

## 2026-11-21 07:20 | BUILD | one fight at a time, Stop a challenge, dummy button (R13, R12)
- Did: `Core/Minigames/Arena.lua`: `Arena.Busy`; Challenge refuses "busy"/"theybusy", Answer(accept) refuses "busy"; `Arena.Withdraw` (`ch.wd`, sanitized, an answer counts only before it; state "withdrawn"); Settle refunds the challenger and a late accepter once, and takes a refund back when an earlier accept turns up; the dummy ignores stopped challenges; `MAXIMUM_OPEN` removed. `UI/ArenaView.lua`: Accept/Decline/Stop buttons in each fight row, Stop in the details, "stopped" state, refusal texts, the challenge modal checks busy at step 1, dev button "[dev] Dummy challenges me" (`Catcher.DevArenaRequest`). docs/protocol.md, doc.md, spec.md (R13), 5 deDE keys (+1 removed).
- Result: offline suite green.
- Evidence: luajit tests/run.lua -> "136 passed, 0 failed"
- Next: user: /reload; Arena > Fights: "[dev] Dummy challenges me", Accept in the row; challenge the dummy from the Guild view, Stop it in Fights; then the in-game rows in verify.md.

## 2026-11-21 07:35 | BUILD | tick / X icons instead of Accept/Decline and Yes/No
- Did: user: "replace annehmen oder ablehnen with X or tick icons on the whole addon". `UI/Window.lua`: `Widgets.CreateIconButton(parent, "accept"|"decline", size, tooltip, onClick)` (ReadyCheck tick / X, hover tint, grey when disabled, the word in the tooltip). Used for the arena row and detail Accept/Decline and the companion switch Yes/No (`UI/AzeCaughtPanel.lua`); those were the only accept/decline buttons in GuildGames.
- Result: offline suite green.
- Evidence: luajit tests/run.lua -> "136 passed, 0 failed"
- Next: user: /reload and look at the icons (Arena > Fights with "[dev] Dummy challenges me"; Collection > Make companion).

## 2026-11-21 07:50 | BUILD | dev icon tools: dummy challenge and fight now
- Did: user: "replace the dev dummy challenge me with a button icon that indicates debug add - also add a button to reduce the timer there for the anticipated fight". `UI/Window.lua`: icon kinds "debug" (wrench) and "skip" (stopwatch) with a "dev" tag; `UI/ArenaView.lua`: both icons bottom left of the Fights page (dev build only, tooltips). `Core/Minigames/Arena.lua`: `Arena.SkipDummyWait` / `Arena.skipped` (memory only, only fights with the dummy: decided now). `Core/Game/Catcher.lua`: `/ggd arena skip`, `Catcher.DevArenaSkip`.
- Result: offline suite green.
- Evidence: luajit tests/run.lua (see the commit)
- Next: user: /reload; Arena > Fights: wrench, tick, stopwatch, Watch.

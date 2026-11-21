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


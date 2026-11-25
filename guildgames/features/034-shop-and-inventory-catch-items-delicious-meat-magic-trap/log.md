# 034 Shop and inventory: catch items (Delicious Meat, Magic Trap): log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-25 09:37 | PLAN | Feature created
- Did: scaffolded `features/034-shop-and-inventory-catch-items-delicious-meat-magic-trap/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-25 09:40 | PLAN | Spec written
- Did: spec.md filled (R1-R10, design, T1-T7, review focus, checklist); user answered 4 questions (two tabs, normal reward with Meat 50g / Trap 500g, traps in three versions, target-frame anchor)
- Result: plan ready; Elite/Rare trap prices (1000g/1500g) are a proposal
- Evidence: spec.md Decisions
- Next: user reviews the plan; then T1 (Items.lua catalog, inventory, buy, boosts, sanitize) with tests/test_items.lua

## 2026-11-25 09:43 | PLAN | Item skill planned
- Did: user asked to plan a skill for adding new items; spec.md gains R11, T8 and the "Item skill (T8)" section (skill .claude/skills/guildgames-new-item, catalog guard test, RED/GREEN subagent runs)
- Result: planned; the skill is written after T1-T4 so it describes the real Items.lua
- Evidence: spec.md
- Next: user reviews the plan (open: Elite/Rare trap prices, the meat reward); then T1

## 2026-11-25 10:05 | DECISION | Open questions taken at the proposal
- Did: user said "go ahead and integrate it"; Elite trap 1000g, Rare trap 1500g, the meat pays the normal reward (spec Decisions)
- Result: assumption logged; still listed under Open questions for the user
- Evidence: spec.md Decisions
- Next: build T1-T6

## 2026-11-25 10:05 | BUILD | T1-T6 built
- Did: Core/Minigames/Items.lua (new), AzeCaught.lua (recordCatch shared, TrapCatch, boost in Throw/OnDeath, sanitize, reset, icon setting atTarget), Core/Game/Api.lua (TargetFrameAnchor), Core/Game/Catcher.lua (UseTrap, target-frame mode, TargetIcon, UpdateCatchItems), UI/Helpers.lua (MouseOver, CloseOnClickAway; PetView uses it), UI/ShopView.lua (new), UI/CatchItems.lua (new), UI/AzeCaughtPanel.lua (5 tabs), UI/AzeCaughtOptions.lua (At the target frame), GuildGames.toc, Locales/deDE.lua, tests/test_items.lua (new), tests/test_load.lua, tests/run.lua; tools/deploy.ps1 run (dev TOC)
- Result: `luajit tests/run.lua` -> `159 passed, 0 failed`
- Evidence: test output; simulator 0 Lua errors; evidence/sim-shop.png, evidence/sim-target.png (sim found the owned count covering Buy, and fractional seconds on the clock: both fixed)
- Next: T8 skill, docs, simulator GUI for the user

## 2026-11-25 10:05 | DOC | Skill and docs
- Did: .claude/skills/guildgames-new-item/SKILL.md (monorepo root); README, CHANGELOG (Unreleased), doc.md, verify.md
- Result: T8 written; its RED/GREEN subagent runs are not done
- Evidence: files
- Next: user tests in the simulator GUI (evidence/sim-shop.lua, scenario "all"), then in game (verify.md checklist); open: trap prices, meat reward, T8 runs

## 2026-11-25 10:08 | DEVIATION | Tabs as icons
- Did: user: "the tabs overlapping a little bit replace the tab names with icons and hover for text"; UI/AzeCaughtPanel.lua: the five view buttons show an icon (VIEW_ICONS), the name as tooltip, unselected icons dimmed
- Result: `luajit tests/run.lua` -> `159 passed, 0 failed`; simulator 0 Lua errors, tabs no longer overlap
- Evidence: simulator screenshot (tabs row)
- Next: user tests in the simulator GUI / in game (verify.md checklist)

## 2026-11-25 10:12 | NOTE | AZEcaught first in the game switch
- Did: user: "on the overview move the companion tab as the first item and the games stay behind it"; UI/GamesTab.lua switchOrder puts "caught" first, then Games.ORDER; README line updated
- Result: `luajit tests/run.lua` -> `159 passed, 0 failed`; simulator 0 Lua errors, header shows the paw icon first
- Evidence: simulator screenshot (header row)
- Next: user tests in the simulator GUI / in game (verify.md checklist)

## 2026-11-25 10:18 | BUILD | /ggd caught setup
- Did: user: "do it for debugging it is easier to have one base command that sets everything up for dev"; Core/Game/Catcher.lua developmentCommands.setup [items|boost] (test companion if none, 3000g, 3 of every catalog item, boosters with "boost", window on the Shop tab); tests/test_load.lua runs all three forms; README dev line
- Result: `luajit tests/run.lua` -> `159 passed, 0 failed`
- Evidence: test output
- Next: user: in the dev build `/ggd caught setup`, then the verify.md checklist

## 2026-11-25 10:39 | NOTE | Release 0.8.0
- Did: user: "clean commit push create new version"; version 0.8.0 (TOC, dev TOC, Init), CHANGELOG, RELEASE_NOTES (EN/DE)
- Result: `luajit tests/run.lua` -> `159 passed, 0 failed`
- Evidence: test output
- Next: user: in-game checklist in verify.md (`/ggd caught setup` first); T8 RED/GREEN skill runs; open: trap prices, meat reward

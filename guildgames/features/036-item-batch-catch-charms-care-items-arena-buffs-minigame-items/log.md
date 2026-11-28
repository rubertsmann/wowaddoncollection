# 036 Item batch: catch charms, care items, arena buffs, minigame items: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-25 14:31 | PLAN | Feature created
- Did: scaffolded `features/036-item-batch-catch-charms-care-items-arena-buffs-minigame-items/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-25 14:31 | PLAN | Spec from the 10 answers
- Did: filled spec.md with 13 items in 4 new groups, prices, requirements R1-R6, tasks T1-T9 and protocol 1.5 (`bf`, `it`). Recorded the answers under Decisions.
- Result: plan ready. Two open questions: the bomb price against Survivor stakes, and confirming the prices.
- Evidence: n/a
- Next: user answers the open questions; then T1 (catalog, charm kind, Equip)

## 2026-11-25 15:03 | DECISION | Plan accepted
- Did: the user accepted the plan ("looks fine"); prices will be tuned later. The bomb works only in runs with a stake of at most 250g (the recommendation).
- Result: build started
- Evidence: n/a
- Next: T1-T6 core logic

## 2026-11-25 15:03 | BUILD | T1-T6, T8 core logic and tests
- Did: Core/Minigames/Items.lua (13 items, groups charms/care/arena/games, kinds charm/care/arenaBuff/runner/survivor, the charm slot, arena buff charges, sanitize); AzeCaught.lua (BestHealth, CharmRewardFactor, second roll, CareItem, the Elixir pauses the decay); Arena.lua (buffs baked into Fighter, bf, SanitizeBuffs, spent on challenge/answer/counter); Runner.lua (shield, head start, it/bi marks); Survivor.lua (Bomb, bombed); Games.lua (it on plays, RecordPlay usedItem); protocol MINOR 5; deDE; tests/test_item_batch.lua (9 tests), catalog guard kinds
- Result: core done
- Evidence: luajit tests/run.lua -> "180 passed, 0 failed"
- Next: T7 UI (shop groups, charm slot, runner toggles, bomb button, arena buff icons, board marks)

## 2026-11-25 15:11 | BUILD | T7 UI, T9 docs
- Did:
  - UI/Helpers.lua: CreateItemButton.
  - UI/ShopView.lua: the charm slot header, Equip/Take off, using care and arena items, refusal texts.
  - UI/RunnerView.lua: Dash Shield and Head Start toggles beside Start, the "Shield!" float text, the result line for item runs.
  - UI/SurvivorArena.lua: the bomb button bottom left during a run.
  - UI/ArenaView.lua: buff icons on the fighter line, the level line and the challenge.
  - UI/GamesTab.lua and Core/View/Model.lua: the bag mark on boards and feeds.
  - Docs: deDE, README, CHANGELOG Unreleased, docs/protocol.md "Item marks" (1.5), doc.md, verify.md.
- Result: feature built; status verifying
- Evidence: luajit tests/run.lua -> "180 passed, 0 failed". Simulator (tools/wow-sim.ps1 -Mode shot, evidence/sim-items.lua): 0 GuildGames Lua errors in four scenarios; evidence/sim-inventory.png, sim-shop.png, sim-runner.png, sim-survivor.png.
- Next: the user runs the in-game checklist in verify.md (and one fight against a 0.9.1 client if possible); then done and release 0.10.0

## 2026-11-25 15:41 | DEVIATION | Second Chance: a second throw instead of a 10% re-roll
- Did: user test: "second chance doesnt work the icon disappears". When the 3 s window runs out before the death, the rope icon goes away and the enemy counts as rolled, so the 10% re-roll never helped there. Changed:
  - Core/Minigames/AzeCaught.lua: EndLateThrows marks a slipped first rope as `again` (not rolled, thrown cleared), so the next Throw is allowed and marked `second`; the re-roll in OnDeath is removed; the `again` memory expires after 600 s and is cleared by reset.
  - Core/Game/Catcher.lua: Catcher.OnSecondChance prints "Second Chance: throw once more at {name}." and brings the icon back.
  - Items.lua effect text, deDE, README, spec, doc.
- Result: one more throw per enemy with the charm; without it, unchanged
- Evidence: luajit tests/run.lua -> "180 passed, 0 failed" (test "charm effects on catches (... second throw)")
- Next: user re-tests Second Chance in game (/reload), then the rest of the in-game checklist in verify.md

## 2026-11-25 16:45 | NOTE | Released as GuildGames 0.10.0 on user request
- Did: version 0.10.0 in GuildGames.toc, GuildGames-Dev.toc and Init.lua; CHANGELOG section; RELEASE_NOTES.md (EN/DE); INDEX row without "unreleased".
- Result: released before the in-game checklist in verify.md was run; status stays verifying.
- Evidence: release commit and tag guildgames/v0.10.0
- Next: user runs the in-game checklist in verify.md (incl. Second Chance: the rope icon comes back once after it slipped); then set done.

## 2026-11-28 11:55 | DONE | closed at the status review
- Did: user reviewed the feature's state
- Result: status done
- Evidence: user: "shows and helps and works" (2026-11-28)
- Next: none

# 019 Code structure like TalentShare: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-20 21:48 | PLAN | Feature created
- Did: scaffolded `features/019-code-structure-like-talentshare/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-20 21:55 | PLAN | spec filled from the comparison with TalentShare
- Did: spec.md R1-R7, T1-T8, Review Focus, decisions (Minigames folder, one Model.Duration, branch refactor/guildgames-structure). User: "implement everything and then continue with this work".
- Result: plan recorded; baseline luajit tests/run.lua -> "116 passed, 0 failed"
- Evidence: features/019-code-structure-like-talentshare/spec.md
- Next: T1

## 2026-11-20 22:05 | BUILD | T1 folders like TalentShare
- Did: git mv Core/*.lua into Core/{Base,Data,Game,Minigames,Net,View}; Core/Library.lua split into Core/Base/Utility.lua, Core/Base/Log.lua, Core/Base/Locale.lua (+ /gg locale moved here from Events, as in TalentShare), Core/Debug/Trace.lua, Core/Net/Codec.lua, Core/Net/Guard.lua; event bus made in Core/Game/Events.lua (no load-time On/Fire before it). GuildGames.toc regrouped; tests/run.lua PURE_FILES; tests/test_load.lua and tests/test_store_and_locale.lua file patterns accept subfolders ([%w_/]+, they skipped nested files before); tools/coinflip.lua file list; path comments, Bindings.xml, docs/protocol.md.
- Result: same behaviour; GuildGames-Dev.toc regenerated with tools/deploy.ps1 (test_load caught it as stale first).
- Evidence: luajit tests/run.lua -> "116 passed, 0 failed"; luajit tools/coinflip.lua H 200 -> "200 flips of 2s 50c: heads 53.50% ..."
- Next: T2 module guards

## 2026-11-20 22:15 | BUILD | T2 no needless module guards
- Did: removed guards on modules the TOC guarantees: Core/Data/Store.lua (AzeCaught), Core/Game/Catcher.lua (AzeCaughtPanel), Core/Game/Events.lua OnActionBlocked (AzeCaught x2), Core/Minigames/AzeCaught.lua (Store x3, Log, Print, TITLE), Core/Minigames/Survivor.lua (Store), UI/AzeCaughtOptions.lua (Catcher x2, TITLE), UI/DevProbe.lua (Survivor, GamesTab), UI/GamesTab.lua (Utility.ShortName, SlotMachine, SurvivorArena, AzeCaughtPanel x2), UI/Window.lua (AzeCaught). Harness addon gets TITLE (as Init.lua); test_games_ui stubs AzeCaughtPanel (it does not load that file). New lint "conventions: no guard on another addon module outside the allowed exceptions" (tests/test_store_and_locale.lua) with two allowed cases: Utility.Me (Store, Api) and Init.lua's early blocked-action hook (OnActionBlocked, defined later).
- Result: the lint was red first ("Core/Base/Init.lua:103 OnActionBlocked | UI/Window.lua:480 AzeCaught"), then green.
- Evidence: luajit tests/run.lua -> "117 passed, 0 failed"
- Next: T3 Survivor duplicate might/haste, Utility.Clamp

## 2026-11-20 22:22 | BUILD | T3 Survivor copy removed, one Clamp
- Did: Core/Minigames/Survivor.lua: the first might/haste pair (a copy, shadowed by the second pair next to `area`) removed. New Core/Base/Utility.lua `Utility.Clamp(value, lowest, highest)` (NaN -> lowest); AzeCaught's local clamp is now that one; the hand-written math.max(math.min(...)) clamps in Games, Catcher (x2), AzeCaught.ProjectToScreen, CoinFlip.Pose, Survivor steer, AzeCaughtPanel.StatBar, DevProbe, GamesTab, SlotMachine, SurvivorArena use it.
- Result: same results for finite input; a NaN now becomes the lower bound instead of passing through (AzeCaught) or becoming the upper bound (math.min/max).
- Evidence: luajit tests/run.lua -> "118 passed, 0 failed" (new: "utility: Clamp limits both ends and turns NaN into the lower bound"); luajit tools/coinflip.lua H 50 runs
- Next: T4 shared UI helpers

## 2026-11-20 22:35 | BUILD | T4 shared UI helpers
- Did: new UI/Helpers.lua (first UI file in the TOC): `UIHelpers.Settings()`, `UIHelpers.SetTextureOr(texture, path, fallbackPathOrColor)`, `UIHelpers.FrameLevel(frame)`. New `Api.PlaySoundNamed(soundNames)` (Core/Game/Api.lua). Replaced: play() copies in SlotMachine/SurvivorArena (with their needless SOUNDKIT/SoundKitFor guards), frameLevel() copies, texture fallbacks (GamesTab.setTextureOr, SurvivorArena.iconOr, Animate.texturedOrColor's first line, inline in SlotMachine, GamesTab, AzeCaughtPanel x2, AzeCaughtOptions, Window x2, Catcher x2), settings() copies in Window/GamesTab/AzeCaughtPanel, GamesTab.Money/GamesTab.Settings re-exports (SlotMachine, SurvivorArena use Model.MoneyText / UIHelpers.Settings). One-line wrappers money/me/now are aliases now; Catcher's chat() was addon.Print. test_games_ui loads UI/Helpers.lua and stubs Api.PlaySoundNamed.
- Result: 55 lines fewer in T4's first part; behaviour unchanged. Dev TOC regenerated (tools/deploy.ps1).
- Evidence: luajit tests/run.lua -> "118 passed, 0 failed"
- Next: T5 one Model.Duration, one Model.RefusalText

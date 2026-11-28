# 031 Catch refused in dungeons: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-24 23:11 | PLAN | Feature created
- Did: scaffolded `features/031-catch-refused-in-dungeons/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-24 23:15 | BUILD | T1+T2 refusal in dungeons and raids
- Did: `Api.InDungeon`, `Api.ShowOverlay` (Core/Game/Api.lua), check at the start of `Catcher.Throw` (Core/Game/Catcher.lua), deDE string, test in tests/test_load.lua; spec, verify, doc, README, CHANGELOG
- Result: party/raid refuse with overlay + chat; open world unchanged. Mutation check (InDungeon forced false) fails the new test as expected.
- Evidence: `luajit tests/run.lua` -> `147 passed, 0 failed`; mutated: `146 passed, 1 failed` ("overlay in party: nil")
- Next: T3 in game: enter a dungeon, `/gg catch` -> red line at the top + chat line; then set done

## 2026-11-24 23:30 | BUILD | T4 range and tag limits
- Did: user asked for two more limits (distance, not tagged by others) and chose 28 yards + allow when unknown. `Api.IsTapDenied`, `Api.InRopeRange` (Core/Game/Api.lua) feed `Api.UnitSnapshot`; `AzeCaught.Throw` refuses "tapped" / "range" (Core/Minigames/AzeCaught.lua); texts in Core/Game/Catcher.lua + Locales/deDE.lua; `interactRange4` added to the unit dump; asserts in tests/test_azecaught.lua
- Result: offline green; whether CheckInteractDistance answers in combat on this client is unknown (RF3)
- Evidence: `luajit tests/run.lua` -> `147 passed, 0 failed`
- Next: in game (user): T3 dungeon message, T5 range in combat (`/gg caught log 20 catch`, read `interactRange4`), tagged enemy

## 2026-11-24 23:46 | VERIFY | UI effects in wow-ui-sim
- Did: ran `tools/wow-sim.ps1 -Addon guildgames -Mode shot -NoOpen -Lua evidence/sim-catch-refusals.lua` (stubs: IsInInstance party, then a weak hostile target tagged by others, then out of range)
- Result: overlay line and all three chat lines render in Blizzard's UI; no Lua errors. (A first run hung: the script printed inside its own chat hook; fixed in the script.)
- Evidence: evidence/sim-catch-refusals.png; "sim: 0 Lua error(s) in GuildGames, 0 elsewhere"
- Next: in game (user): T3 dungeon, T5 `interactRange4` in combat, a tagged enemy

## 2026-11-28 09:53 | DONE | dungeon refusal confirmed in game
- Did: user: "doesnt work because minions cant be caught in a dungeon"
- Result: catching is refused in dungeons in the client; remaining rows closed as accepted gaps (verify.md); T5 left open
- Evidence: user report 2026-11-28
- Next: none; reopen only if the range check (T5) matters

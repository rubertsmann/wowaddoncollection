# 027 Recipe drop alerts: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-24 11:22 | PLAN | Feature created
- Did: scaffolded `features/027-recipe-drop-alerts/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-24 12:20 | BUILD | T1-T6 built
- Did: `Core/Data/RecipeDrops.lua` (new, pure), `Core/Game/Drops.lua` (new), Sync DROP/DROPA handlers + BroadcastDrop/AnswerDrop, Communication wiring and priority types, PROTOCOL_MINOR 7, `UI.SetDropNotice` + minimap tooltip, deDE strings, Dev tools triggers "Recipe drop from a member" / "Answers to my recipe drop" (removed by Remove all fake data), docs (protocol.md 15, README, CHANGELOG, status.md)
- Result: two bugs caught by the tests and fixed: RecipeDrops.Get returned false with nothing stored; "/ps drops x off" parsed to nil (and/or with false)
- Evidence: `luajit tests/run.lua` -> 310 passed, 0 failed (baseline 302); tools/deploy.ps1 regenerated the dev TOC
- Next: user: in-game checklist in verify.md (restart the game: new files), then a real drop with a second member

## 2026-11-24 11:52 | NOTE | Correction: entry time
- Did: the BUILD entry stamped 12:20 was written without reading the clock; it happened shortly before 11:47
- Result: n/a
- Evidence: `date` -> 2026-11-24 11:49
- Next: VERIFY below

## 2026-11-24 11:52 | VERIFY | Dev triggers on Forever, review
- Did: read devChecks.dropIn / dropMine and the saved log after the user's reloads; ran review-professionshare
  (review/recipe-drops.md): D1 a DROP for a non-recipe item could alert -> fixed (Drops.OnDrop requires the Recipe class)
- Result: incoming drop learnable, answer g 144 captured, alert raised; tooltip rows Cook 300 / Alchemist 280 / Skinner 265 + 1 more
- Evidence: devChecks 11:48:16 / 11:48:18; `luajit tests/run.lua` -> 310 passed, 0 failed
- Next: DONE below

## 2026-11-24 11:52 | DONE | Accepted by the user
- Did: user: "check everything commit then finalize"
- Result: done; open: a real drop and two members (accepted gaps in verify.md)
- Evidence: verify.md
- Next: none

## 2026-11-24 13:05 | BUILD | bag scan button (user request)
- Did: "Announce the recipes in my bags now" button on the settings page (UI/Alerts.lua, Recipe drops section) and `/ps drops scan`; Drops.AnnounceBags (Core/Game/Drops.lua) runs Drops.Announce for each item of RecipeDrops.BagScanList (Core/Data/RecipeDrops.lua: unique, not bound, at most MAXIMUM_DROPS), 2 s apart, one summary chat line instead of one per item; 7 deDE strings
- Result: user's question: the tooltip lines exist only for recipes from my own loot of this session; the button lets recipes already in the bags get them
- Evidence: `luajit tests/run.lua` -> 332 passed, 0 failed (new: "the bag scan announces each tradeable recipe once..."; test_load runs AnnounceBags and /ps drops scan)
- Next: in game: settings -> Recipe drops -> button with tradeable recipes in the bags; hover one (expect "Guild members who can use it:" + "Waiting for answers..." / "Nobody online can use it.")

## 2026-11-24 13:30 | VERIFY | bag scan button in game
- Did: read the dev SavedVariables after the user's report "the features are working as expected"
- Result: `drops.bagScan items=2`, both recipes `outcome=announced` (13:02); the user saw the tooltip lines
- Evidence: WTF/Account/<account>/SavedVariables/ProfessionShare-Dev.lua (log 13:02:48-13:02:50)
- Next: answers from a second member on 1.4.x

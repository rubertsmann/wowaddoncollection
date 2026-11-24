# 026 Debug fake data menu and recipe probe: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-24 10:59 | PLAN | Feature created
- Did: scaffolded `features/026-debug-fake-data-menu-and-recipe-probe/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-24 11:10 | PLAN | Spec filled
- Did: spec.md (R1-R7, RF1-RF5, checklist); scope = step 1 of recipe drop alerts: debug rework + assumption probes, in-game data only
- Result: plan approved by the user ("implement the first step so we can check for assumptions")
- Evidence: spec.md Decisions
- Next: T1

## 2026-11-24 11:10 | BUILD | T1-T4 built
- Did: `Core/Data/RecipeCheck.lua` (new, pure: PatternFromFormat, Match, ReadTooltip, Decide, ParseLoot); `Core/Game/Api.lua`
  (BagRecipeItems, RecipeCheckStrings, ItemTooltipLinesWithColor, shared hidden-tooltip reader with colours);
  `UI/DevProbe.lua` (fakeMember helper, devFake/devChecks, RemoveFakeData, RestoreFakeMembers, RecipeProbe, loot recorder,
  SimulateRecipeLoot, ENTRIES/SECTIONS, /psd fake, /psd recipeprobe; old /psd fake* commands kept as aliases);
  `UI/Window.lua` (one "Dev tools" dropdown replaces six buttons + Item probe); `Core/Game/Events.lua` (module check,
  restore fake members after load); deDE (6 keys removed, "Dev tools" added); TOC, tests/run.lua.
- Result: found and fixed a bug while testing: the client-format list used ipairs over possibly-nil arguments.
- Evidence: `luajit tests/run.lua` -> 301 passed, 0 failed (baseline 295; new tests/test_recipe_check.lua, test_load dev block)
- Next: T5 in game (checklist in verify.md), then read devChecks from WTF\...\ProfessionShare-Dev.lua

## 2026-11-24 11:30 | VERIFY | Recipe probe on Forever (deDE)
- Did: read devChecks.recipes from WTF\Account\<ACCOUNT>\SavedVariables\ProfessionShare-Dev.lua after the user's /reload
- Result: assumptions hold: the "Benötigt <Beruf> (n)" line is red (1/0.13/0.13) exactly when my skill is too low or I lack
  the profession, white when learnable; "Wird beim Aufheben gebunden" read; client strings captured (minSkill "Benötigt %1$s (%2$d)",
  loot self "Ihr erhaltet Beute: %s" without a period). Forever has its own recipe items (273098, 250989, Skinning
  requirement): no external database would know them, in-game data only was the right call.
- Evidence: 5 items, 0 mismatches, 0 unreadable; only the recipes check ran (no loot / member checks in the file)
- Next: DEVIATION below

## 2026-11-24 11:32 | DEVIATION | Last Requires line, not the first
- Did: Forever shows the created item's tooltip FIRST and the recipe's own requirement LAST; `RecipeCheck.ReadTooltip` now takes
  the last "Requires X (n)" line; test fixture reordered; regression test with the real item 274972 tooltip; spec RF1 updated
- Result: same results for the 5 probed items (their created items carry no skill line)
- Evidence: `luajit tests/run.lua` -> 302 passed, 0 failed
- Next: user: Dev tools -> "Recipe loot (me)", "Recipe loot (other player)", a Member entry, "Remove all fake data", one known recipe in the bags, /reload

## 2026-11-24 11:45 | VERIFY | Loot triggers and menu in game
- Did: read devChecks after the user's second /reload
- Result: loot (self, wouldAnnounce=true), lootOther (kind other, no name kept), remove ran (0 records: no fake member present);
  "Bereits bekannt" still not seen (no known recipe in the bags); no real recipe loot yet
- Evidence: devChecks.loot.ok=true, lootOther.ok=true, lootLines 2 simulated
- Next: build 027 recipe drop alerts on RecipeCheck; this feature stays "verifying" until a real loot line and a known recipe are seen

## 2026-11-24 11:52 | NOTE | Correction: entry times
- Did: the entries stamped 11:30, 11:32 and 11:45 were written without reading the clock (the system time was ~11:20-11:49); their order is right, their times are not
- Result: n/a
- Evidence: `date` -> 2026-11-24 11:49 when 027/029 were done
- Next: DONE below

## 2026-11-24 11:52 | DONE | Accepted by the user
- Did: in-game evidence complete for the menu, probe, fake loot, fake members; review/recipe-drops.md written
- Result: done; open: "Already known" and a real loot line (accepted gaps in verify.md)
- Evidence: devChecks read from WTF after the user's reloads; `luajit tests/run.lua` -> 310 passed, 0 failed
- Next: none

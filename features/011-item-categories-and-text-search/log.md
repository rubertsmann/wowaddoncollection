# 011 Item categories and text search: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-16 22:53 | PLAN | Feature created
- Did: scaffolded `features/011-item-categories-and-text-search/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-16 22:53 | BUILD | T1 dev item probe
- Did: UI/DevProbe.lua (new, dev build only), Item probe button on the Debug tab (UI/Window.lua), /tsd itemprobe [itemID ...], TalentShare.toc, Locales/deDE.lua; deployed (dev TOC regenerated)
- Result: stubbed-client harness run writes devProbe (apis, templates, buckets, items, spells, tradeskill) without error
- Evidence: `luajit tests/run.lua` -> 187 passed, 0 failed
- Next: user runs the probe in game (with profession windows open), /reload; read TalentShare-Dev.lua SavedVariables, then design T2-T4

## 2026-11-16 22:55 | VERIFY | T1 probe run in game
- Did: user ran Item probe in the dev build (catalog 25 recipes, 17 sampled, 12 buckets), /reload; read devProbe from the dev SavedVariables
- Result: category data (class/subclass/equipLoc) and effect text (C_Spell.GetSpellDescription, C_TooltipInfo) available; checkbox menus (MenuUtil, WowStyle1FilterDropdownTemplate) available; old global item APIs nil. Findings in docs/api-findings.md
- Evidence: WTF SavedVariables TalentShare-Dev.lua, devProbe.at = 2026-11-16 22:54:29 (not copied: holds account data)
- Gaps: no alchemy/enchanting recipes in the catalog (potion/elixir subclasses and recipe-spell path not seen); profession-window categories empty (no window open during the click)
- Next: user decides on the design (answer), then T2-T4

## 2026-11-16 23:04 | BUILD | T2-T4 categories, profession dropdown, free-text search
- Did: Core/Model.lua (CategoryKey, RecipeCategories, TooltipSearchText, BuildRecipeRows categories + words), Core/ItemText.lua (new), Core/Api.lua (ItemCategoryInfo, CategoryLabel, CategoryGroupLabel, ItemTooltipLines), Core/Store.lua (itemText, Clean), UI/Window.lua (dropdowns, SearchBoxTemplate, text pump, fallbacks), Locales/deDE.lua, TalentShare.toc, tests/run.lua, tests/test_categories.lua (7); deployed
- Result: offline green; stubbed-client harness with and without menu templates runs all menus, ticks and the text pump without error
- Evidence: `luajit tests/run.lua` -> 194 passed, 0 failed
- Next: user restarts the game and runs verify.md checklist 1-5

## 2026-11-16 23:06 | VERIFY | first in-game look
- Did: user tried the dev build in game after the restart
- Result: user: "looks good" (which checklist items were run not stated; verify.md rows stay NOT-VERIFIED until confirmed)
- Evidence: user message
- Next: user confirms checklist 1-5 (or accepts the gaps); then commit

## 2026-11-16 23:09 | VERIFY | in-game checks by the user
- Did: user checked the profession dropdown, the category menu and searching for simple words in the dev build
- Result: pass (verify.md R1, R2, R3 partly IN-GAME); open: effect-text words, profession switch clearing categories, /tsd clean
- Evidence: user message "ive checked searching for simple words also dropdown and the category"
- Next: release 0.5.0 committed on release/0.5.0; remaining checklist items 3-5 when convenient

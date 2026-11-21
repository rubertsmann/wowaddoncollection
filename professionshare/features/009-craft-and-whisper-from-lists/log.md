# 009 Craft and whisper from lists: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-16 22:13 | PLAN | Feature created
- Did: scaffolded `features/009-craft-and-whisper-from-lists/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-16 22:19 | PLAN | Spec written
- Did: spec.md R1-R9, tasks T1-T5, review focus RF1-RF5; user asked "is it possible ... I want ...": built without a separate plan round (assumption logged in Decisions)
- Result: two-mode secure Craft button (open+select / craft), icon button per row, links built locally
- Evidence: spec.md
- Next: T1

## 2026-11-16 22:19 | BUILD | T1-T5 craft button, icon tooltips, whisper with link
- Did: Core/Model.lua (CraftTarget, OrderContact, RecipeContact, ChatText, order rows canCraft/claimersRaw); Core/Api.lua (RecipeLink, ItemLink, OpenProfessionName, SelectRecipe, CraftRecipe, open.tradeskill); Core/Events.lua (TRADE_SKILL_SHOW/CLOSE -> TRADESKILL); UI/Window.lua (icon button, recipeTooltip, whisper with text, secure Craft button, combat refresh); Locales/deDE.lua; tests/test_craft_whisper.lua (8)
- Result: offline green; in-game behaviour of CraftRecipe/OpenRecipe on Forever unknown
- Evidence: `luajit tests/run.lua` -> 178 passed, 0 failed; mutation ChatText without stripping -> 177 passed, 1 failed
- Next: user runs the in-game checklist in verify.md

## 2026-11-16 22:19 | BLOCKED | In-game checklist
- Did: doc.md, CHANGELOG "Unreleased", README, INDEX status verifying; deployed to the dev AddOns folder with tools/deploy.ps1
- Result: waiting for the game
- Evidence: n/a
- Next: user: /reload, `/console scriptErrors 1`, run verify.md items 1-8, report results (esp. item 3) or send /ts export

## 2026-11-16 22:27 | TEST | In game: "Open profession works only sometimes", "click to whisper does nothing"
- Did: SavedVariables (TalentShare-Dev.lua, written 22:20) hold no session after the deploy: no evidence on disk. Offline harness (scratchpad clicks.lua) runs every OnClick of the built window: whisper opens and inserts, no error offline
- Result: hypothesis 1 (craft): mode chosen by comparing the open window's profession name with the spellbook name; on a mismatch the button stays "/cast", and casting the open profession closes its window. Fix: Api.OpenWindowHasRecipe (open window lists the recipe). Hypothesis 2 (whisper): an error only the real client raises while building the link stopped the whisper silently (text was built before the whisper opened). Fix: whisper opens first, text built lazily inside pcall, error printed to chat; SelectRecipe no longer called right before CraftRecipe
- Evidence: luajit tests/run.lua -> 178 passed, 0 failed; debug log now records craft.mode / craft.select / craft.start / whisper lines
- Next: user: /reload, try both again, /reload once more (saves the log); read TalentShare-Dev.lua debug lines craft.* and whisper

## 2026-11-16 22:30 | VERIFY | Craft button works in game
- Did: read TalentShare-Dev.lua (saved 22:27) after the user's test
- Result: user: "crafting menu works"; C_TradeSkillUI.CraftRecipe from the addon button click works on Forever; every craft fires TRADE_SKILL_SHOW again (harmless: refreshes the button)
- Evidence: debug log lines "craft.start 2544 1 ok" (30+), "craft.start 6499 1 ok", "craft.start 2149 1 ok"; no "whisper" line at all in the log
- Next: whisper not yet tested after the fix (no log line): user clicks a crafter / recipe icon, reports chat output, /reload

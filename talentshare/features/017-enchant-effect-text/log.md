# 017 Enchant effect text: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-18 22:01 | PLAN | Feature created
- Did: scaffolded `features/017-enchant-effect-text/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-18 22:01 | BUILD | Effect text, search, dev fake enchanter
- Did: `Api.SpellDescription`, `Api.HyperlinkTooltipLines` (Core/Game/Api.lua); `recipeEffectText` with cache, tooltip and detail line, search lookup (UI/Window.lua); `lookups.effect` (Core/View/Model.lua); `Store.keptNames` (Core/Data/Store.lua); `DevProbe.AddFakeEnchanter`, Debug tab button (UI/DevProbe.lua, UI/Window.lua); `tests/test_effect_probe.lua`
- Result: copied live enchanter records were dropped by the 0.7.0 -> 0.7.1 version reset (`events.versionReset ... catalog=82 chars=3`), so testing moved to the in-memory fake enchanter
- Evidence: `luajit tests/run.lua` -> `231 passed, 0 failed`; user: "seems to be working correctly"
- Next: release 0.7.2; optional: `/reload` after hovering to log which source works (docs/api-findings.md)

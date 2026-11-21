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

## 2026-11-18 22:12 | DEVIATION | 0.7.2 showed tools/reagents instead of the effect for most enchants
- Did: read the `window.effectProbe` lines after the user's /reload (SavedVariables TalentShare-Dev.lua, 21:57:45-48). 5 of 6 enchants: description=nil on the first call, spell:/enchant: tooltips = name + "Werkzeuge: ..." (+ "Reagenzien: ..."); only 7771 had the description. The tooltip fallback took those lines as the effect and cached them for the session.
- Result: fix in UI/Window.lua: description only (no tooltip fallback), misses not cached, SPELL_DATA_LOAD_RESULT -> SPELL_INFO redraws the detail panel and the search (Core/Game/Events.lua). docs/api-findings.md records the real behaviour. spec.md R4 updated.
- Evidence: log lines 619-624 of TalentShare-Dev.lua; `luajit tests/run.lua` -> `231 passed, 0 failed`
- Next: user re-tests in the dev build (Fake enchanter, hover, select, /reload); then release 0.7.3

## 2026-11-18 22:14 | VERIFY | 0.7.3 fix confirmed in game
- Did: user re-tested in the dev build (Fake enchanter, hover, select, /reload); read the log
- Result: all 6 enchants found their real description, no errors; R1/R2 IN-GAME, status done
- Evidence: TalentShare-Dev.lua lines 643-648 `window.effectText` (22:12:05-22:12:10), e.g. 13419 "Einen Umhang dauerhaft so verzaubern, dass er die Beweglichkeit um 3 erhöht."
- Next: release 0.7.3

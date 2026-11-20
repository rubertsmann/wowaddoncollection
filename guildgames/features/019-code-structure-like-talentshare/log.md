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

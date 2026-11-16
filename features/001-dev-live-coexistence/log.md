# 001 Dev live coexistence: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-16 10:05 | PLAN | Feature created
- Did: scaffolded `features/001-dev-live-coexistence/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-16 10:06 | BUILD | T1-T3 identity block, deploy script, ignore files
- Did: `Core/Init.lua` identity block (IS_DEV, TITLE, PREFIX, SVNAME, FRAME, SLASH, VERSION); `Core/Events.lua` uses `_G[ns.SVNAME]`; `UI/Window.lua` frame names/title/offsets from ns; `tools/deploy.ps1` rewritten (generated dev TOC, junction `TalentShare-Dev`, removes old repo junction, `-InstallLive`/`-Force`); `.gitignore`/`.pkgmeta` ignore `TalentShare-Dev.toc`; TOC + `ns.BASE_VERSION` = 0.2.0; `tests/test_identity.lua`
- Result: `luajit tests/run.lua` -> 30 passed, 0 failed (26 before + 4 identity tests)
- Evidence: deploy output "removed old dev junction ... linked ...\TalentShare-Dev"; AddOns now lists TalentShare-Dev + TalentShareProbe, no TalentShare; repo files intact; `dist/TalentShare-0.2.0.zip` contains only TalentShare.toc (18 entries)
- Next: user starts the game, checks both addons (T4); document in README/status

## 2026-11-16 10:06 | BLOCKED | T4 in-game check needs the user
- Did: nothing; waiting
- Result: dev addon cannot be run by me
- Evidence: n/a
- Next: user runs `/tsd version` (expect "TalentShare (dev): v0.2.0-dev (protocol 1, prefix TShareDev)"), opens the window with `/tsd`, and reads the AddOn list (Esc -> AddOns) for the entry "TalentShare (dev)"

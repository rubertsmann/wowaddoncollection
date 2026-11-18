# 010 Order notifications: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-16 22:37 | PLAN | Feature created
- Did: scaffolded `features/010-order-notifications/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-16 22:38 | PLAN | Research and spec
- Did: options researched: Blizzard mail icon (MiniMapMailFrame, owned by real mail -> not used), own minimap button badge + letter icon, PlaySound (SOUNDKIT), RaidNotice_AddMessage, FlashClientIcon, chat line, tab label; Settings.RegisterCanvasLayoutCategory / InterfaceOptions_AddCategory for the options panel; spec.md R1-R7, RF1-RF5
- Result: user asked to "add options": built without a separate plan round (Decisions)
- Evidence: spec.md
- Next: T1

## 2026-11-16 22:38 | BUILD | T1-T5 notify core, badge, alerts, options panel
- Did: Core/Notify.lua (new), UI/Alerts.lua (new), UI/Window.lua (badge, letter icon, UI.SetNotice, UI.OrdersVisible, Options button, refreshOrders marks seen), Locales/deDE.lua, TalentShare.toc, tests/run.lua, tests/test_notify.lua (9 tests); deployed with tools/deploy.ps1 (dev TOC regenerated)
- Result: offline green; stubbed-client harness: new order -> chat line + PlaySound(880), all window/options clicks without error
- Evidence: `luajit tests/run.lua` -> 187 passed, 0 failed
- Next: user runs verify.md checklist 1-6 (needs a second guild member with the dev build for 1, 3-5)

## 2026-11-16 22:41 | BUILD | T6 test-all button
- Did: UI/Alerts.lua `Alerts.Test` + "Test all notifications" button (chat, sound, screen now; badge/letter 8 s; flash after 3 s); UI/Window.lua `UI.SetNotice(n, icon, hideNumber)` - fixes: with the badge option off the letter icon never showed; Locales/deDE.lua; deployed
- Result: offline green; harness: Test all -> chat line + sound, no errors
- Evidence: `luajit tests/run.lua` -> 187 passed, 0 failed
- Next: user runs verify.md checklist 1-7 (7 works alone, without a second member)

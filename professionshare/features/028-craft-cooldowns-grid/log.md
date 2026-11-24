# 028 Craft cooldowns grid: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-24 11:43 | PLAN | Feature created
- Did: scaffolded `features/028-craft-cooldowns-grid/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-24 11:45 | PLAN | spec written from the user's answers
- Did: filled spec.md (R1-R13, T1-T8, RF1-RF5, cross-cutting checklist, decisions from the 11 answers)
- Result: plan ready; protocol 2.8 / schema 9 decided (own record kind `cds`)
- Evidence: features/028-craft-cooldowns-grid/spec.md
- Next: user confirms the open question "one tile per craft vs. per crafter+craft", then start T1

## 2026-11-24 11:50 | DECISION | tile layout and debug cooldown
- Did: the user said "go ahead" without answering "one tile per craft vs. per crafter". Built per craft plus a switch "One tile per crafter"; the 20 s debug cooldown uses a fake member, not my own record (spec Decisions)
- Result: spec.md updated (R2, R12, Decisions)
- Evidence: features/028-craft-cooldowns-grid/spec.md
- Next: T1-T3

## 2026-11-24 11:55 | BUILD | T1-T3 data file, record, store schema 9, sync kind, protocol 2.8
- Did: new Core/Data/CraftCooldowns.lua (GROUPS, Sanitize, FromWire/ToWire, Put, Update, NoteCast, GroupsOfCharacter); Core/Data/Store.lua (cds table, schema 9, migration 8 -> 9, clean, prune, version reset, canonical names); Core/Net/Sync.lua (record kind cds: crev, WANTC, CDS with `at`); Core/Base/Init.lua PROTOCOL_MINOR 8; TOC, tests/run.lua, Events module check
- Result: tests/test_craft_cooldowns.lua (14 tests incl. 2 h clock skew over the codec, old peer, forged record)
- Evidence: `luajit tests/run.lua` -> 321 passed, 3 failed (own test with a future rev, test_reputation pinned schema 8, stale dev TOC); the first two fixed in the tests
- Next: T4 Api + Events

## 2026-11-24 12:00 | BUILD | T4-T7 game reading, view model, grid UI, debug options
- Did: Core/Game/Api.lua (ReadCraftCooldowns, OpenWindowCooldownRecipes, CraftLink, cooldownState.trusted); Core/Game/Events.lua (reads on login, SPELL_UPDATE_COOLDOWN, BAG_UPDATE_COOLDOWN, TRADE_SKILL_SHOW, UNIT_SPELLCAST_SUCCEEDED with fallback; /ps cd [scan]); Core/View/Model.lua (BuildCooldownTiles, ExpandCooldownTiles, FormatCooldownShort/Long, CooldownGroupName); Core/View/MiscTables.lua (mode cooldowns, IsGrid); new UI/CooldownGrid.lua; UI/Window.lua (grid in place of the table, switch, legend); UI/DevProbe.lua (cooldowns, cdsoon, cdprobe); Core/Debug/Diagnostics.lua; 21 deDE strings; tests/test_craft_cooldowns_model.lua; test_load covers the grid, the expanded view, /ps cd and the fake data
- Result: all offline tests green after tools/deploy.ps1 regenerated ProfessionShare-Dev.toc
- Evidence: `luajit tests/run.lua` -> 331 passed, 0 failed
- Next: docs (T8), then in-game check by the user

## 2026-11-24 12:10 | DOC | T8 docs
- Did: README (Cooldowns mode, module table), CHANGELOG 1.4.0, docs/protocol.md section 16, docs/status.md, doc.md, verify.md; INDEX status verifying
- Result: docs describe the built state; in-game checks listed in verify.md
- Evidence: this commit's diff (not committed yet: the user has not asked for a commit)
- Next: BLOCKED on the user: deploy is done; restart the game, run the verify.md in-game checklist (start with `/psd cd` next to an open Alchemy/Tailoring window, then Dev tools -> "Crafters: cooldowns in every state")

## 2026-11-24 13:30 | VERIFY | first in-game check (live 1.4.1 and dev build)
- Did: read the live and dev SavedVariables after the user's report "the features are working as expected"
- Result: no ERROR/EXCEPTION today; dev fake crafters ran, tiles of all three groups whispered; live: a real member's synced recipes contain 17187 (Transmute: Arcanite), the Transmute tile listed that member and whispered (no 1.4 member yet, so no peer cooldown records); verify.md rows R1, R2, R4, R7-R11 IN-GAME, R3/R12 partial
- Evidence: WTF/Account/<account>/SavedVariables/ProfessionShare.lua (log 13:21-13:22, recipes), ProfessionShare-Dev.lua (log 12:12)
- Next: own cooldown reading with an alchemist or tailor (`/ps cd`, checklist 1-2), then a second member on 1.4.x (checklist 7); status stays verifying until then or until the user accepts the gaps

## 2026-11-24 17:57 | VERIFY | first real members on 1.4.1
- Did: read the live SavedVariables after several guild members updated
- Result: three members on 1.4.1; HELLO with the cooldown field arrives, "cds: peer has none" for each (none knows a timegated recipe, checked against their synced recipes), `cds` empty; 1.3.0 / 1.0.2 members still sync; no warnings after 12:51
- Evidence: live ProfessionShare.lua comm log (HELLO `ver=1.4.1/6`, `why` lines), `cds = {}`, chars records without cooldown recipe ids
- Next: checklist 7 needs a 1.4.x member who knows a transmute, Mooncloth or the Salt Shaker; 1-2 an own alchemist/tailor; 6 the 20 s trigger; or the user accepts the gaps -> done

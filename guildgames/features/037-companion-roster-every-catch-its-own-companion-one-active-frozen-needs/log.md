# 037 Companion roster (every catch its own companion, one active, frozen needs): log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-25 17:13 | PLAN | Feature created
- Did: scaffolded `features/037-companion-roster-every-catch-its-own-companion-one-active-frozen-needs/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-25 17:15 | PLAN | Spec written from the user's 10 answers
- Did: filled spec.md (requirements, design, tasks, review focus, checklist, decisions Q1-Q10)
- Result: plan ready for review; 037 (roster, schema 3) comes before 038 (3v3 team fights, protocol 1.6, same-version gate)
- Evidence: spec.md
- Next: user reviews the plan (038: confirm the "full roster" reading); then build 037 T1

## 2026-11-25 17:55 | BUILD | All tasks built (037 and 038 together, on user request "implement both")
- Did: Core/Minigames/AzeCaught.lua (roster, Reconcile, Select by uid, Release, frozen rest, move from schema 2), Core/Minigames/Arena.lua (progress per companion, team fight, teams in challenge/answer/counter, version gate, legacy refunds, dummy team), Core/Data/Store.lua (schema 3), Core/Base/Init.lua (protocol 1.6), Core/View/Model.lua (roster rows), UI/AzeCaughtPanel.lua (roster, Switch, Release), UI/ArenaView.lua (team flows, replay strip), UI/TeamDialog.lua (new), GuildGames.toc, Locales/deDE.lua, tests (test_roster, test_team_arena, updates), README, CHANGELOG, docs/protocol.md
- Result: 193 passed, 0 failed; simulator: 0 GuildGames errors in 4 scenarios
- Evidence: luajit tests/run.lua -> "193 passed, 0 failed"; features/037-*/evidence/sim-roster.png, features/038-*/evidence/sim-accept.png, sim-challenge.png, sim-replay.png (scenario sim-teams.lua)
- Next: user runs the in-game checklist in verify.md (dev build deployed); then a second guild member on the same build for the two-client fight

## 2026-11-25 20:30 | DONE | released in GuildGames 0.11.0
- Did: user tried it in game with the training dummy and accepted ("seems to be all working just fine - cleanup commit push create a new version"); verify.md rows set, accepted gaps written.
- Result: status done.
- Evidence: verify.md; release commit of guildgames/v0.11.0.
- Next: the two-client 3 vs 3 fight when a second guild member updates (verify.md checklist).

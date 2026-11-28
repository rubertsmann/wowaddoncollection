# 023 Send backlog and offline whispers: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-23 21:59 | PLAN | Feature created
- Did: scaffolded `features/023-send-backlog-and-offline-whispers/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-23 21:40 | PLAN | Diagnosis from the live log
- Did: read the live SavedVariables trace (1.0.2) after the user saw "Momentan ist kein Spieler mit dem Namen ... online" for a guild member.
- Result: send queue backlog (434 chunks, oldest 756 s), 53 outdated answers waiting, 19 own revs in 814 s (crafting skill-ups, each a forced HELLO). Whispers to "First Surname" names work in general. The game's system message itself is not in the log (no CHAT_MSG_SYSTEM capture).
- Evidence: numbers in spec.md "Decisions" (no player names in this repo)
- Next: user decides on fixes A/B/C

## 2026-11-23 21:55 | BUILD | T1, T2 library and addon wiring
- Did: see spec.md Design. Tests written first: the 3 library tests failed before the change (replace: 12 chunks instead of 6; offline: sent; IsOnline: nil field).
- Result: green
- Evidence: libguildsync `39 passed, 0 failed`; professionshare `259 passed, 0 failed`; guildgames `139 passed, 0 failed`
- Next: docs and release

## 2026-11-23 22:05 | NOTE | Released
- Did: ProfessionShare 1.2.1 and GuildGames 0.4.1 with LibGuildSync MINOR 5 (versions, CHANGELOGs, RELEASE_NOTES), tags `professionshare/v1.2.1`, `guildgames/v0.4.1`.
- Result: status stays `verifying` (live check open)
- Evidence: libguildsync 39, professionshare 259, guildgames 139 passed, 0 failed
- Next: user plays a crafting session with the guild, then checks the trace (verify.md checklist)

## 2026-11-28 10:37 | DONE | closed at the status review
- Did: user reviewed the feature's state
- Result: status done
- Evidence: user: "works" (2026-11-28)
- Next: none

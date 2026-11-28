# 023 Send backlog and offline whispers: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` | `MULTI-CLIENT` | `READ-ONLY` | `NOT-VERIFIED`.

Baseline before work: libguildsync 36, professionshare 257, guildgames 138 passed, 0 failed
Result after work: libguildsync 39, professionshare 259, guildgames 139 passed, 0 failed

| ID | Requirement / Review Focus | How verified | Level | Evidence | Result | Date |
|---|---|---|---|---|---|---|
| R1 | Newer record answer replaces a waiting one | libguildsync `test_channel` "a newer record answer ... replaces ..."; professionshare `test_send_backlog` | OFFLINE | suites above | pass | 2026-11-23 |
| R2 | Offline recipient's whispers dropped | libguildsync `test_channel` "whispers to a member the roster shows offline ...", "guild: the roster records who is online"; `test_send_backlog` | OFFLINE | suites above | pass; roster freshness on Forever NOT verified | 2026-11-23 |
| R3 | Own changes announced coalesced | professionshare `test_load` ("soon,soon,soon") | OFFLINE | 259 passed | pass | 2026-11-23 |
| R4 | Trace shows dropped / replaced | `test_channel` (st = replaced / dropped) | OFFLINE | 39 passed | pass | 2026-11-23 |
| RF1 | Partly sent message not replaced | `test_channel` replace test, last part | OFFLINE | 39 passed | pass | 2026-11-23 |
| RF2 | Recently heard member counts online | `test_channel` offline test (C-R) | OFFLINE | 39 passed | pass | 2026-11-23 |
| RF3 | Throttle keeps the chunk | existing throttle tests in `test_channel` | OFFLINE | 39 passed | pass | 2026-11-23 |
| live | Message gone in a real session | play with the guild while levelling a profession, then read the trace (`/ps export`): few `queued` rows, `dropped ... offline` for members who left | NOT-VERIFIED | - | needs user | - |
| ALL | user's status review | user, live use | IN-GAME | user: "works" | pass | 2026-11-28 |

## In-game checklist
- [ ] Craft for a while with several members online; afterwards `/ps export`: chunks waiting stay small, no whisper rows older than a minute.
- [ ] A member logs out while you craft: no "kein Spieler ... online" message; the trace shows `dropped recipient offline`.

## Accepted gaps
- Checklist items not run one by one: closed at the user's status review (2026-11-28, "works").

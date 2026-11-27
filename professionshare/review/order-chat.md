# Review: order chat and history (protocol 2.9, feature 048) and the notification scope dropdown (feature 047)

Scope: the uncommitted change before release 1.6.0. Read and run offline (`luajit tests/run.lua` -> 402 passed,
0 failed); the window, the chat and the alert were checked in game by the user with `/psd fake chat` (one client).
Two real members chatting is NOT verified.

## Checklist
| # | Area | Result |
|---|---|---|
| 1 | Secrets | none in the diff or the new files |
| 2 | Inbound gate | `OMSG` is a normal Sync handler behind `Communication.OnAddonMessage` -> `Guard.Accept`; no new path |
| 3 | Input validation | `Orders.Sanitize` copies `msgs`/`ev` by allow-list (safe names, times in the horizon, text UTF-8 <= 160 bytes, no control characters, not blank, kinds from a list); a bad entry is dropped, a list > 120 not read; `MergeMessage` sanitizes the single `OMSG` entry; `xdig` values are only compared (`type == "number"`), never stored; catalog `tools` allow-listed (<= 4, <= 60 bytes, no `|`) |
| 4 | Display | chat text escaped in `Model.OrderChatRows`; names through `Utility.Escape(ShortName)`; tools escaped in `Model.OrderOverview`; the chat-frame alert uses `Utility.ChatSafe` |
| 5 | Version | minor 2.9, additive, `docs/protocol.md` section 18; `Orders.Version` unchanged so 2.8 digests still match; chat pushed only to peers that send `xdig` (tested) |
| 6 | Persistence | new order fields re-sanitized on load; older builds drop them; `ui.chatSeen` read with `tonumber`, pruned |
| 7 | Bounds | 30 messages + 30 events per order; OPUSH cut at 10 orders or ~8000 estimated bytes (a full batch encodes far below `MAXIMUM_ENCODED_BYTES`, tested) |
| 10 | WoW specifics | the order window holds no secure frames; strata DIALOG so the main window cannot draw through it |
| 11 | Tests | `tests/test_order_chat.lua` (11), `test_sync.lua` (+4: live, catch-up, forged author, 2.8 peer, size), `test_load.lua` |

## Findings
| ID | Severity | Where | Finding | Recommendation |
|---|---|---|---|---|
| OC1 | Low | `Core/Data/Orders.lua` `extraVersion` | The digest is a sum of times: two different chat sets with the same sum (two messages in the same second dropped/added by the 30 cap on different peers) look equal, so the peers do not resync until the next message. Rare, self-healing with the next message. | Accept; if it shows up, add the entry count to the digest (needs a 2.x minor). |
| OC2 | Info | `Core/Net/Sync.lua` `onOrderPush` | Relayed chat (OPUSH) can carry messages in any member's name. Within the trust model (guild members are trusted, like claims); live `OMSG` is checked against the sender. | None. |
| OC3 | Info | `Core/Data/Orders.lua` sanitize | A guild member can send a message dated up to one day ahead; it then sorts last. Within the trust model. | None. |
| OC4 | Low | `UI/Alerts.lua` `ui.chatSeen` | Pruned only when a chat is read; entries of pruned orders stay until then (a few numbers). | Accept. |

No finding blocks the release.

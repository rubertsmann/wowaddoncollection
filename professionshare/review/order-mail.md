# Review: order mail status and history (protocol 2.10, feature 049)

Scope: the uncommitted change after release 1.6.0. Read and run offline (`luajit tests/run.lua` -> 415 passed,
0 failed). Nothing verified in game yet.

## Checklist
| # | Area | Result |
|---|---|---|
| 1 | Secrets | none in the diff |
| 2 | Inbound gate | no new message type; `ml` travels in ORDER/OPUSH, `mdig` in HELLO, behind `Guard.Accept` as before |
| 3 | Input validation | `Orders.Sanitize` copies `ml` by allow-list (kind from a list, safe names, times in the horizon, `c`/`h` only `true`, item list of <= 12 pairs of bounded positive integers); a bad entry is dropped, a list > 120 not read; `mdig` values only compared |
| 4 | Display | names through `Utility.Escape(ShortName)`; item names via `Model.ItemListText` (escaped); the alert uses `Model.ChatText` for the recipe name and `ShortName` for the sender |
| 5 | Version | minor 2.10, additive, `docs/protocol.md` section 19; `Orders.Version`/`ExtraVersion` unchanged; mails pushed only to peers that send `mdig` (tested) |
| 6 | Persistence | `ml` re-sanitized on load; older builds drop it; `ui.mailSeen` read with `tonumber`, pruned |
| 7 | Bounds | 30 entries per order; OPUSH size estimate counts 160 bytes per entry; message depth stays <= 6 |
| 10 | WoW specifics | no secure frames; recording runs after `MAIL_SEND_SUCCESS` / a click, never in a protected path |
| 11 | Tests | `tests/test_order_mail.lua` (9), `test_mail_sender.lua` (+3), `test_sync.lua` (+1), `test_load.lua` |

## Findings
| ID | Severity | Where | Finding | Recommendation |
|---|---|---|---|---|
| OM1 | Info | `Core/Data/Orders.lua` `Status` | Any guild member's complete item entry makes the order Mailed (no check that the sender claims it). Within the trust model, like claims. | None. |
| OM2 | Low | `Core/Game/MailSender.lua` `recordMail` | An item job sent to a recipient other than the requester (chosen in the row menu) still sets Mailed. | Accept; the history names the recipient. |
| OM3 | Info | `Core/Data/Orders.lua` `mailVersion` | Same sum-of-times digest weakness as OC1 (two different sets with the same sum look equal); self-healing with the next mail. | Accept. |

No finding blocks.

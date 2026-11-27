# Review: mail tag and pickup tracking (protocol 2.11, feature 050)

Scope: the uncommitted change after release 1.7.0. Read and run offline (`luajit tests/run.lua` -> 423 passed,
0 failed, inbox simulated). The real inbox API is not verified.

## Checklist
| # | Area | Result |
|---|---|---|
| 1 | Secrets | none |
| 2 | Inbound gate | no new message type; `rcv` travels in ORDER/OPUSH, `rdig` in HELLO |
| 3 | Input validation | `rcv` allow-listed like `ml` (without `c`/`h`); `rdig` values only compared. Inbox data comes from the local client; the tag is matched by pattern and never shown |
| 4 | Display | pickup rows: names escaped, items via `Model.ItemListText`; the alert via `Model.ChatText` / `ShortName` |
| 5 | Version | 2.11 additive, `docs/protocol.md` section 20; separate digest |
| 6 | Persistence | `rcv` re-sanitized on load |
| 7 | Bounds | 30 entries; the OPUSH estimate counts them |
| 10 | WoW specifics | post-hooks (`hooksecurefunc`) on the take functions, no replaced globals, no protected calls; every inbox call in `pcall` |
| 11 | Tests | `tests/test_mail_pickup.lua` (8) with a simulated inbox |

## Findings
| ID | Severity | Where | Finding | Recommendation |
|---|---|---|---|---|
| MP1 | Low | `Core/Game/MailReceiver.lua` | A failed take (bags full) followed within 15 s by returning the same mail counts as a pickup. | Accept (rare); shorten the window if seen. |
| MP2 | Info | `Core/Data/MailQueue.lua` `Tag` | A 6-character hash: two orders with the same tag are possible in theory; the role check narrows a wrong match further. | None. |
| MP3 | Info | `Core/Data/MailQueue.lua` `ApplyPickup` | Anyone could type a tag into a subject; it only counts for the requester or a claimer taking the items out of their own mailbox. Within the trust model. | None. |
| MP4 | Medium (until verified) | `Core/Game/MailReceiver.lua` `readMail` | The `GetInboxHeaderInfo` return order (sender 3rd, subject 4th, hasItem 8th, wasReturned 10th) and the item id as the 2nd value of `GetInboxItem` are from the modern client, not verified on Forever. If wrong, pickups are simply not recorded (no error). | Verify in game; record in `docs/api-findings.md`. |

No finding blocks.

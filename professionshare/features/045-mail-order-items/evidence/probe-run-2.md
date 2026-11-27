# Mail probe run 2 (2026-11-27 11:15, 1.4.3-dev, user, `/psd mailtest` at an open mailbox)

```
[ 0.00] --- attach (1.4.3-dev, 2026-11-27 11:15:34) ---
[ 0.00] item 279978 (Camp Tent): stacks in the bags: bag 0 slot 2: 5
[ 0.00] event CURSOR_CHANGED false, 1, 0, 0
[ 0.00] event ITEM_LOCK_CHANGED 0, 2
[ 0.00] item 279978 from bag 0 slot 2 (stack 5): split 3 -> ok, cursor holds item: true
[ 0.00] event MAIL_SEND_INFO_UPDATE (nothing)
[ 0.00] event CURSOR_CHANGED true, 0, 1, 0
[ 0.00] event MAIL_SEND_INFO_UPDATE (nothing)
[ 0.00] ClickSendMailItemButton(1): ok; GetSendMailItem(1) right after: Camp Tent, 279978, 134250, 5, 1
[ 0.00] MAIL_SEND_INFO_UPDATE seen after 0.00 s; GetSendMailItem(1): Camp Tent, 279978, 134250, 5, 1
[ 0.00] item 6948 (Hearthstone): stacks in the bags: bag 0 slot 1: 1
[ 0.00] event CURSOR_CHANGED false, 1, 0, 0
[ 0.00] event ITEM_LOCK_CHANGED 0, 1
[ 0.00] item 6948 from bag 0 slot 1 (stack 1): pickup -> ok, cursor holds item: true
[ 0.00] ClickSendMailItemButton(2): ok; GetSendMailItem(2) right after: (nothing)
[ 0.00] event ITEM_LOCK_CHANGED 0, 1
[ 0.00] event CURSOR_CHANGED true, 0, 1, 0
[ 0.00] after click: cursor still held an item -> ClearCursor (now holds item: false)
[ 0.00] event UI_ERROR_MESSAGE 460, You can't mail soulbound items.
[ 1.93] event ITEM_LOCK_CHANGED 0, 2
[ 3.04] MAIL_SEND_INFO_UPDATE NOT seen after 3.04 s; GetSendMailItem(2): (nothing)
[ 3.04] attachments now: none
```
(Two earlier runs in the same report: `fill` and `attach` with the mailbox closed -> "the mailbox is not open".)

Read from it (facts on Forever):
- F1: `SplitContainerItem` + `ClickSendMailItemButton` attached the WHOLE stack (5), not the 3 split off.
- F2: `MAIL_SEND_INFO_UPDATE` fires synchronously inside `ClickSendMailItemButton` (twice); no waiting needed after a good attach.
- F3: A soulbound item is refused on the client: it stays on the cursor, no attachment, `UI_ERROR_MESSAGE 460 "You can't mail soulbound items."`; ClearCursor put it back.
- F4: Open: the Camp Tent attachment was gone 3 s later (bag 0 slot 2 unlocked at 1.93 s). Server refusal (tent bound?) or a side effect of the refused Hearthstone; unknown.
- `fill` not tested yet (mailbox was closed).

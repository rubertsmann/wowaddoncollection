# Order row actions and mailbox queue list

Status: built, in-game check open | Since version: next release | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
The Orders tab works per order: a filter dropdown, a right-click menu with the order's actions, and action icons on
each row (mail the reagents to the crafter, mail the crafted item to the requester, add to the Auctionator buy list).
At a mailbox the mail queue is listed next to the inbox; you fill one mail at a time with a click.

## How to use
- Filter: the dropdown top left (which orders; "Show finished").
- Right-click an order: I'll craft it, Withdraw, Mark done, Cancel order, Whisper, the mail actions, the buy list.
- **Craft** (top bar): for the selected order (a menu cannot cast spells in WoW, so it stays a button).
- Row icons: hammer = I'll craft it, pass = Withdraw, check = Mark done, cross = Cancel order, bag = mail the reagents to the crafter (several claimers: a menu asks who), letter = mail the crafted item
  to the requester, coin (Auctionator only) = add to the buy list (dialog with "Subtract what I have").
- Mailbox: the panel lists every queued mail with ready/missing counts. **Fill** fills it, you press Send. **Done**
  takes what is attached off the mail (the missing rest stays), **Delete** removes it. The Mail tab has the same as row
  icons (arrow = Move up, letter = Fill, check = Done, cross = Delete).

## How it works
- Buy list: `db.ui.buyListOrders[character] = { orderID, ... }`; every Add rebuilds Auctionator's list from all
  collected orders and sets the search for the next auction house visit; `AUCTION_HOUSE_CLOSED` after a search clears
  the collection (`AuctionatorBridge.TakeSearchedThisVisit`).
- Mail: `MailSender.FillJob(jobID)` fills on click (another queued mail in the form is emptied first; items the player
  put in are not touched); `MailSender.Done(jobID)`; no fill on `MAIL_SHOW` or after `MAIL_SEND_SUCCESS`.
- Order rows: `canMailMats`, `canMailItem`, `hasReagents` (`Model.BuildOrderRows`).
- Messages: no change.

## Limits and known issues
- No menu support on the client: right-click does nothing (left-click still selects); the filter becomes a cycle
  button (right-click toggles finished orders).
- The panel shows at most 8 mails; the rest are on the Mail tab.

## Changelog line
- Orders tab: filter dropdown, right-click actions, row icons for mail and buy list; Craft in the top bar. Mailbox:
  queue listed next to the inbox, Fill / Done / Delete per mail.

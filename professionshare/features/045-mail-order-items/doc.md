# Mail order items

Status: built, in-game check open | Since version: next release | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
From the Orders tab you queue mails for orders: the reagents to the crafter who claimed the order, or the crafted item
to the requester. The queue waits until you open a mailbox. Then the first mail is filled for you (recipient, subject,
exact amounts attached) and you press Send. After the send the next one is filled.

## How to use
- Orders tab: tick orders, choose the mode with **Mail: mats to crafter** / **Mail: item to requester** (bottom right),
  click **Add to mail queue (n)**. Several claimers: a menu asks who gets the mats. Queued orders lose their tick.
- **Mail** tab (next to Orders): the queue with each mail's items and what your bags are missing; **Move up**,
  **Remove**, **Fill next mail**.
- At a mailbox: the panel next to the mail window shows the mail in the form; **Fill next mail**, **Skip** (the
  attachments go back, the next job is filled), **Remove**, **List** (opens the Mail tab).
- Items you lack are left out; after the send the job keeps only them and waits for the next mailbox. More than 12
  attachments: the rest goes in the next mail of the same job.

## How it works
- Data: `db.mailQueue[characterName] = { job, ... }` (local, sanitized on load); `db.ui.mailMode` ("item" or absent = mats).
  Job: `{ id, orderID, mode, recipient, recipeID, qty, label, items = { [itemID] = remaining }, createdAt }`.
- Messages: none (nothing is sent to other members).
- Modules: `Core/Data/MailQueue.lua` (pure: jobs, attachment plan), `Core/Game/MailSender.lua` (fills the form, mail
  events, SendMail post-hook), `UI/MailPanel.lua` (panel at the mailbox), Mail tab and Orders controls in `UI/Window.lua`.
- Exact amounts: a whole stack when it fits the remaining need, otherwise the amount is split into a free bag slot and
  that new stack is attached (a split clicked straight into the mail attaches the whole stack on Forever).
- A send counts for the job only when the mail went to the job's recipient (realm and case ignored).

## Localization
All labels through `Text` (deDE in `Locales/deDE.lua`). Subject and body use the recipe name in the sender's language.

## Limits and known issues
- Item mode assumes one item per craft.
- Bags only (not bank). Soulbound items are skipped.
- Not verified in game yet: the tab switch and recipient field on Forever, the split into a free slot, `MAIL_SEND_SUCCESS`.

## Changelog line
- Mail queue: queue the reagents (to the crafter) or the crafted item (to the requester) of ticked orders; at a mailbox
  the mails are filled one after another with exact amounts, you press Send. New Mail tab.

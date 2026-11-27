# Order mail status and history

Status: done | Since version: 1.7.0 | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
A mail sent through the addon's mail queue is written into its order by itself. The order's History tab lists every
mail with its items and amounts; once the crafted item has gone out completely, the order has the status **Mailed**
(between claimed and done) until the requester marks it done. The recipient of a mail gets order news for it.

## How to use
- Send a queued mail from the mailbox panel as before; nothing else to do.
- **Done** on a queued mail in the mailbox panel (sent by hand) records the mail as "(marked by hand)".
- Order window, Overview: **Mark item as mailed / handed over** (active crafter) and **Mark reagents as mailed /
  handed over** (requester, while someone claims it) for mails outside the queue or trades.
- Orders tab: status "Mailed" with a mail icon, filter **Mailed**.
- Dev build: `/psd fake mailed [delay]` puts a mail from someone else to you on an order (local only).

## How it works
- Data: optional order field `ml` (`docs/protocol.md` section 19), synced with the order; local `ui.mailSeen`.
- Messages: ORDER and OPUSH carry `ml`; HELLO `mdig` (protocol 2.10).
- Modules: `Core/Data/Orders.lua` (entries, status, digest), `Core/Data/MailQueue.lua` (`Delivered`, `MailEntry`),
  `Core/Game/MailSender.lua` (records on send / Done), `Core/View/Model.lua` (history, rows, mark targets),
  `Core/View/Notify.lua` (mail news), `UI/OrderWindow.lua`, `UI/Window.lua`, `UI/Alerts.lua`.

## Localization
New labels through `Text` (deDE translated). Item names come from the viewer's client; only ids and counts are sent.

## Limits and known issues
- Mails sent outside the queue are not detected (use the mark button).
- Returned or bounced mails are not detected.
- The status needs a COMPLETE item mail; a partial one shows only in the history.

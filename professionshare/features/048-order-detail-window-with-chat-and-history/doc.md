# 048 Order detail window with chat and history: documentation

## What it does
Every order on the Orders tab has a speech-bubble icon (first in the row's action column). It opens a window for that
order with three tabs:
- **Overview:** status, who requested it and when, who crafts it, when and by whom it was closed, the note, the
  reagents for the whole ordered quantity with how many you hold (bags and bank), the tools the recipe needs (when a
  crafter's scan recorded them) and the guild members who know the recipe with their rank.
- **Chat:** the order's messages, oldest at the top, newest at the bottom; type in the line at the bottom, Enter or
  **Send**. Every guild member with the addon reads and writes every order's chat. Hover a message for the full text.
- **History:** every status change with date and time: placed, claimed, withdrawn, marked done, cancelled, and who.

A new message from someone else on an order you requested or claim is order news: number on the minimap button and the
row's chat icon, the notification sound and a chat line "Name about Recipe: text" (the existing switches under
Settings -> Order notifications apply). Opening the order's chat marks it read. The window opens on the chat when
it has unread messages, else on the overview.

## How it works
- Data: optional order fields `msgs` and `ev` (`Core/Data/Orders.lua`), merged as a union, at most 30 of each.
- Wire (protocol 2.9): HELLO `xdig`, message `OMSG`, catalog `tools`; details in `docs/protocol.md` section 18.
- View: `Model.OrderOverview`, `Model.OrderChatRows`, `Model.OrderHistory`; unread: `Notify.UnseenChat`,
  `Notify.ChatUnread`; window: `UI/OrderWindow.lua`.

## Limits
- At most 30 messages per order (the oldest drop), 160 bytes each. No editing or deleting.
- A message reaches members who are online, or later from any member who holds it (their HELLO digest compare).
- Members on 2.8 or older do not see chat or the recorded history; their claims and closes still show in the history
  (taken from the order's own fields), but a claim they withdrew and claimed again shows only the last step.
- Tools are known only from clients with `GetTradeSkillTools` (classic profession window).
- Pruned orders (closed for 7 days, or 30 days old) take their chat along.

## Localization
All labels through `Text` (deDE added). Chat text is player text, shown as typed (escaped).

## Verification
See [verify.md](verify.md).

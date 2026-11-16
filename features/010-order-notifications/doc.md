# Order notifications

Status: verifying | Since version: next release | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
When a guild member posts an order you could craft, or someone claims or finishes one of your orders, TalentShare tells
you without the window being open: a red number on the minimap button and on the Orders tab, a letter icon on the
minimap button, a chat line and a sound. A message in the middle of the screen and a flashing taskbar icon can be
switched on. Opening the Orders tab clears it.

## How to use
- **Options** button in the window, `/ts options`, or the game's settings under AddOns > TalentShare.
- "Tell me about": orders for my professions (default; also recipes of that profession you do not know yet), recipes I
  know, or all orders.
- Sound: four game sounds to choose from, **Test** plays it.
- **Test all notifications** shows every switched-on effect once (badge and letter for 8 s, taskbar flash after 3 s).

## How it works
- `Core/Notify.lua` (pure): `Relevant`, `Unseen`, `MarkSeen`, `Fresh`, `Get`/`Set` with defaults. Tests: `tests/test_notify.lua`.
- `UI/Alerts.lua`: recomputes on `DATA_CHANGED` (orders/chars), announces only what is new since the last check, at
  most one sound/screen message/flash per 10 s; options panel.
- Data (SavedVariables, this client only): `ui.notify` (settings), `ui.notifySeen[orderId]` (state when last seen; pruned
  with the orders). Messages: no change.
- Why not the game's mail icon: it belongs to real mail; the game shows and hides it itself.

## Localization
All strings in `Locales/deDE.lua`. Recipe names from peers are shown as plain `[Name]` (Model.ChatText).

## Limits and known issues
- Relevance by profession needs at least one guild member in the data who knows the recipe (always true for orders made from the Recipes tab).
- Settings panel API and the letter texture on Forever are not verified yet (fallbacks: own options window; default icon).

## Changelog line
- Notifications about new orders for your professions and news on your own orders (minimap badge, letter icon, sound, chat, optional screen message and taskbar flash), with an options panel (`/ts options`).

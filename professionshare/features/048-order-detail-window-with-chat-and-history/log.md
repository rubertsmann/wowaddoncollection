# 048 Order detail window with chat and history: log

Append only. Newest entry at the bottom. The last entry must say what to do next.
Format: `## <YYYY-MM-DD HH:MM> | <PLAN|DECISION|BUILD|TEST|VERIFY|DOC|DEVIATION|BLOCKED|DONE|NOTE> | <short title>` then Did / Result / Evidence / Next.

## 2026-11-27 13:54 | PLAN | Feature created
- Did: scaffolded `features/048-order-detail-window-with-chat-and-history/` from the templates
- Result: spec.md is empty
- Evidence: n/a
- Next: fill in spec.md (goal, requirements, design, tasks, cross-cutting checklist)

## 2026-11-27 14:07 | DECISION | Chat access, alerts, opening
- Did: asked the user; answers recorded in spec.md Decisions (everyone reads/writes, chat on my orders notifies, row icon opens)
- Result: design: chat and events inside the order record, own digest `xdig`, message `OMSG`, protocol 2.9, schema unchanged
- Evidence: spec.md Decisions
- Next: T1 order data

## 2026-11-27 14:07 | BUILD | T1-T6 data, sync, tools, model, notify, window
- Did: `Core/Data/Orders.lua` (msgs/ev, sanitize, union merge, AddMessage, MergeMessage, WithoutChat, ExtraVersion,
  ExtraDigest, Missing with xdig, events on claim/withdraw/close); `Core/Net/Sync.lua` (xdig, OMSG, ORDER without chat,
  size-cut OPUSH batches); `Core/Net/Communication.lua` (BroadcastOrderMessage, OMSG priority); `Core/Base/Init.lua`
  minor 9; `Core/Data/Store.lua` + `Core/Game/Api.lua` + `Core/Data/Scanner.lua` (catalog `tools`);
  `Core/View/Model.lua` (OrderHistory, OrderChatRows, OrderOverview, row unreadChat); `Core/View/Notify.lua` (chat
  unread); `UI/Alerts.lua` (chat news, ChatSeen); `UI/OrderWindow.lua` (new); `UI/Window.lua` (details icon with
  count); TOC; deDE (25 strings); tests `tests/test_order_chat.lua` (new, 11), `test_sync.lua` (+4), `test_load.lua`.
  `tests/test_hardening.lua`: the "newer minor" header became 2.99 (2.9 is now the current minor).
- Result: all tasks built
- Evidence: `luajit tests/run.lua` -> 402 passed, 0 failed
- Next: docs (T7), then the in-game checklist in verify.md (user)

## 2026-11-27 14:09 | DOC | T7 docs and verification matrix
- Did: docs/protocol.md section 18, CHANGELOG (Unreleased -> protocol 2.9), README (order window, code layout),
  docs/status.md, doc.md, verify.md; spec status verifying, INDEX verifying
- Result: every requirement OFFLINE; the window look, typing, tools API on Forever and two-member chat NOT-VERIFIED
- Evidence: `luajit tests/run.lua` -> 402 passed, 0 failed
- Next: user runs the in-game checklist in verify.md (game restart needed: new TOC file); then done

## 2026-11-27 14:42 | VERIFY | In-game: works; layering bug fixed
- Did: user report: "in general it works fine", but the main window's icons and text drew through the order window
  (it looked transparent). Cause: both windows on strata HIGH; the main window's rows have higher frame levels.
  `UI/OrderWindow.lua`: strata DIALOG, toplevel, Raise on open.
- Result: fix built; not yet seen in game
- Evidence: user message; `luajit tests/run.lua` -> 402 passed, 0 failed
- Next: user checks the window again (`/reload` is enough); then review-professionshare on the change, then done

## 2026-11-27 14:44 | BUILD | Dev command: fake chat answer
- Did: `UI/DevProbe.lua` `AddFakeChatMessage`, entry `chat` (`/psd fake chat [delay s]`, Dev tools menu, Triggers): a message
  from the requester / a claimer / a fake member on the open (or my newest) order, merged as if received; not sent.
  `tests/test_load.lua` runs it.
- Result: the chat, unread count and alert can be tried alone
- Evidence: `luajit tests/run.lua` -> 402 passed, 0 failed
- Next: user checks the layering fix and the fake answer in game; then review-professionshare, then done

## 2026-11-27 14:46 | DONE | Released in 1.6.0
- Did: status done (spec, INDEX); remaining in-game rows accepted by the user's release request (verify.md)
- Result: part of release 1.6.0
- Evidence: verify.md "Accepted gaps"; review/order-chat.md (no blocking finding)
- Next: none

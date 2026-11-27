# 048 Order detail window with chat and history: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> 387 passed, 0 failed
Result after work:    `luajit tests/run.lua` -> 402 passed, 0 failed

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence (output line, file, screenshot) | Result | Date |
|---|---|---|---|---|---|---|
| R1 | Chat icon opens the window, shows unread count | test_load "load: all TOC files..." (window opens per tab, row unreadChat = 1, read after showing the chat) | OFFLINE | 402 passed | pass (look NOT-VERIFIED in game) | 2026-11-27 |
| R2 | Overview content | test_order_chat "order overview: reagents for the whole quantity, tools ..." + test_load | OFFLINE | 402 passed | pass (look NOT-VERIFIED) | 2026-11-27 |
| R3 | Chat rows + input, everyone writes | test_load (send path), test_order_chat merge tests | OFFLINE | 402 passed | pass (typing/Enter NOT-VERIFIED) | 2026-11-27 |
| R4 | History incl. old-version changes | test_order_chat "order history: derived from the fields for old orders ..." | OFFLINE | 402 passed | pass | 2026-11-27 |
| R5 | Sync live + after login, 2.8 unaffected | test_sync "order chat travels live (OMSG) and after login", "a HELLO without xdig (2.8 peer) ..." | OFFLINE | 402 passed | pass; two real clients NOT-VERIFIED | 2026-11-27 |
| R6 | Chat on my orders is news; reading clears it | test_order_chat "order chat notify: ..." + test_load | OFFLINE | 402 passed | pass (sound/chat line in game NOT-VERIFIED) | 2026-11-27 |
| R7 | Text limits, own-name sending, caps | test_order_chat "bad entries are dropped", "AddMessage trims ...", "newest 30"; test_sync "forged chat author" | OFFLINE | 402 passed | pass | 2026-11-27 |
| RF1 | No endless OPUSH to 2.8 peers | test_sync "a HELLO without xdig (2.8 peer) gets no OPUSH for chat"; test_order_chat "Missing pushes chat only ..." | OFFLINE | 402 passed | pass | 2026-11-27 |
| RF2 | Forged author dropped | test_sync "ORDER broadcasts leave the chat out; a forged chat author is dropped" | OFFLINE | 402 passed | pass | 2026-11-27 |
| RF3 | 31st message, same result everywhere | test_order_chat "the newest 30 are kept, the same ones on every client" | OFFLINE | 402 passed | pass | 2026-11-27 |
| RF4 | OPUSH with full chats under the size limit | test_sync "OPUSH batches with full chats stay under the message size limit" | OFFLINE | 402 passed | pass | 2026-11-27 |
| RF5 | Garbage entries never drop the order | test_order_chat "bad entries are dropped, the order still merges" | OFFLINE | 402 passed | pass | 2026-11-27 |
| Tools | `GetTradeSkillTools` on Forever | in-game scan | NOT-VERIFIED | needs the user | open | |

## In-game checklist (things only the user can do)
- [ ] Restart the game (new file in the TOC; `/reload` is not enough), `/console scriptErrors 1`.
- [ ] Orders tab: each row has a speech-bubble icon first in the action column; hover says "Order details, chat and history".
- [ ] Click it: the window shows the order; Overview lists status, requester, reagents x quantity with "have n", tools, who knows it.
- [ ] Chat tab: type a message, Enter -> it appears at the bottom; `/psd fake order` then open that order and write.
- [ ] History tab: create, claim, withdraw, mark done an order; each step appears with date and time.
- [ ] Open a profession (classic window) once, then the Overview of an order for a recipe with a tool (e.g. a smelting
  or blacksmith recipe): "Tools" lists it. If not, the client has no `GetTradeSkillTools`.
- [ ] With a second member on the new build: a message from them on your order -> number on the minimap button, sound,
  chat line "Name about Recipe: text"; the row's icon shows 1; opening the chat clears it.

## In-game result
- 2026-11-27, user, one client with `/psd fake order` and `/psd fake chat`: "looks and works fine" (after the
  strata fix: "it looks like some elements are rendered on the same z layer" was the only problem). R1, R2, R3, R4, R6
  are IN-GAME for one client.

## Accepted gaps
- R5 (two real members chatting) and Tools (`GetTradeSkillTools` on Forever): not checked; accepted by the user's
  release request for 1.6.0 on 2026-11-27.

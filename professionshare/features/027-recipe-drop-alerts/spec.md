# 027 Recipe drop alerts: spec

- Status: done
- Created: 2026-11-24
- Target version: 1.4.0 (protocol 2.7, schema unchanged)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
When a tradeable recipe drops into my bags, the guild members (with the addon) who can learn it now are told, and I can
see in the item's tooltip who answered: up to 3 names with their skill, green = can learn it, red = skill too low.

## Requirements
- R1: Trigger: my own loot line ("You receive loot", not pushed items, not other players' loot) with a recipe item that
  reaches my bags within 10 s and does not bind on pickup -> `DROP {item}` on GUILD, once per loot line.
- R2: Receiver: reads the item's tooltip on its own client (RecipeCheck): learnable -> alert + whisper `DROPA {item, s="g",
  r=rank}`; skill too low -> `DROPA {s="r"}` without alert; known / no profession / unreadable -> nothing. Not-loaded item
  data is retried (3 tries, 2 s apart).
- R3: Alert (each switchable): a chat line from the addon ("<link> dropped for <looter>: you can learn it (<skill>)"),
  the minimap button's news icon with the drop in its tooltip until the window is opened.
- R4: Looter: a chat line "<link> dropped: hover it to see who can use it" (chat switch); any tooltip of that item
  (bags, chat link hover, clicked link) shows up to 3 answering members "Name (skill)" green/red, green first then by skill,
  and "..." when more answered; "waiting for answers" / "nobody online can use it" before / without answers.
- R5: Settings (db.ui.drops): share my drops and answer (on), chat line (on), minimap icon (on). `/ps drops` shows
  them, `/ps drops <share|chat|icon> on|off` sets one. (Grouped settings page: 029.)
- R6: Addon users only; no whispers to players without the addon; no rate limit (user), duplicates of the same
  drop from the same sender within 60 s are ignored.
- R7: Dev tools: Triggers "Recipe drop from a member" (incoming DROP for a bag recipe), "Answers to my last drop"
  (fake green/red answers incl. more than 3); results in devChecks.

## Non-goals
- No external data; no offline members in the list (only who answers); no grouped settings page (029).

## Design
- `Core/Data/RecipeDrops.lua` (new, pure): settings (DEFAULTS, Get, Set), my drops (NoteMyDrop, AddAnswer, HintRows, max
  20 drops, answers accepted 15 min), receiver side (SanitizeDrop, SanitizeAnswer, AnswerStatus, IsDuplicate), pending
  alerts (AddAlert, Alerts, ClearAlerts).
- `Core/Net/Sync.lua` (changed): handlers DROP -> `environment.onRecipeDrop(sender, itemID)`, DROPA ->
  `RecipeDrops.AddAnswer`; `sync:BroadcastDrop(itemID)`, `sync:AnswerDrop(target, itemID, status, rank)`.
- `Core/Net/Communication.lua` (changed): wires `onRecipeDrop` to `addon.Drops.OnDrop`; DROP/DROPA priority types.
- `Core/Game/Drops.lua` (new, client glue): CHAT_MSG_LOOT -> bag confirm -> tooltip -> broadcast + chat line; incoming
  DROP -> tooltip read with retries -> answer + alert; tooltip hooks (GameTooltip, ItemRefTooltip, chat link hover);
  `/ps drops`.
- `UI/Window.lua` (changed): `UI.SetDropNotice(alerts)`; minimap icon/tooltip; cleared when the window opens.
- `UI/DevProbe.lua` (changed): two Triggers entries.
- Data shape: `db.ui.drops` settings only (UI table, no schema change). Drops and answers are session memory.
- Message shape: `DROP {item}` (GUILD), `DROPA {item, s = "g"|"r", r}` (WHISPER to the looter). Protocol 2.7 additive.

## Tasks
- [x] T1 (M): RecipeDrops pure module + tests/test_recipe_drops.lua. Verify: offline.
- [x] T2 (S): Sync handlers + send functions, PROTOCOL_MINOR 7. Verify: offline (handler tests, old-peer drop).
- [x] T3 (M): Drops.lua: loot -> confirm -> broadcast; incoming -> read -> answer/alert; tooltip hooks; /ps drops. Verify: test_load.
- [x] T4 (S): minimap notice, deDE strings. Verify: test_load, locale lint.
- [x] T5 (S): Dev tools triggers. Verify: test_load, in game.
- [x] T6 (S): docs (protocol.md section 15, README, CHANGELOG, doc.md). Verify: read.
- [x] T7 (single client; two members accepted as open): in game (single client with fake triggers), then two members.

## Review Focus (failure modes a happy-path test would miss)
1. RF1: hostile DROP / DROPA (bad item id, huge rank, unknown status, answer for an item I never dropped) -> dropped. Pinned by: T1, T2.
2. RF2: a 2.6 peer gets DROP -> drops it as unknown type, no error. Pinned by: T2.
3. RF3: peer names in tooltip / chat lines are escaped. Pinned by: T1.
4. RF4: item data not loaded on the receiver -> retried, then silent; never an error. Pinned by: T3.
5. RF5: share switched off -> no DROP sent and no answers given. Pinned by: T3.

## Cross-cutting checklist (answer every line; "n/a: reason" is fine)
- [x] Protocol: additive bump to 2.7 (DROP, DROPA); older peers drop unknown types.
- [x] Stored data: `Store.SCHEMA` unchanged (settings in `ui.drops`, drops in memory).
- [x] Trust model: allow-list sanitizers for both messages; names escaped before display.
- [x] Localization: only ids, status letter and rank travel; texts through `Text[]` with deDE.
- [x] Load order: RecipeDrops.lua after RecipeCheck.lua; Drops.lua after Events.lua (needs Events, RecipeCheck, Api).
- [x] Packaging: no change.
- [x] Tests: tests/test_recipe_drops.lua; test_load (commands, hooks, dev triggers).
- [x] Docs: protocol.md 15, README, CHANGELOG, doc.md, status.md.

## Decisions (user answers and design choices, newest last)
- 2026-11-24: trigger only my own loot that reaches my bags (user).
- 2026-11-24: alert only members who do not know it and have the skill (user); red names = skill too low (user).
- 2026-11-24: chat hint and/or minimap icon, each switchable (user); addon users only (user).
- 2026-11-24: looter's chat line, list in the hover tooltip, max 3 names then "..." (user); number = current skill (user).
- 2026-11-24: no rate limit (user); a duplicate DROP within 60 s is ignored (claude: retries must not alert twice).
- 2026-11-24: bind-on-pickup recipes are not announced (claude: nobody else can use them).
- 2026-11-24: in-game data only; each receiver decides from its own tooltip (user, after 026 proved it on Forever).

## Open questions
- Does the real loot line come before or after the item is in the bags? (game; handled both ways by waiting up to 10 s)

# 036 Item batch: catch charms, care items, arena buffs, minigame items: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.

Baseline before work: `luajit tests/run.lua` -> 171 passed, 0 failed (release 0.9.1)
Result after work:    `luajit tests/run.lua` -> 180 passed, 0 failed

Test names below are from `tests/test_item_batch.lua` unless another file is named.

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence (output line, file, screenshot) | Result | Date |
|---|---|---|---|---|---|---|
| R1 | Five groups in order, every item buyable with the existing checks | test_items "the catalog guard" (groups, kinds, kind fields, translations) | OFFLINE | 180 passed, 0 failed | pass | 2026-11-25 |
| R1 | Shop and inventory show the new groups | simulator | NOT-VERIFIED | evidence/sim-shop.png, evidence/sim-inventory.png (simulator only; needs in-game) | sim ok | 2026-11-25 |
| R2 | One charm slot, owned once, equip/swap/off for free | "a charm is bought once, equipped in the one slot, swapped and taken off for free" | OFFLINE | 180 passed, 0 failed | pass | 2026-11-25 |
| R2 | Charm effects on catches, none when not equipped (Second Chance: one more throw after a slipped rope) | "charm effects on catches (reward, lure, best moment, second throw); none without equipping" | OFFLINE | 180 passed, 0 failed | pass | 2026-11-25 |
| R3 | Feast, Toy, refusals keep the item; Elixir stops the decay for 4 h | "Feast and Toy fill their needs, a refusal keeps the item; the Elixir stops the decay" | OFFLINE | 180 passed, 0 failed | pass | 2026-11-25 |
| R4 | Buffs in the fighter stats, `bf` ids, charges, no stacking of one buff | "arena buffs raise the published fighter, list their ids and are spent per published fighter" | OFFLINE | 180 passed, 0 failed | pass | 2026-11-25 |
| R4 | A challenge spends once; buff icons are shown on both sides | "a challenge spends the buffs once; ..." | OFFLINE | 180 passed, 0 failed | pass (icons: in-game) | 2026-11-25 |
| R5 | Dash Shield, Head Start, the `it`/`bi` marks, board and feed rows | "the Dash Shield absorbs one hit, the Head Start starts at 200 m and pays only beyond it"; "runner items are used only when a run starts" | OFFLINE | 180 passed, 0 failed | pass | 2026-11-25 |
| R5 | Survivor Bomb: once per run, at most a 250g stake, the play is marked | "the Survivor Bomb clears the screen once per run, only up to a 250g stake; the play is marked" | OFFLINE | 180 passed, 0 failed | pass | 2026-11-25 |
| R5 | Toggles beside Start, the bomb button, the bag icon on boards | simulator | NOT-VERIFIED | evidence/sim-runner.png, evidence/sim-survivor.png (simulator only; needs in-game) | sim ok | 2026-11-25 |
| R6 | `equipped` and `arenaBuffs` sanitized at load | "saved charm slot and arena buffs are sanitized" | OFFLINE | 180 passed, 0 failed | pass | 2026-11-25 |
| RF1 | A peer's `bf` with garbage, repeats or too many ids | "arena buffs raise the published fighter ..." (SanitizeFighter cases) | OFFLINE | 180 passed, 0 failed | pass | 2026-11-25 |
| RF2 | Charges used once per published fighter; a withdrawn or declined challenge keeps them used | "a challenge spends the buffs once; ..." | OFFLINE | 180 passed, 0 failed | pass (withdraw: READ-ONLY) | 2026-11-25 |
| RF3 | The equipped charm not owned or unknown | "saved charm slot and arena buffs are sanitized"; `Items.Equipped` checks the count | OFFLINE | 180 passed, 0 failed | pass | 2026-11-25 |
| RF4 | The Elixir and the clock going back | "Feast and Toy ... the Elixir stops the decay" (a tick with an earlier time) | OFFLINE | 180 passed, 0 failed | pass | 2026-11-25 |
| RF5 | A 1.4 peer computes the same fight | "a challenge spends the buffs once; the fight is the same for a client that drops bf" | OFFLINE | 180 passed, 0 failed | pass | 2026-11-25 |
| UI | The new UI loads without Lua errors | `tools/wow-sim.ps1 -Mode shot`, four scenarios (`evidence/sim-items.lua`) | NOT-VERIFIED | 0 GuildGames errors in last-guildgames-errors.json (simulator) | sim ok | 2026-11-25 |
| ALL | user's status review | user, live use | IN-GAME | user: "shows and helps and works" | pass | 2026-11-28 |

## In-game checklist (things only the user can do)
- [ ] Shop: the groups Charms, Care, Arena and Games appear. Buy a charm; Buy is then greyed out ("owned once").
- [ ] Inventory: Equip a charm. The Charms header shows "Equipped: ...", and Take off empties the slot.
- [ ] Catch with Lucky Charm equipped: the reward is 10% higher than without (compare the ledger entries).
- [ ] Feast and Squeaky Toy fill the bars. Using one on full bars says "needs nothing of it now" and keeps the item.
- [ ] Care Elixir: the bars stay where they are for a while.
- [ ] Arena buffs:
  - Use War Paint. The fighter line in the Arena tab shows its icon.
  - Challenge someone. The inventory shows "(2 fights left)", and the opponent sees the icon in the fight details.
- [ ] Companion Dash:
  - Arm the shield and Head Start beside Start, then run.
  - The first hit shows "Shield!", the run starts at 200 m, and a bag icon follows the run in the feed.
- [ ] Survivor:
  - With a stake of at most 250g, the bomb button (bottom left) clears the screen once.
  - At a higher stake it is greyed out with the reason.
- [ ] Second client (MULTI-CLIENT): an older version (0.9.1) sees the same fight winner against a buffed fighter.

## Accepted gaps
- Checklist steps not run one by one and the two-client rows: closed at the user's status review (2026-11-28, "shows and helps and works").

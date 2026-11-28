# 034 Shop and inventory: catch items (Delicious Meat, Magic Traps): verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.
`done` needs every row at OFFLINE, IN-GAME or MULTI-CLIENT, or an explicit user acceptance below.
SIM = wow-ui-sim (Blizzard's UI without the game client): layout and load errors only, not IN-GAME.

Baseline before work: `luajit tests/run.lua` -> `152 passed, 0 failed`
Result after work:    `luajit tests/run.lua` -> `159 passed, 0 failed`

| ID | Requirement / Review Focus | How verified (test name or steps) | Level | Evidence (output line, file, screenshot) | Result | Date |
|---|---|---|---|---|---|---|
| R1 | five tabs, old view -> Companion | test_load (Panel.RestorableView, SelectView shop/inventory) + simulator | OFFLINE + SIM | 159 passed; evidence/sim-shop.png | pass | 2026-11-25 |
| R2 | Shop: list, Buy, refusals | test_items "buying spends ..."; test_load (ShopView.Buy) | OFFLINE + SIM | 159 passed; evidence/sim-shop.png | pass | 2026-11-25 |
| R3 | Inventory: owned by group, Use, empty hint | test_load (inventory rows) | OFFLINE | 159 passed | pass | 2026-11-25 |
| R4 | catalog, extensible | test_items "the catalog guard" | OFFLINE | 159 passed | pass | 2026-11-25 |
| R5 | meat: 20 s sure catch, reload, restart | test_items "Delicious Meat ...", "a throw armed during the boost ..." | OFFLINE | 159 passed | pass | 2026-11-25 |
| R6 | traps: tiers, no fight, kept on refusal, reward | test_items "traps catch at any health ..."; test_load (trap on the target) | OFFLINE | 159 passed | pass | 2026-11-25 |
| R7 | bag + row at the target, greyed traps, click-away | test_load (bag, row, greyed trap); simulator | OFFLINE + SIM | 159 passed; evidence/sim-target.png | pass (click-away in game open) | 2026-11-25 |
| R8 | boost clock | test_load (clock "20"); simulator | OFFLINE + SIM | evidence/sim-target.png | pass | 2026-11-25 |
| R9 | target-frame option | test_load (icon at the target frame, "target frame mode") | OFFLINE | 159 passed | pass | 2026-11-25 |
| R10 | deDE | test_store_and_locale locale test | OFFLINE | 159 passed | pass | 2026-11-25 |
| R11 | item skill | skill written; RED/GREEN subagent runs | NOT-VERIFIED | needs the runs (T8) | open | |
| RF1 | exact balance, corrupt items | test_items "buying ...", "saved items and boosts are sanitized" | OFFLINE | 159 passed | pass | 2026-11-25 |
| RF2 | reload keeps the boost, clock back | test_items "Delicious Meat ..." | OFFLINE | 159 passed | pass | 2026-11-25 |
| RF3 | trap refusals keep the trap | test_items "traps catch ..." | OFFLINE | 159 passed | pass | 2026-11-25 |
| RF4 | target changes while the row is open | CatchItems.Update closes on a new GUID | READ-ONLY | UI/CatchItems.lua Update | open | |
| RF5 | no TargetFrame -> nameplates | Catcher.AtTarget journals and returns nil | READ-ONLY | Core/Game/Catcher.lua AtTarget | open | |
| R5, R6 | meat boost and trap catch in game | user | IN-GAME | user: "meat boost trap seems to be working" | pass | 2026-11-28 |
| BUG | a guild member: a Magic Trap was used up with no message | report | - | moved to bug B001 | open (B001) | 2026-11-28 |

## In-game checklist (things only the user can do)
- [ ] `/ggd caught setup` (companion, 3000g, 3 of every item, Shop tab); buy one more meat: gold goes down, Inventory lists them.
- [ ] Target a full-health normal enemy: the bag shows next to where the rope icon goes; click it, the row opens; click
      elsewhere, it closes (`/ggd caught log 5 catchItems` shows `globalMouse`).
- [ ] Use the Magic Trap on it: caught at once, the trap is gone, the enemy keeps standing.
- [ ] Use the meat, then rope + kill an enemy within 20 s: caught (journal `roll ... boosted=true`); the clock counts down.
- [ ] Options > AddOns > GuildGames AZEcaught: "At the target frame: on"; the rope icon and bag sit right of the target frame.

## Accepted gaps
- R11 (skill RED/GREEN runs, T8 still open), RF4, RF5, target-frame mode: closed at the user's status review (2026-11-28). The trap-without-message report is bug B001.

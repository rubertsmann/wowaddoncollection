# 047 Notification scope dropdown and profession level scope: verification

Levels: `OFFLINE` (luajit suite) | `IN-GAME` (WoW client, evidence from user or disk) | `MULTI-CLIENT` (two real guild members) | `READ-ONLY` (reasoned, not run) | `NOT-VERIFIED`.

Baseline before work: `luajit tests/run.lua` -> `385 passed, 0 failed`
Result after work:    `luajit tests/run.lua` -> `387 passed, 0 failed`

| ID | Requirement / Review Focus | How verified | Level | Evidence | Result | Date |
|---|---|---|---|---|---|---|
| R1 | Dropdown with the four scopes (cycling button as fallback) | `test_load` builds the settings page (stub dropdown) | READ-ONLY (look) | suite 387 | pending in game | 2026-11-27 |
| R2 | Level scope: known, or my rank >= the recipe's rank | `notify: level scope: my rank reaches the lowest rank ...` | OFFLINE | suite 387 | pass | 2026-11-27 |
| R3 | Recipe rank: catalog minSkill, else lowest knower; none -> no | `notify: level scope uses the catalog rank ...` | OFFLINE | suite 387 | pass | 2026-11-27 |
| R4 | Hint per scope | code (`scopeHint`, refreshed with the panel) | READ-ONLY | - | pending in game | 2026-11-27 |
| RF1 | Nobody knows the recipe -> not news | level test (recipe 555) | OFFLINE | suite 387 | pass | 2026-11-27 |
| RF2 | My own rank never counts as the recipe's rank for a recipe I do not know | `RecipeRanks` only reads records that know the recipe | OFFLINE (READ-ONLY reasoning) | suite 387 | pass | 2026-11-27 |
| RF3 | Rank of another profession ignored | level test (Tailoring 40 vs 50) | OFFLINE | suite 387 | pass | 2026-11-27 |
| RF4 | "level" is a valid stored value, unknown values fall back | catalog-rank test (`Get` with "level"); existing settings test ("evil") | OFFLINE | suite 387 | pass | 2026-11-27 |

## In-game checklist (user)
`/reload`, `/ps options` (dev: `/psd options`) -> Order notifications.
- [ ] "Tell me about" is a dropdown listing: Orders for recipes I know, Orders I have the profession level for, Orders for my professions, All orders; the hint under it changes with the choice; the choice survives `/reload`.
- [ ] With "Orders I have the profession level for": an order (e.g. `/psd fake order`) for a recipe you do not know, in a profession where your rank is at least the lowest rank of a member who knows it, raises the notification.

## Accepted gaps
- R1, R4 (dropdown and hint seen in game): not reported back separately; accepted by the user's release request
  for 1.6.0 on 2026-11-27.

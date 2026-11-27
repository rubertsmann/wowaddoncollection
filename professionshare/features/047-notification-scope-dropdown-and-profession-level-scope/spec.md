# 047 Notification scope dropdown and profession level scope: spec

- Status: done
- Created: 2026-11-27
- Target version: next (UI + local setting; protocol and schema unchanged)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
The settings' "Tell me about" choice becomes a dropdown showing every option, with a new option for orders whose
recipe my profession rank is high enough for.

## Requirements
- R1: Settings page, section Order notifications: "Tell me about" is a dropdown (radio list) instead of the cycling
  button: Orders for recipes I know, Orders I have the profession level for, Orders for my professions, All orders.
  Without menu support on the client the cycling button stays.
- R2: New scope "level": another member's open order is news when I know the recipe, or when my rank in the recipe's
  profession is at least the recipe's rank, even if I do not know the recipe yet.
- R3: The recipe's rank: the catalog's `minSkill` when present; else the lowest rank among the guild members who know
  the recipe (in that profession). Without either, the order is not news in this scope (no false "yes").
- R4: The hint under the dropdown explains the selected scope (incl. how the recipe's rank is found).

## Non-goals
- No recording of real recipe ranks from tooltips (the user chose the rank rule; the estimate covers it).
- "Orders I can craft" is the existing "Orders for recipes I know" (user: no new option).

## Design
- `Core/View/Notify.lua`: `SCOPES` gets "level"; `Relevant` handles it; `RecipeRanks(store, recipeID)` (pure).
- `UI/Alerts.lua`: dropdown (`WowStyle1DropdownTemplate`, radio), fallback cycling button; hint per scope.
- `Locales/deDE.lua`: new strings.
- Data: `db.ui` notify scope value "level" (validated by `Notify.Get`; unknown values fall back to the default).

## Tasks
- [x] T1 (S): `Notify.RecipeRanks` + "level" scope + tests in `tests/test_notify.lua`.
- [x] T2 (S): settings dropdown + hint + locale; `test_load` builds the page.
- [x] T3 (S): docs, verify.

## Review Focus (failure modes a happy-path test would miss)
1. RF1: Recipe known by nobody with a rank (no catalog rank, no knowers) -> not news, no error. Pinned by: T1.
2. RF2: The lowest knower is me (I know it) -> covered by "known"; my own rank must not count as the recipe's rank for
   a recipe I do not know. Pinned by: T1.
3. RF3: A profession entry without a rank, or a rank from another profession -> ignored. Pinned by: T1.
4. RF4: An old saved scope value stays valid; an unknown one falls back to the default. Pinned by: T1.

## Cross-cutting checklist (answer every line; "n/a: reason" is fine)
- [x] Protocol: unchanged.
- [x] Stored data: schema unchanged; one more allowed value of an existing local setting.
- [x] Trust model: ranks come from sanitized peer records (0..1000); nothing displayed from peers here.
- [x] Localization: labels and hints through `Text`.
- [x] Load order: no new files.
- [x] Packaging: n/a.
- [x] Tests: `tests/test_notify.lua` (2 new), `test_load` builds the settings page with the dropdown.
- [x] Docs: README, CHANGELOG, docs/status.md, doc.md.

## Decisions (user answers and design choices, newest last)
- 2026-11-27: Dropdown instead of the cycling button (user).
- 2026-11-27: "Orders I can craft" = the existing "Orders for recipes I know"; no new option (user).
- 2026-11-27: "Profession level" = the recipe's rank is lower or equal to my profession rank, known or not (user).
  The addon has no recipe ranks (the scan never fills `minSkill`), so the rank is the lowest rank of any member who
  knows the recipe: they learned it at that rank or lower, so it never says yes wrongly; `minSkill` wins when present (design).

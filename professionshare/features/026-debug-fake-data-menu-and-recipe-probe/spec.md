# 026 Debug fake data menu and recipe probe: spec

- Status: done
- Created: 2026-11-24
- Target version: 1.4.0 (dev tools only; the recipe check module ships unused until 027)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
Step 1 of "recipe drop alerts": prove with in-game data only (no external data) that a client can tell from a recipe
item's own tooltip whether this character can learn it, and that my own loot can be told apart from other loot; and
give the Debug tab one grouped, normalized way to add fake data, fire fake triggers and remove all fake data again.

## Requirements
- R1: The Debug tab has one "Dev tools" menu (dev build only) with sections Members (fake data), Triggers (fake
  events), Probes and "Remove all fake data". It replaces the six loose buttons; the same entries run as
  `/psd fake <key>` (`/psd fake` lists them).
- R2: Every fake member is made by one helper: name `Fake <Role>` in the canonical form, remembered in the dev
  SavedVariables (`devFake`) so it survives `/reload` and is kept from the roster prune.
- R3: "Remove all fake data" removes every fake member from chars, offers, access, rep and feedback, and nothing else.
- R4: Recipe probe (`/psd recipeprobe [itemID ...]`, menu Probes): for every recipe item in my bags (and the asked ids)
  it reads the item tooltip with line colours and records: profession named in "Requires X (n)", required skill,
  whether that line is red, "Already known", "Binds when picked up", my stored skill in that profession, and the
  decision (learnable | low | known | noProfession | unreadable). Colour and own-skill decisions are compared and a
  mismatch is flagged.
- R5: Loot recorder (dev build, passive): every loot chat line with a recipe item is recorded with which client
  format matched (own loot, own pushed item, someone else) and whether the item reached my bags within 10 s.
- R6: Fake trigger "Recipe loot (me)": a loot line built from the client's own format with a recipe item from my bags
  runs through the same recorder and probe.
- R7: Every probe, trigger and fake action writes a machine-readable result to `db.devChecks` (ProfessionShareDevDB),
  so the results can be read from the WTF file after `/reload` and checked automatically.

## Non-goals
- No sending, no alerts, no settings page (027 recipe drop alerts, 029 grouped settings page).
- No external recipe data; no item -> recipe mapping.
- Nothing of the menu, recorder or probe in the live build.

## Design
- `Core/Data/RecipeCheck.lua` (new, pure, ships): `PatternFromFormat`, `ReadTooltip(lines, strings)`,
  `Decide(reading, myProfessions)`, `ParseLoot(message, formats)`. Used by 027 later.
- `Core/Game/Api.lua` (changed): `Api.ItemTooltipLinesWithColor(itemOrLink)`, `Api.BagRecipeItems()`,
  `Api.RecipeCheckStrings()` (the client's own format strings: ITEM_MIN_SKILL, ITEM_SPELL_KNOWN,
  ITEM_BIND_ON_PICKUP, LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_PUSHED_SELF, LOOT_ITEM_PUSHED_SELF_MULTIPLE,
  LOOT_ITEM, LOOT_ITEM_MULTIPLE).
- `UI/DevProbe.lua` (changed): shared fake-member helper, `DevProbe.ENTRIES` (key, section, label, run),
  `RemoveFakeData`, `RecipeProbe`, loot recorder, `/psd fake`, `/psd recipeprobe`; results via `recordCheck`.
- `UI/Window.lua` (changed): the six fake buttons and "Item probe" become one "Dev tools" dropdown built from
  `DevProbe.ENTRIES`.
- Data shape change: dev SavedVariables only: `devFake[name] = role`, `devChecks[key] = result` (not sanitized, not
  sent, dev build only). `Store.SCHEMA` unchanged.
- Message shape change: none.

## Tasks
- [x] T1 (M): `RecipeCheck` pure module + `tests/test_recipe_check.lua`. Verify: offline suite.
- [x] T2 (S): Api tooltip lines with colours, bag recipe items, client strings. Verify: test_load stubs.
- [x] T3 (M): DevProbe: fake-member helper, entries, remove, checks, recipe probe, loot recorder, commands. Verify: test_load.
- [x] T4 (S): Window: "Dev tools" menu replaces the buttons; deDE strings. Verify: test_load, locale lint.
- [x] T5 (S): in-game: probe on real recipe items, loot one recipe, read `devChecks` from the WTF file. Verify: IN-GAME.

## Review Focus (failure modes a happy-path test would miss)
1. RF1: recipe tooltips embed the created item's tooltip, which can have its own "Requires ..." line -> only the LAST
   "Requires <profession> (n)" counts (Forever shows the created item first, the recipe's requirement last). Pinned by: T1.
2. RF2: German format strings ("Benötigt %s (%d)") and positional forms ("%1$s") -> pattern built from the client
   string, not English text. Pinned by: T1.
3. RF3: item not cached yet -> "unreadable", retried once, never an error. Pinned by: T1, T3.
4. RF4: someone else's loot line ("X receives loot") must never count as mine. Pinned by: T1.
5. RF5: remove-all must not touch real members whose name starts with "Fake" by chance -> only names in `devFake`
   plus the four legacy fake names. Pinned by: T3.

## Cross-cutting checklist (answer every line; "n/a: reason" is fine)
- [x] Protocol: unchanged (nothing sent).
- [x] Stored data: `Store.SCHEMA` unchanged; dev-only top-level keys `devFake`, `devChecks`.
- [x] Trust model: n/a, reads only my own client.
- [x] Localization: parsing uses the client's own global format strings; menu labels are dev-only English (like DevProbe), the menu button is `Text["Dev tools"]`.
- [x] Load order: `RecipeCheck.lua` after `Reputation.lua` in both TOCs and `tests/run.lua`.
- [x] Packaging: no change (new file is in Core/).
- [x] Tests: `tests/test_recipe_check.lua` (RF1, RF2, RF4), test_load (menu, commands, remove).
- [x] Docs: doc.md, CHANGELOG line (dev tools), docs/status.md.

## Decisions (user answers and design choices, newest last)
- 2026-11-24: in-game data only, no external data (user). Each client decides from its own tooltip.
- 2026-11-24: trigger is my own loot that reaches my bags (user).
- 2026-11-24: step 1 = debug rework + assumption probes before the drop feature (user: "implement the first step so we can check for assumptions").
- 2026-11-24: fake inputs grouped in one menu (choice A(a), proposed; user went ahead).

## Open questions
- Is the "Requires X (n)" line red exactly when my skill is too low on Forever? (needs: game, T5)
- Do recipe tooltips on Forever show "Already known"? (needs: game, T5)

# 017 Enchant effect text: spec

- Status: done
- Created: 2026-11-18
- Target version: 0.7.2 (UI only, client data)
- Owner: claude
- Links: [log](log.md) | [verify](verify.md) | [doc](doc.md)

## Goal
Recipes that make no item (enchants) show what they do: the effect text in the recipe tooltip and the detail panel,
and the free-text search finds them by it.

## Requirements
- R1: Hovering the icon of a recipe without an item shows its effect text (green) under the name, when the client knows it.
- R2: Selecting such a recipe shows the effect as one line under the title in the detail panel.
- R3: The Recipes search matches the effect text of recipes without an item (as feature 011 does for item effects).
- R4: The text is read on the viewer's own client, in their language, by recipe id as spell id: spell description first,
  then the `spell:` and `enchant:` tooltips. Nothing new is stored or sent. What each source returned is logged once
  per recipe (`window.effectProbe`, debug level).
- R5: Dev build only: Debug tab button / `/tsd fakeenchanter` adds an in-memory "Fake Enchanter" with six enchants, kept
  from the roster prune (`Store.keptNames`, empty in the live build), to test without a real enchanter.

## Non-goals
- No effect text for recipes whose spell the client does not know; no syncing of effect texts between players.
- No effect column in the Recipes table.

## Design
- `Core/Game/Api.lua`: `Api.SpellDescription` (requests the spell load when empty), `Api.HyperlinkTooltipLines` (the
  hidden-tooltip reader of feature 011, generalised from items to any link).
- `UI/Window.lua`: `recipeEffectText` (three sources, session cache, one log line per recipe); tooltip line, detail line,
  `itemLookups.effect` for the search.
- `Core/View/Model.lua`: `BuildRecipeRows` searches `lookups.effect(recipeID)` for recipes without `produces`.
- `Core/Data/Store.lua`: `Store.keptNames` (names Prune never drops).
- `UI/DevProbe.lua`: `DevProbe.AddFakeEnchanter`, `/tsd fakeenchanter`; button in the Debug tab (dev build).
- Data shape / message shape: none.

## Tasks
- [x] T1 (S): Api spell description + generic tooltip reader. Verify: test_load, in game
- [x] T2 (S): tooltip + detail line. Verify: in game
- [x] T3 (S): search via `lookups.effect`. Verify: `tests/test_effect_probe.lua`
- [x] T4 (S): dev fake enchanter + `Store.keptNames`. Verify: `tests/test_effect_probe.lua`, in game
- [x] T5 (S): docs, release 0.7.2

## Review Focus
1. RF1: spell not loaded yet -> no text on the first hover, text on the next (load requested); search catches up on the next keystroke. Pinned by: READ-ONLY (Api.SpellDescription)
2. RF2: recipe with an item -> never asked for a spell text. Pinned by: test "search: an enchant is found by its effect text..."
3. RF3: effect text is client text, still escaped before display. Pinned by: READ-ONLY (`Utility.Escape` at both display points)
4. RF4: the prune exemption cannot keep real former members. Pinned by: test "prune: a name in Store.keptNames survives..."

## Cross-cutting checklist
- [x] Protocol: unchanged; nothing sent.
- [x] Stored data: unchanged (texts cached in memory only).
- [x] Trust model: effect text comes from the viewer's client, escaped before display.
- [x] Localization: the client's own language; new UI label "Fake enchanter" (dev only) in deDE.
- [x] Load order: no new files.
- [x] Packaging: no change.
- [x] Tests: `tests/test_effect_probe.lua` (2 tests).
- [x] Docs: README, CHANGELOG, RELEASE_NOTES, docs/status.md, docs/api-findings.md, doc.md.

## Decisions
- 2026-11-18: read the text locally by recipe id = spell id instead of syncing it from the enchanter (user has no enchanter; the ids in the live data are classic spell ids).
- 2026-11-18: test with an in-memory fake enchanter from the Debug tab (user), since copied records were dropped by the version reset.

## Open questions
- Which of the three sources delivers the text on Forever: answered by the `window.effectProbe` log after a `/reload` (needs: game).

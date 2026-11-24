# Debug fake data menu and recipe probe

Status: done | Since version: 1.4.0 (unreleased, dev build only) | Spec: [spec](spec.md) | Verification: [verify](verify.md)

## What it does
Dev build only. The Debug tab has one **Dev tools** menu instead of six loose buttons: Members (fake guild members with
recipes, keys, attunements, feedback), Triggers (fake events: realm request, recipe loot as me or as another player),
Probes (recipes in my bags, item probe of the catalog) and Cleanup (remove all fake data). The recipe probe and the loot
recorder check, with in-game data only, what a recipe drop alert would rely on.

## How to use
- UI: `/psd debug` -> Debug tab -> "Dev tools".
- Commands: `/psd fake` (list), `/psd fake <key> [itemID]` (keys: enchanter, keys, naxx, feedback, request, loot,
  lootother, recipes, items, remove), `/psd recipeprobe [itemID ...]`, `/psd itemprobe [itemID ...]`. The old
  `/psd fakeenchanter|fakekeys|fakenaxx|fakefeedback|fakerequest` still work.
- Results: `/reload`, then `WTF\Account\<ACCOUNT>\SavedVariables\ProfessionShare-Dev.lua` -> `devChecks`
  (`recipes`, `loot`, `lootOther`, `lootLines`, `remove`, one key per member action).

## How it works
- Data (dev SavedVariables only): `devFake[name] = role` (fake members, kept from the roster prune after `/reload`),
  `devChecks[key] = result` (with `at`, `version`), `devChecks.lootLines` (last 20 recipe loot lines).
- Messages: none; nothing of this is sent.
- Modules: `Core/Data/RecipeCheck.lua` (pure: patterns from the client's own format strings, tooltip reading, decision,
  loot line kind); `Core/Game/Api.lua` (`BagRecipeItems`, `RecipeCheckStrings`, `ItemTooltipLinesWithColor`);
  `UI/DevProbe.lua` (fake members, entries, probe, recorder, commands); `UI/Window.lua` (the menu).
- Decision of the probe: learnable (my stored skill >= required), low, known ("Already known"), noProfession,
  unreadable (no "Requires X (n)" line or item not loaded). A red requirement line that disagrees with my stored skill
  is flagged as a mismatch.

## Localization
The parsing uses the client's own global strings (ITEM_MIN_SKILL, ITEM_SPELL_KNOWN, ITEM_BIND_ON_PICKUP, LOOT_ITEM_*),
so it works in every client language. Menu entries are dev-only English; the menu button is translated.

## Limits and known issues
- My stored skill is as fresh as my last profession scan; a mismatch with the red colour points at a stale skill.
- Another player's loot line is stored without the player's name.

## Verification
See [verify.md](verify.md).

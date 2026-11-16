# API findings for WoW Forever (interface 16001)

**Status: INCONCLUSIVE. The probe (`dev/TalentShareProbe`, `/tsp`) has not been run in the game yet.** Replace this
file with the probe's results (`TalentShareProbeDB.lua`) once it has.

## Static evidence (read from addons installed in `_forever_\Interface\AddOns`, no game started)

* Auctionator's TOC lists `16001` in `## Interface:` but its `[AllowLoadGameType ...]` filters only name
  `vanilla, tbc, wrath, cata, mists, mainline, classic`. Forever (`camelot` / `forever`) is not named, so which of
  Auctionator's code paths Forever runs is not determinable from the files.
* Auctionator ships both profession API families: modern `C_TradeSkillUI.GetRecipeSchematic(recipeID, false, level)`
  (`Source_Mainline`) and legacy `GetTradeSkillReagentInfo(recipeIndex, reagentIndex)` / `GetTradeSkillInfo`
  (`Source_Classic`). This is why `Core/Api.lua` supports both and picks at runtime.
* No installed addon calls `GetAllRecipeIDs`, so there is no evidence about the recipe-listing call on Forever.

## Already known from public docs (third-party, unverified on the live client)

* `GetSpellInfo`, `GetItemInfo`, `GetTalentInfo` globals are reported missing on Forever beta builds; use
  `C_Spell.GetSpellInfo` / `C_Item.GetItemInfo`. `Core/Api.lua` only uses `C_Item.*` first for item data.
* TOC per-client suffixes: `_Forever.toc` / `_Camelot.toc` (wiki); this addon uses a single `TalentShare.toc` with
  `## Interface: 16001`.

## To do

Run the probe, then fill in: which recipe-list API exists, where reagents come from, whether recipe IDs are spell IDs.

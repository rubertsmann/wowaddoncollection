# API findings for WoW Forever (interface 16001)

**Status: VERIFIED in game (build 1.60.1 / 70938, 2026-11-16), German client (deDE), character with Leatherworking,
Skinning, Cooking.** Source: `TalentShareProbeDB` plus a `/ts scan` / `/ts dump` run (screenshot in `screens-debug/`).

## What Forever provides (probe `apis` table)

| Need | API that exists | Legacy API (all absent) |
|---|---|---|
| Professions | `GetProfessions`, `GetProfessionInfo` | `GetNumSkillLines`, `GetSkillLineInfo` |
| Recipe IDs | `C_TradeSkillUI.GetAllRecipeIDs` (132 IDs returned for Cooking, includes unlearned) | `GetNumTradeSkills`, `GetTradeSkillInfo` |
| Recipe info | `C_TradeSkillUI.GetRecipeInfo` (has `learned`, `name`, `icon`, `hyperlink`, `categoryID`) | |
| Reagents | `C_TradeSkillUI.GetRecipeSchematic(id, false)` -> `reagentSlotSchematics[].reagents[]`, `quantityRequired`, `outputItemID` | `GetTradeSkillReagentInfo` etc. |
| Items | `C_Item.GetItemInfo`, `C_Item.GetItemNameByID`, `C_Item.GetItemIconByID`, `C_Item.GetItemCount`, `C_Item.RequestLoadItemDataByID` | `GetItemInfo`, `GetItemCount` |
| Spells | `C_Spell.GetSpellInfo` | |
| Addon comms | `C_ChatInfo.RegisterAddonMessagePrefix` / `SendAddonMessage` / `IsAddonMessagePrefixRegistered` | |
| Guild | `IsInGuild`, `GetNumGuildMembers`, `GetGuildRosterInfo`, `C_GuildInfo.GuildRoster` | `GuildRoster` |
| Timers | `C_Timer.After`, `C_Timer.NewTicker` | |

Conclusion: Forever is the modern (Mainline-style) API. `Core/Api.lua` chooses the modern `C_TradeSkillUI` path at
runtime; the legacy branch is dead code on this client and can stay as a fallback.

## Facts the data model relies on

* `recipeID` is NOT a spell ID in the Classic sense but is stable and unique per recipe (e.g. 1263067 Eisenofen,
  2152 Leichtes Rüstungsset). Both classic-era IDs (2152, 9058) and new-style IDs (1229517) appear in one character.
* `GetAllRecipeIDs` lists every recipe of the profession; only those with `learned == true` are the character's.
  Scanner filters on `learned` (confirmed: 23 known out of 132 listed for Cooking, plus 12 + 1 for the others).
* Reagent entries are item IDs plus a required count (`quantityRequired`); names/icons are resolved separately via
  `C_Item`, and may be nil until the item data has loaded (use `RequestLoadItemDataByID`).
* Profession names are localized (here `Lederverarbeitung`, `Kürschnerei`, `Kochkunst`). The addon keys professions by
  localized name, so a guild with mixed client languages would show duplicates (known limitation).
* `TRADE_SKILL_CLOSE` fired in the probe; scans also ran from the profession-window events (`scan changed` log lines).
* Profession record: `{name, icon, skill, maxSkill, ...}`; Cooking 150/150, Leatherworking 35/75, Skinning 131/150.

## Still unverified

* Whether the scan data survives for professions that were not opened since login (scanner needs the window open once).
* Addon-message delivery between two real characters (needs another online guild member), including the throttle limits.

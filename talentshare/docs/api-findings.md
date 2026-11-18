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

Conclusion: Forever is the modern (Mainline-style) API. `Core/Game/Api.lua` chooses the modern `C_TradeSkillUI` path at
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

## Player names (VERIFIED from a user export, 2026-11-16, build 1.60.1 / 70938)

Characters on Forever have a **first name and a surname**. Values from one client (dev build 0.4.1, German client):

| Call | Returned |
|---|---|
| `UnitName("player")` | `"Drakk"`, `"Nuk"`: the surname comes in the 2nd value (retail: realm, nil for the player) |
| `UnitFullName("player")` | `"Drakk"`, `"Nuk"` |
| `GetRealmName()` / `GetNormalizedRealmName()` | `"CAMWOW EU4 Realm 5 PvE"` / `"CAMWOWEU4Realm5PvE"` (one realm for the whole guild) |
| `GetGuildRosterInfo(i)` | `"Drakk Nuk"`, `"Mira Holt"`, ...: **first name + space + surname, no realm suffix** |
| `CHAT_MSG_ADDON` sender (own GUILD echo) | `"Drakk Nuk"` |
| `Ambiguate("Drakk-CAMWOWEU4Realm5PvE", "none")` | `"Drakk"` |

Consequence: a player's identity is `"First Surname"`. Building it as `UnitName() .. "-" .. GetNormalizedRealmName()` (what
0.4.0 did) gives `"Drakk-<realm>"`, which no other source ever uses. Handled in `Api.MyBaseName` / `Utility.CanonicalName` (feature 008).
Not yet verified: whether a whisper addressed to `"First Surname"` is delivered (the trace shows it as `(to Mira Holt)`;
pulls fall back to the guild channel if not).

## Blocked for addons (found in game 2026-11-16)

* `C_TradeSkillUI.OpenTradeSkill(skillLineID)` exists, but calling it from addon code opens nothing and shows the red
  message "Interface-Aktion auf Grund eines Addons fehlgeschlagen" (inferred from the user report, no taint log read).
  `pcall` still returns success because a blocked call raises no Lua error. Professions must be opened by a real click:
  a `SecureActionButtonTemplate` with `type=macro`, `macrotext="/cast <profession>"` (feature 005).
* A profession's recipe list is only readable while that profession's window is open; there is no passive way to read it.
* `GetProfessionInfo` returns the icon as 2nd value (used only for local buttons).

## Item and spell data (dev item probe, feature 011, client 1.60.1 build 70938, deDE, 2026-11-16)

* Only the namespaced APIs exist: `C_Item.GetItemInfoInstant`, `C_Item.GetItemInfo`, `C_Item.GetItemClassInfo`,
  `C_Item.GetItemSubClassInfo`, `C_Item.GetItemSpell`, `C_Item.GetItemStats`, `C_Item.GetItemInventoryTypeByID`,
  `C_Spell.GetSpellInfo`, `C_Spell.GetSpellDescription`, `C_Spell.RequestLoadSpellData`. The old globals
  (`GetItemInfo`, `GetItemInfoInstant`, `GetItemSpell`, `GetSpellDescription`, `GetItemStats`, `GetItemClassInfo`,
  `GetSpellInfo`) are **nil**.
* `C_Item.GetItemInfoInstant` returns id, type name, subtype name, equipLoc (`INVTYPE_HEAD` ...; `_G[equipLoc]` is the
  localized slot), icon, classID, subClassID. Consumable subclasses are specific: 5 = food and drink, 6 = item
  enhancement, 8 = other (camp items). Trade goods 7:6 = leather, quiver 11:2 / ammo pouch 11:3.
* `C_Item.GetItemStats(link)` keys are language independent (`ITEM_MOD_AGILITY_SHORT`, `RESISTANCE0_NAME`).
* Buff food: `C_Item.GetItemSpell` -> spell id; `C_Spell.GetSpellDescription` holds the full effect text
  ("... erhaltet 15 Min. lang 1 Beweglichkeit"). Plural markup `|4Sek.:Sek.;` can appear and must be stripped.
* `C_TooltipInfo.GetItemByID(id).lines[i].leftText` works directly (`TooltipUtil.SurfaceArgs` is nil and not needed);
  same text as a hidden `GameTooltip` scan, but plural markup stays raw.
* Profession window filters: legacy `GetTradeSkillSubClasses` / `GetTradeSkillInvSlots` are nil;
  `C_TradeSkillUI.GetCategories` / `GetCategoryInfo` exist (contents not probed yet).
* UI: `MenuUtil.CreateCheckboxContextMenu`, `MenuUtil.CreateRadioContextMenu`, `WowStyle1DropdownTemplate`,
  `WowStyle1FilterDropdownTemplate`, `SearchBoxTemplate`, `UIDropDownMenuTemplate` all exist.

## Enchant recipes (feature 017, 2026-11-18)

* The recipe id of an enchant is its classic spell id (13419 = Enchant Cloak - Minor Agility, 7418, 7426, 7428, 7771,
  7786 seen in a live guild catalog). Read in game with the dev fake enchanter (deDE, 2026-11-18, `window.effectProbe` log):
  * `C_Spell.GetSpellDescription(id)` returns nil on the first call (spell not loaded yet) and the effect text once
    loaded: 7771 -> "Einen Umhang dauerhaft so verzaubern, dass er die Rüstung um 10 erhöht.".
  * The `spell:<id>` and `enchant:<id>` tooltips (identical) hold only the name, "Werkzeuge: <rod>" and "Reagenzien: ..."
    (with colour codes) before the load; after it the description is their last line. Not usable as an effect source.

## Still unverified

* Whether the scan data survives for professions that were not opened since login (scanner needs the window open once).
* Addon-message delivery between two real characters (needs another online guild member), including the throttle limits.

local addonName, addon = ...

-- ============================================================================================================== --
-- STATIC DATA, NOT READ FROM THE GAME. The game tells an addon a faction's name and a player's standing, but not what a
-- standing unlocks. Those hints are written here by hand from the sources below and can be outdated after a Forever patch.
-- Update them with the project skill `update-faction-hints` (professionshare/.claude/skills/update-faction-hints), which
-- also bumps CHECKED. Only this file holds hint data; nothing here is ever sent to other players.
-- ============================================================================================================== --
-- Sources: warcraft.wiki.gg "Classic reputation rewards" and the pages of each faction.
-- Faction ids: warcraft.wiki.gg "FactionID"; checked in game with /ps rep (unknown ids show "?" there).
--
-- FACTIONS (display order inside a group, groups in GROUP_ORDER):
--   id      faction id (GetFactionInfoByID)
--   name    English name, used only when the viewer's client cannot name the faction
--   group   "raid" | "vendor" | "city" | "cartel" | "pvp"
--   side    "Alliance" | "Horde" for a faction only one side can earn (nil: both); the other side's client reports it as
--           Hated without having met it, so it is not scanned there
--   icon    texture shown in the list
--   hints   per standing (1 Hated .. 8 Exalted): { standing, en = English text, de = German text, items = { itemID, ... } }
--           `items` is optional: the tooltip then also lists those items by the viewer's own client (name, quality).
--           Only add item ids that were checked in game: a wrong id shows a wrong item.

---@class FactionHint
---@field standing integer 1 Hated .. 8 Exalted: from this standing on
---@field en string
---@field de string
---@field items? integer[] item ids, checked in game

---@class FactionDefinition
---@field id integer
---@field name string English fallback name
---@field group string
---@field side? "Alliance"|"Horde"
---@field icon string
---@field hints FactionHint[] ascending by standing

---@class FactionHintsModule
local FactionHints = {}
addon.FactionHints = FactionHints

---@type string date the hints were last compared with the sources (YYYY-MM-DD)
FactionHints.CHECKED = "2026-11-24"
---@type string
FactionHints.SOURCE = "warcraft.wiki.gg (Classic reputation rewards, faction pages)"

---@type string[]
FactionHints.GROUP_ORDER = { "raid", "vendor", "city", "cartel", "pvp" }

local ALLIANCE_ICON, HORDE_ICON = "Interface\\Icons\\INV_BannerPVP_02", "Interface\\Icons\\INV_BannerPVP_01"
local GOBLIN_ICON = "Interface\\Icons\\INV_Misc_Coin_01"

-- the same two hints for every home city
---@return FactionHint[]
local function cityHints()
    return {
        { standing = 6, en = "Vendors of this faction are cheaper.", de = "Händler dieser Fraktion sind günstiger." },
        { standing = 8, en = "Its racial mounts can be bought by characters of every race of your side.",
          de = "Ihre Volksreittiere können von Charakteren jedes Volks deiner Seite gekauft werden." },
    }
end

---@return FactionHint[]
local function cartelHints()
    return {
        { standing = 6, en = "Vendors of this goblin town are cheaper.", de = "Händler dieser Goblinstadt sind günstiger." },
    }
end

---@return FactionHint[]
local function battlegroundHints()
    return {
        { standing = 5, en = "Battleground quartermaster rewards start to unlock; the best ones need Exalted.",
          de = "Belohnungen beim Schlachtfeld-Rüstmeister werden freigeschaltet; die besten brauchen Ehrfürchtig." },
    }
end

---@type FactionDefinition[]
FactionHints.FACTIONS = {
    -- raids and endgame
    { id = 749, name = "Hydraxian Waterlords", group = "raid", icon = "Interface\\Icons\\Spell_Frost_SummonWaterElemental", hints = {
        { standing = 6, en = "Aqual Quintessence: douses the runes in Molten Core so Majordomo Executus appears.",
          de = "Aqual-Quintessenz: löscht die Runen im Geschmolzenen Kern, damit Majordomus Exekutus erscheint." },
        { standing = 7, en = "Eternal Quintessence: a version that is not used up.",
          de = "Ewige Quintessenz: eine Version, die nicht verbraucht wird." },
    } },
    { id = 529, name = "Argent Dawn", group = "raid", icon = "Interface\\Icons\\Spell_Holy_HolyBolt", hints = {
        { standing = 5, en = "Quartermasters in the Plaguelands sell recipes and anti-undead consumables, more with each level.",
          de = "Rüstmeister in den Pestländern verkaufen Rezepte und Verbrauchsgüter gegen Untote, mehr mit jeder Stufe." },
        { standing = 6, en = "Naxxramas attunement can be bought (cheaper at Revered, free at Exalted).",
          de = "Der Naxxramas-Zugang kann gekauft werden (günstiger ab Respektvoll, kostenlos bei Ehrfürchtig)." },
        { standing = 8, en = "Naxxramas shoulder enchants (Might, Power or Fortitude of the Scourge).",
          de = "Schulterverzauberungen aus Naxxramas (Macht, Kraft oder Seelenstärke der Geißel)." },
    } },
    { id = 270, name = "Zandalar Tribe", group = "raid", icon = "Interface\\Icons\\Ability_Mount_JungleTiger", hints = {
        { standing = 5, en = "Zul'Gurub: head and leg enchants and the first class armor turn-ins.",
          de = "Zul'Gurub: Kopf- und Beinverzauberungen und die ersten Klassenrüstungs-Abgaben." },
        { standing = 8, en = "Shoulder enchants: Zandalar Signet of Might, Mojo or Serenity.",
          de = "Schulterverzauberungen: Zandalarianisches Siegel der Macht, des Mojo oder der Gelassenheit." },
    } },
    { id = 609, name = "Cenarion Circle", group = "raid", icon = "Interface\\Icons\\Spell_Nature_Regeneration", hints = {
        { standing = 5, en = "Silithus vendors sell nature resistance and Cenarion recipes, more with each level.",
          de = "Händler in Silithus verkaufen Naturwiderstands- und Zirkel-Rezepte, mehr mit jeder Stufe." },
        { standing = 6, en = "Ruins of Ahn'Qiraj quest rewards (rings, cloaks, weapons) unlock from Honored to Exalted.",
          de = "Questbelohnungen aus den Ruinen von Ahn'Qiraj (Ringe, Umhänge, Waffen) werden von Wohlwollend bis Ehrfürchtig freigeschaltet." },
    } },
    { id = 910, name = "Brood of Nozdormu", group = "raid", icon = "Interface\\Icons\\INV_Misc_Head_Dragon_Bronze", hints = {
        { standing = 4, en = "Temple of Ahn'Qiraj: the bronze dragonflight ring, upgraded at every level.",
          de = "Tempel von Ahn'Qiraj: der Ring des bronzenen Drachenschwarms, mit jeder Stufe verbessert." },
        { standing = 8, en = "The last upgrade of the ring.", de = "Die letzte Verbesserung des Rings." },
    } },
    -- vendors: recipes, mounts
    { id = 59, name = "Thorium Brotherhood", group = "vendor", icon = "Interface\\Icons\\INV_Ingot_Thorium", hints = {
        { standing = 5, en = "Lokhtos Darkbargainer (Blackrock Depths) sells his first plans, patterns and formulas.",
          de = "Lokhtos Düsterfeilsch (Schwarzfelstiefen) verkauft seine ersten Pläne, Muster und Formeln." },
        { standing = 6, en = "More Dark Iron and fire resistance recipes.",
          de = "Weitere Dunkeleisen- und Feuerwiderstands-Rezepte." },
        { standing = 7, en = "Further plans, patterns and formulas.", de = "Weitere Pläne, Muster und Formeln." },
        { standing = 8, en = "The best blacksmithing plans, e.g. Sulfuron Hammer.",
          de = "Die besten Schmiedepläne, z. B. Sulfuronhammer." },
    } },
    { id = 576, name = "Timbermaw Hold", group = "vendor", icon = "Interface\\Icons\\Ability_Hunter_Pet_Bear", hints = {
        { standing = 4, en = "Timbermaw furbolgs stop attacking: safe way through the Timbermaw Hold tunnel.",
          de = "Die Holzschlundfurbolgs greifen nicht mehr an: sicherer Weg durch den Tunnel der Holzschlundfeste." },
        { standing = 6, en = "Leatherworking pattern: Might of the Timbermaw.", de = "Lederverarbeitungsmuster: Macht der Holzschlund." },
        { standing = 7, en = "Leatherworking pattern: Mantle of the Timbermaw.", de = "Lederverarbeitungsmuster: Mantel der Holzschlund." },
        { standing = 8, en = "Quest for the trinket Defender of the Timbermaw.", de = "Quest für das Schmuckstück Verteidiger der Holzschlund." },
    } },
    { id = 589, side = "Alliance", name = "Wintersaber Trainers", group = "vendor", icon = "Interface\\Icons\\Ability_Mount_WhiteTiger", hints = {
        { standing = 8, en = "Reins of the Winterspring Frostsaber (epic mount, Alliance).",
          de = "Zügel des Winterquellfrostsäblers (episches Reittier, Allianz)." },
    } },
    -- home cities
    { id = 72, side = "Alliance", name = "Stormwind", group = "city", icon = ALLIANCE_ICON, hints = cityHints() },
    { id = 47, side = "Alliance", name = "Ironforge", group = "city", icon = ALLIANCE_ICON, hints = cityHints() },
    { id = 69, side = "Alliance", name = "Darnassus", group = "city", icon = ALLIANCE_ICON, hints = cityHints() },
    { id = 54, side = "Alliance", name = "Gnomeregan Exiles", group = "city", icon = ALLIANCE_ICON, hints = cityHints() },
    { id = 76, side = "Horde", name = "Orgrimmar", group = "city", icon = HORDE_ICON, hints = cityHints() },
    { id = 81, side = "Horde", name = "Thunder Bluff", group = "city", icon = HORDE_ICON, hints = cityHints() },
    { id = 68, side = "Horde", name = "Undercity", group = "city", icon = HORDE_ICON, hints = cityHints() },
    { id = 530, side = "Horde", name = "Darkspear Trolls", group = "city", icon = HORDE_ICON, hints = cityHints() },
    -- goblin towns
    { id = 369, name = "Gadgetzan", group = "cartel", icon = GOBLIN_ICON, hints = cartelHints() },
    { id = 21, name = "Booty Bay", group = "cartel", icon = GOBLIN_ICON, hints = cartelHints() },
    { id = 470, name = "Ratchet", group = "cartel", icon = GOBLIN_ICON, hints = cartelHints() },
    { id = 577, name = "Everlook", group = "cartel", icon = GOBLIN_ICON, hints = cartelHints() },
    -- battlegrounds
    { id = 730, side = "Alliance", name = "Stormpike Guard", group = "pvp", icon = ALLIANCE_ICON, hints = battlegroundHints() },
    { id = 890, side = "Alliance", name = "Silverwing Sentinels", group = "pvp", icon = ALLIANCE_ICON, hints = battlegroundHints() },
    { id = 509, side = "Alliance", name = "League of Arathor", group = "pvp", icon = ALLIANCE_ICON, hints = battlegroundHints() },
    { id = 729, side = "Horde", name = "Frostwolf Clan", group = "pvp", icon = HORDE_ICON, hints = battlegroundHints() },
    { id = 889, side = "Horde", name = "Warsong Outriders", group = "pvp", icon = HORDE_ICON, hints = battlegroundHints() },
    { id = 510, side = "Horde", name = "The Defilers", group = "pvp", icon = HORDE_ICON, hints = battlegroundHints() },
}

---@type table<integer, FactionDefinition>
local factionByID = {}
for _, faction in ipairs(FactionHints.FACTIONS) do factionByID[faction.id] = faction end

---@param factionID any
---@return FactionDefinition|nil
function FactionHints.Faction(factionID) return factionByID[factionID] end

-- The hint text for the viewer's UI language: German for "deDE", English otherwise.
---@param hint FactionHint
---@param languageCode string|nil
---@return string
function FactionHints.HintText(hint, languageCode)
    if languageCode == "deDE" and type(hint.de) == "string" and hint.de ~= "" then return hint.de end
    return hint.en
end

-- The next hint above a standing (what the player gets at the next level that unlocks something), or nil.
---@param factionID integer
---@param standing integer|nil
---@return FactionHint|nil
function FactionHints.NextHint(factionID, standing)
    local faction = factionByID[factionID]
    for _, hint in ipairs(faction and faction.hints or {}) do
        if hint.standing > (standing or 0) then return hint end
    end
    return nil
end

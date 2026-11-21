local addonName, addon = ...

-- The ONLY file of this addon that calls WoW client functions for game logic: random numbers, sounds, and (through
-- LibGuildSync's Guild) my identity and the guild roster. Every call is guarded: a missing API never breaks a play.
---@class ApiModule
local Api = {}
addon.Api = Api

local Guild = LibStub("LibGuildSync-1.0").Guild

---@return boolean
function Api.IsGuilded() return Guild.IsGuilded() end
---@return PlayerInformation
function Api.GetPlayerInformation() return Guild.GetPlayerInformation() end
function Api.RequestRoster() return Guild.RequestRoster() end
---@return table<string, boolean>
function Api.GetGuildRoster() return Guild.GetGuildRoster() end

-- A number in [0, 1) for game outcomes (Games.Flip and Slots.Spin take it as their random function; tests inject their own).
---@return number
function Api.Random() return math.random() end

-- The coin sound played on a won flip, or nil when this client has no such sound kit.
---@return integer|nil
function Api.CoinSoundKit()
    return SOUNDKIT and (SOUNDKIT.LOOT_WINDOW_COIN_SOUND or SOUNDKIT.IG_BACKPACK_COIN_SELECT) or nil
end

-- The first of `soundNames` this client's SOUNDKIT table has, or nil.
---@param soundNames string[]
---@return integer|nil
function Api.SoundKitFor(soundNames)
    if not SOUNDKIT then return nil end
    for _, soundName in ipairs(soundNames) do
        if SOUNDKIT[soundName] then return SOUNDKIT[soundName] end
    end
    return nil
end

-- Plays a sound kit; never raises (a missing sound must not break a play).
---@param soundKitID integer|nil
function Api.PlaySound(soundKitID)
    if soundKitID and PlaySound then
        local ok, errorMessage = pcall(PlaySound, soundKitID)
        if not ok then addon.Log.Debug("api.call", "a client function raised an error", { call = "PlaySound", error = tostring(errorMessage) }) end
    end
end

-- Plays the first of `soundNames` this client knows; nothing when it knows none.
---@param soundNames string[]
function Api.PlaySoundNamed(soundNames) Api.PlaySound(Api.SoundKitFor(soundNames)) end

------------------------------------------------------------------ AZEcaught (feature 018): units
-- This client (Retail-based Forever, build 70959) FORBIDS addons the combat log (registering it shows the "reserved for
-- the Blizzard UI" dialog) and hands out SECRET values in combat and instances (health, name, GUID, ...): comparing,
-- indexing or doing arithmetic on one raises an error. So AZEcaught only reads units, and every value read goes through
-- Api.NotSecret: a secret reads as nil (unknown). Same rule as the Spoken addons on this client.

-- `value`, or nil when the client hides it (a secret). Clients without secrets have no issecretvalue.
---@param value any
---@return any
function Api.NotSecret(value)
    local isSecret = rawget(_G, "issecretvalue")
    if isSecret and isSecret(value) then return nil end
    return value
end
local NotSecret = Api.NotSecret

-- GetTime(): seconds with fractions, for throw windows and the active-time ticker.
---@return number
function Api.Clock() return GetTime and GetTime() or 0 end

---@return integer
function Api.PlayerLevel()
    local ok, level = pcall(UnitLevel, "player")
    level = ok and NotSecret(level) or nil
    return type(level) == "number" and level > 0 and level or 1
end

---@param unit string
---@return string|nil
function Api.UnitGuid(unit)
    if not UnitGUID then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    guid = ok and NotSecret(guid) or nil
    return type(guid) == "string" and guid or nil
end

-- The unit token that currently shows `guid` (nameplate, target, ...), or nil.
---@param guid string
---@return string|nil
function Api.UnitTokenFromGuid(guid)
    if not UnitTokenFromGUID or type(guid) ~= "string" then return nil end
    local ok, unit = pcall(UnitTokenFromGUID, guid)
    unit = ok and NotSecret(unit) or nil
    return type(unit) == "string" and unit or nil
end

-- true / false, or nil when the client hides it.
---@param unit string
---@return boolean|nil
function Api.IsDead(unit)
    if not UnitIsDead then return nil end
    local ok, dead = pcall(UnitIsDead, unit)
    if not ok then return nil end
    dead = NotSecret(dead)
    if dead == nil then return nil end
    return dead and true or false
end

-- true when `unit` has the player on its threat list (it is fighting the player), nil when unknown.
---@param unit string
---@return boolean|nil
function Api.IsFightingMe(unit)
    if not UnitThreatSituation then return nil end
    local ok, situation = pcall(UnitThreatSituation, "player", unit)
    if not ok then return nil end
    situation = NotSecret(situation)
    return situation ~= nil and true or false
end

---@class UnitSnapshot
---@field guid string
---@field npc integer|nil
---@field name string|nil nil when hidden
---@field level integer|nil nil when hidden (a skull level is reported as player level + 10)
---@field classification string "normal" when hidden
---@field health number|nil fraction 0..1, nil when hidden
---@field hostile boolean|nil nil when hidden
---@field dead boolean|nil nil when hidden

---@param func function|nil
---@param ... any
---@return any value (nil when the function is missing, raised, or the value is a secret)
local function read(func, ...)
    if not func then return nil end
    local ok, value = pcall(func, ...)
    if not ok then return nil end
    return NotSecret(value)
end

-- What AZEcaught can know about a unit, or nil when there is no unit (or its GUID is hidden). Never raises.
---@param unit string
---@return UnitSnapshot|nil
function Api.UnitSnapshot(unit)
    local ok, snapshot = pcall(function()
        if read(UnitExists, unit) == false then return nil end
        local guid = Api.UnitGuid(unit)
        if not guid then return nil end
        local health, healthMaximum = read(UnitHealth, unit), read(UnitHealthMax, unit)
        local level = read(UnitLevel, unit)
        if type(level) == "number" and level < 0 then level = Api.PlayerLevel() + 10 end
        local canAttack = read(UnitCanAttack, "player", unit)
        local name = read(UnitName, unit)
        local classification = read(UnitClassification, unit)
        return { guid = guid, npc = addon.AzeCaught.NpcIDFromGuid(guid), name = type(name) == "string" and name or nil,
            level = type(level) == "number" and level or nil,
            classification = type(classification) == "string" and classification or "normal",
            health = (type(health) == "number" and type(healthMaximum) == "number" and healthMaximum > 0) and health / healthMaximum or nil,
            hostile = canAttack ~= nil and (canAttack and true or false) or nil, dead = Api.IsDead(unit) }
    end)
    if not ok then
        addon.AzeCaught.Journal("WARNING", "api.unit", "reading a unit failed", { unit = unit, error = tostring(snapshot) })
        return nil
    end
    return snapshot
end

-- The instance type ("party", "raid", "none", ...) for the journal, or nil when the client does not say.
---@return string|nil
function Api.InInstance()
    if not IsInInstance then return nil end
    local ok, inside, kind = pcall(IsInInstance)
    if not ok then return nil end
    return NotSecret(kind) or (NotSecret(inside) and "yes") or nil
end

-- The nameplate frame of a unit token, or nil.
---@param unit string
---@return table|nil
function Api.NamePlateFor(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    return ok and NotSecret(plate) or nil
end

------------------------------------------------------------------ the catch dump (feature 018, debugging)

-- One value for the dump: the value as text, "secret" (hidden by the client), "missing" (no such function on this
-- client), "error" (it raised), "nil". Several return values are joined with "/".
---@param func function|nil
---@param ... any
---@return string
local function dumpValue(func, ...)
    if type(func) ~= "function" then return "missing" end
    local results = { pcall(func, ...) }
    if not results[1] then return "error" end
    local isSecret = rawget(_G, "issecretvalue")
    local parts = {}
    for index = 2, math.max(2, table.maxn(results)) do
        local value = results[index]
        if isSecret and isSecret(value) then parts[#parts + 1] = "secret"
        else parts[#parts + 1] = value == nil and "nil" or tostring(value) end
    end
    while #parts > 1 and parts[#parts] == "nil" do parts[#parts] = nil end
    return table.concat(parts, "/")
end

local STAT_NAMES = { "strength", "agility", "stamina", "intellect", "spirit" }

-- Everything an addon can read about `unit`, as text, for the journal (`/gg caught dump`, and logged on every catch).
-- Player-only functions (UnitStat, UnitArmor) are tried too, so the log shows what this client gives for an NPC.
---@param unit string
---@return table<string, string>
-- Every other way this client might tell WHO a unit is (user 2026-11-20: dungeons hide UnitGUID, UnitName and the
-- health, "are there maybe other functions that could expose that information"). Each value as dumpValue text
-- ("secret", "missing", "error", "nil" or the value). Read-only; nothing here is stored.
---@param unit string
---@return table<string, string>
function Api.IdentityProbe(unit)
    local G = _G
    local probe = { unit = unit }
    local function try(key, func, ...) probe[key] = dumpValue(func, ...) end
    try("UnitGUID", G.UnitGUID, unit)
    try("UnitName", G.UnitName, unit)
    try("UnitNameUnmodified", G.UnitNameUnmodified, unit)
    try("GetUnitName", G.GetUnitName, unit, false)
    try("UnitFullName", G.UnitFullName, unit)
    try("UnitCreatureType", G.UnitCreatureType, unit)
    try("UnitCreatureFamily", G.UnitCreatureFamily, unit)
    try("UnitHealthPercent", G.UnitHealthPercent, unit)
    try("UnitIsUnit target", G.UnitIsUnit, unit, "target")
    try("UnitSelectionType", G.UnitSelectionType, unit)
    try("UnitIsQuestBoss", G.UnitIsQuestBoss, unit)
    try("UnitClassBase", G.UnitClassBase, unit)
    local secrets = rawget(G, "C_Secrets")
    try("C_Secrets.ShouldUnitIdentityBeSecret", secrets and secrets.ShouldUnitIdentityBeSecret, unit)
    try("C_Secrets.ShouldUnitHealthMaxBeSecret", secrets and secrets.ShouldUnitHealthMaxBeSecret, unit)
    -- the tooltip data the client builds for the unit
    local tooltipInfo = rawget(G, "C_TooltipInfo")
    local okTooltip, data = pcall(function() return tooltipInfo and tooltipInfo.GetUnit and tooltipInfo.GetUnit(unit) end)
    if not okTooltip then probe["tooltip"] = "error"
    elseif type(data) ~= "table" then probe["tooltip"] = tooltipInfo and "nil" or "missing"
    else
        probe["tooltip.guid"] = dumpValue(function() return data.guid end)
        for index = 1, 4 do
            local line = type(data.lines) == "table" and data.lines[index]
            if line then probe["tooltip.line" .. index] = dumpValue(function() return line.leftText end) end
        end
    end
    -- the model the client renders for the unit
    local okModel, model = pcall(G.CreateFrame, "PlayerModel", nil, G.UIParent)
    if okModel and model then
        pcall(model.SetSize, model, 1, 1)
        pcall(model.SetUnit, model, unit)
        try("model.GetModelFileID", model.GetModelFileID, model)
        try("model.GetDisplayInfo", model.GetDisplayInfo, model)
        try("model.GetCreatureDisplayID", model.GetCreatureDisplayID, model)
        pcall(model.ClearModel, model); pcall(model.Hide, model)
    else
        probe["model"] = "error"
    end
    -- the client's own nameplate text
    local plate = Api.NamePlateFor(unit)
    local okFrame, unitFrame = pcall(function() return plate and plate.UnitFrame end)
    if not okFrame then unitFrame = nil; probe["nameplate.UnitFrame"] = "error" end
    probe["nameplate"] = plate and "yes" or "nil"
    if unitFrame then
        try("nameplate.name", unitFrame.name and unitFrame.name.GetText, unitFrame.name)
        probe["nameplate.unitField"] = dumpValue(function() return unitFrame.unit end)
    end
    return probe
end

function Api.UnitDump(unit)
    local G = _G
    local dump = { unit = unit }
    local guid = Api.UnitGuid(unit)
    dump.guid = guid or dumpValue(G.UnitGUID, unit)
    dump.npc = tostring(guid and addon.AzeCaught.NpcIDFromGuid(guid) or "nil")
    local reads = {
        exists = { G.UnitExists, unit }, name = { G.UnitName, unit }, level = { G.UnitLevel, unit },
        effectiveLevel = { G.UnitEffectiveLevel, unit }, classification = { G.UnitClassification, unit },
        creatureType = { G.UnitCreatureType, unit }, family = { G.UnitCreatureFamily, unit }, race = { G.UnitRace, unit },
        sex = { G.UnitSex, unit }, faction = { G.UnitFactionGroup, unit }, reaction = { G.UnitReaction, "player", unit },
        class = { G.UnitClass, unit }, health = { G.UnitHealth, unit }, healthMax = { G.UnitHealthMax, unit },
        powerType = { G.UnitPowerType, unit }, power = { G.UnitPower, unit }, powerMax = { G.UnitPowerMax, unit },
        canAttack = { G.UnitCanAttack, "player", unit }, isEnemy = { G.UnitIsEnemy, "player", unit },
        isDead = { G.UnitIsDead, unit }, inCombat = { G.UnitAffectingCombat, unit },
        threat = { G.UnitThreatSituation, "player", unit }, tapDenied = { G.UnitIsTapDenied, unit },
        isPlayer = { G.UnitIsPlayer, unit }, isBoss = { G.UnitIsBossMob, unit }, questBoss = { G.UnitIsQuestBoss, unit },
        armor = { G.UnitArmor, unit }, attackPower = { G.UnitAttackPower, unit }, damage = { G.UnitDamage, unit },
        attackSpeed = { G.UnitAttackSpeed, unit }, resistance = { G.UnitResistance, unit, 1 },
        zone = { G.GetRealZoneText }, subZone = { G.GetSubZoneText }, playerLevel = { G.UnitLevel, "player" },
    }
    for key, call in pairs(reads) do dump[key] = dumpValue(call[1], unpack(call, 2)) end
    for index, statName in ipairs(STAT_NAMES) do dump[statName] = dumpValue(G.UnitStat, unit, index) end
    local mapApi = G.C_Map
    dump.mapID = dumpValue(mapApi and mapApi.GetBestMapForUnit, "player")
    return dump
end

-- The stats AZEcaught keeps for an NPC (user 2026-11-20): creature type (id or localized name), beast family, maximum
-- health, power type and maximum, gender. Hidden (secret) or missing values are left out; never raises.
---@param unit string
---@return NpcStats
function Api.UnitStats(unit)
    local G = _G
    local function first(func, ...)
        if type(func) ~= "function" then return nil end
        local results = { pcall(func, ...) }
        if not results[1] then return nil end
        return NotSecret(results[2]), NotSecret(results[3])
    end
    local typeName, typeID = first(G.UnitCreatureType, unit)
    local powerType = first(G.UnitPowerType, unit)
    local stats = {
        typeName = type(typeName) == "string" and typeName or nil,
        type = addon.AzeCaught.CreatureTypeID(typeID, typeName),
        family = (function() local family = first(G.UnitCreatureFamily, unit) return type(family) == "string" and family or nil end)(),
        hp = (function() local value = first(G.UnitHealthMax, unit) return type(value) == "number" and value or nil end)(),
        power = type(powerType) == "number" and powerType or nil,
        powerMax = (function() local value = first(G.UnitPowerMax, unit) return type(value) == "number" and value or nil end)(),
        sex = (function() local value = first(G.UnitSex, unit) return type(value) == "number" and value or nil end)(),
    }
    return stats
end

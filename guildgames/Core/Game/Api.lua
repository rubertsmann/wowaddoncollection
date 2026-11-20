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

-- The nameplate frame of a unit token, or nil.
---@param unit string
---@return table|nil
function Api.NamePlateFor(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    return ok and NotSecret(plate) or nil
end

------------------------------------------------------------------ throw geometry (feature 018, rope effect)

local MELEE_GUESS = 6          -- yards: a throw in combat without any distance source (most kills are close)
local INTERACT_GUESS = { [3] = 7, [4] = 18 }   -- CheckInteractDistance index -> typical yards inside it (3 ~10 yd, 4 ~28 yd)
local BEYOND_GUESS = 35

-- Where `unit` is, relative to the player, for the rope effect: never a nameplate (restricted regions: measuring one
-- taints the addon). Tries, in order: world positions (UnitPosition of both + GetPlayerFacing -> distance and bearing),
-- CheckInteractDistance (OUT of combat only: it is restricted against enemies in combat), else a melee guess.
-- Every value is checked for secrets; `why` says what was not usable, for the journal.
---@param unit string
---@return { distance: number, bearing: number, zoom: number|nil, source: string, why: string }
function Api.ThrowGeometry(unit)
    local reasons = {}
    local okZoom, zoom = pcall(function() return GetCameraZoom and GetCameraZoom() end)
    zoom = okZoom and NotSecret(zoom) or nil
    if type(zoom) ~= "number" then reasons[#reasons + 1] = "zoom " .. (okZoom and "unknown" or "error"); zoom = nil end
    local function result(distance, bearing, source)
        return { distance = distance, bearing = bearing, zoom = zoom, source = source, why = table.concat(reasons, "; ") }
    end
    -- 1. world positions: first value is the west axis, second the north axis; facing 0 = north, counter-clockwise
    local positioned, west, north, westTarget, northTarget, facing = pcall(function()
        if not (UnitPosition and GetPlayerFacing) then return nil end
        local playerWest, playerNorth, _, playerInstance = UnitPosition("player")
        local targetWest, targetNorth, _, targetInstance = UnitPosition(unit)
        if NotSecret(playerInstance) ~= NotSecret(targetInstance) then return nil end
        return NotSecret(playerWest), NotSecret(playerNorth), NotSecret(targetWest), NotSecret(targetNorth), NotSecret(GetPlayerFacing())
    end)
    if positioned and type(west) == "number" and type(north) == "number" and type(westTarget) == "number"
        and type(northTarget) == "number" and type(facing) == "number" then
        local toWest, toNorth = westTarget - west, northTarget - north
        local relative = math.atan2(toWest, toNorth) - facing             -- counter-clockwise = to the left
        relative = (relative + math.pi) % (2 * math.pi) - math.pi
        return result(math.sqrt(toWest * toWest + toNorth * toNorth), -relative, "position")
    end
    reasons[#reasons + 1] = "position " .. (positioned and "hidden" or "error")
    -- 2. interaction ranges, out of combat only
    local inCombat = InCombatLockdown and InCombatLockdown()
    if not inCombat and CheckInteractDistance then
        for _, index in ipairs({ 3, 4 }) do
            local ok, inside = pcall(CheckInteractDistance, unit, index)
            inside = ok and NotSecret(inside)
            if inside then return result(INTERACT_GUESS[index], 0, "interact" .. index) end
        end
        return result(BEYOND_GUESS, 0, "interact beyond")
    end
    reasons[#reasons + 1] = inCombat and "interact skipped in combat" or "interact missing"
    return result(MELEE_GUESS, 0, "melee guess")
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

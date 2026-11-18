-- LibGuildSync: the guild and identity client calls every sync addon needs (roster, my name). Calls that fail on this
-- client (missing or changed API) return nil instead of breaking the caller.
local lib = LibStub("LibGuildSync-1.0")
local Guild = lib:Module("Guild", 1)
if not Guild then return end

-- pcall(func, ...) returning func's results, or nil when it is missing or raised an error.
---@param func function|nil
---@param ... any
---@return any ...
local function tryCall(func, ...)
    if type(func) ~= "function" then return nil end
    local results = { pcall(func, ...) }
    if results[1] then return unpack(results, 2, table.maxn(results)) end
    return nil
end

---@return boolean
function Guild.IsGuilded()
    return (IsInGuild and IsInGuild()) and true or false
end

-- My base name as the server uses it: "First" on normal clients, "First Surname" on Forever, where UnitName("player")
-- returns the surname as its second value (retail returns nil there for the player).
---@return string|nil
function Guild.MyBaseName()
    if not UnitName then return nil end
    local firstName, secondValue = UnitName("player")
    if type(secondValue) == "string" and secondValue ~= "" and not lib.Utility.IsRealmSpelling(secondValue) then
        local fullCharacterName = firstName .. " " .. secondValue
        lib.Utility.NoteMyFullName(fullCharacterName)
        return fullCharacterName
    end
    return firstName
end

---@class PlayerInformation
---@field name string|nil canonical "Name-Realm"
---@field class string|nil class file name
---@field level integer|nil

---@return PlayerInformation
function Guild.GetPlayerInformation()
    local className
    if UnitClass then className = select(2, UnitClass("player")) end
    return { name = lib.Utility.CanonicalName(Guild.MyBaseName()), class = className, level = UnitLevel and UnitLevel("player") or nil }
end

function Guild.RequestRoster()
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster()
    elseif GuildRoster then GuildRoster() end
end

-- Set of canonical "Name-Realm" for everyone in the guild (empty if the roster is not loaded yet). The roster's spelling
-- of MY character teaches Utility which realm string the server uses for my realm, before any name is canonicalized.
---@return table<string, boolean>
function Guild.GetGuildRoster()
    local Utility = lib.Utility
    local rosterSet, rosterNames = {}, {}
    if not Guild.IsGuilded() or not GetNumGuildMembers then return rosterSet end
    for memberIndex = 1, (GetNumGuildMembers()) do
        local rosterName = GetGuildRosterInfo(memberIndex)
        if type(rosterName) == "string" and rosterName ~= "" then rosterNames[#rosterNames + 1] = rosterName end
    end
    Utility.LearnFromRoster(rosterNames, Guild.MyBaseName())
    Utility.SetRosterNames(rosterNames)
    for _, rosterName in ipairs(rosterNames) do
        local canonicalName = Utility.CanonicalName(rosterName)
        if canonicalName then rosterSet[canonicalName] = true end
    end
    return rosterSet
end

-- Raw identity facts for a diagnostic report: every source of "my name" and of the roster's names, so a mismatch between
-- them (realm suffix form) can be seen without guessing. Values are what the client returned, untouched.
---@return table identity fields: unitName, unitRealm, unitFullName, realmName, normalizedRealm, guild, base, built, ambiguated, rosterCount, rosterSample, rosterMe, build
function Guild.IdentityInformation()
    local identity = {}
    identity.unitName, identity.unitRealm = tryCall(UnitName, "player")
    if UnitFullName then
        local fullName, fullRealm = tryCall(UnitFullName, "player")
        identity.unitFullName = tostring(fullName) .. " / " .. tostring(fullRealm)
    end
    identity.realmName = GetRealmName and tryCall(GetRealmName)
    identity.normalizedRealm = GetNormalizedRealmName and tryCall(GetNormalizedRealmName)
    identity.guild = GetGuildInfo and tryCall(GetGuildInfo, "player")
    local builtName = lib.Utility.CanonicalName(Guild.MyBaseName())
    identity.base = Guild.MyBaseName()
    identity.built = builtName
    identity.ambiguated = Ambiguate and builtName and tryCall(Ambiguate, builtName, "none")
    local rosterSample, myRosterName = {}, nil
    if Guild.IsGuilded() and GetNumGuildMembers then
        local memberCount = tryCall(GetNumGuildMembers) or 0
        identity.rosterCount = memberCount
        for memberIndex = 1, memberCount do
            local rosterName = tryCall(GetGuildRosterInfo, memberIndex)
            if rosterName then
                if #rosterSample < 8 then rosterSample[#rosterSample + 1] = rosterName end   -- the raw form the client reports
                local characterName = rosterName:match("^([^-]+)") or rosterName
                if identity.base and (characterName == identity.base or characterName == identity.unitName) then myRosterName = rosterName end
            end
        end
    end
    identity.rosterSample = rosterSample
    identity.rosterMe = myRosterName   -- how the roster spells MY name
    if GetBuildInfo then
        local versionText, buildNumber, _, interfaceVersion = tryCall(GetBuildInfo)
        identity.build = ("%s (%s) interface %s"):format(tostring(versionText), tostring(buildNumber), tostring(interfaceVersion))
    end
    return identity
end

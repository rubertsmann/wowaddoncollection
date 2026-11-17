local addonName, addon = ...

-- Debug log. Every entry goes into FpvCigaretteDB.log (a ring buffer, written to
-- WTF\Account\<account>\SavedVariables\FpvCigarette.lua on /reload or logout); with /cig debug on it is also printed
-- to chat. Important events are always logged; high-frequency ones (zoom calls, camera samples) only in debug mode.
local Log = {}
addon.Log = Log

local MAX_ENTRIES = 400
local onceKeys = {}

local function serialize(fields)
    if not fields then return "" end
    local keys = {}
    for key in pairs(fields) do keys[#keys + 1] = key end
    table.sort(keys)
    local parts = {}
    for _, key in ipairs(keys) do
        local value = fields[key]
        if type(value) == "number" and value ~= math.floor(value) then value = string.format("%.3f", value) end
        parts[#parts + 1] = key .. "=" .. tostring(value)
    end
    return " " .. table.concat(parts, " ")
end

function Log.Enabled() return FpvCigaretteDB and FpvCigaretteDB.debug or false end

---@param category string
---@param message string
---@param fields? table
function Log.Write(category, message, fields)
    if not FpvCigaretteDB then return end
    local line = string.format("%s %.2f [%s] %s%s", date("%H:%M:%S"), GetTime(), category, message, serialize(fields))
    local log = FpvCigaretteDB.log or {}
    FpvCigaretteDB.log = log
    log[#log + 1] = line
    while #log > MAX_ENTRIES do table.remove(log, 1) end
    if Log.Enabled() then DEFAULT_CHAT_FRAME:AddMessage("|cff888888[cig " .. category .. "]|r " .. message .. serialize(fields)) end
end

-- Only in debug mode (frequent things).
function Log.Debug(category, message, fields)
    if Log.Enabled() then Log.Write(category, message, fields) end
end

-- Once per session per key (warnings that would otherwise repeat every frame).
function Log.Once(key, category, message, fields)
    if onceKeys[key] then return end
    onceKeys[key] = true
    Log.Write(category, message, fields)
end

function Log.Clear() if FpvCigaretteDB then FpvCigaretteDB.log = {} end end

function Log.Tail(count)
    local log = FpvCigaretteDB and FpvCigaretteDB.log or {}
    local first = math.max(1, #log - count + 1)
    local lines = {}
    for index = first, #log do lines[#lines + 1] = log[index] end
    return lines
end

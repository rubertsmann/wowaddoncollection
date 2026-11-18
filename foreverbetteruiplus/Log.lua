local addonName, addon = ...

-- Debug log. Every entry goes into ForeverBetterUIPlusDB.log (a ring buffer, written to
-- WTF\Account\<account>\SavedVariables\ForeverBetterUIPlus.lua on /reload or logout); with /fbui debug on it is also
-- printed to chat.
local Log = {}
addon.Log = Log

local MAX_ENTRIES = 600

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

function Log.Enabled() return ForeverBetterUIPlusDB and ForeverBetterUIPlusDB.debug or false end

---@param category string
---@param message string
---@param fields? table
function Log.Write(category, message, fields)
    if not ForeverBetterUIPlusDB then return end
    local line = string.format("%s %.2f [%s] %s%s", date("%H:%M:%S"), GetTime(), category, message, serialize(fields))
    local log = ForeverBetterUIPlusDB.log or {}
    ForeverBetterUIPlusDB.log = log
    log[#log + 1] = line
    while #log > MAX_ENTRIES do table.remove(log, 1) end
    if Log.Enabled() then DEFAULT_CHAT_FRAME:AddMessage("|cff888888[fbui " .. category .. "]|r " .. message .. serialize(fields)) end
end

-- Only in debug mode (frequent things).
function Log.Debug(category, message, fields)
    if Log.Enabled() then Log.Write(category, message, fields) end
end

function Log.Clear() if ForeverBetterUIPlusDB then ForeverBetterUIPlusDB.log = {} end end

function Log.Tail(count)
    local log = ForeverBetterUIPlusDB and ForeverBetterUIPlusDB.log or {}
    local first = math.max(1, #log - count + 1)
    local lines = {}
    for index = first, #log do lines[#lines + 1] = log[index] end
    return lines
end

local _, addon = ...

-- Pure rules (no WoW API): settings defaults, which alpha an element should have, and the fade step.
-- Tested offline by tests/run.lua.
local Logic = {}
addon.Logic = Logic

Logic.DEFAULT_GLOBAL = 0.6        -- opacity for every element set to "global"
Logic.DEFAULT_FADE_SECONDS = 0.2  -- time for a full 0 -> 1 fade
Logic.HOVER_ALPHA = 1

-- An element's mode is stored in db.elements[key]:
--   nil / "global"  -> uses db.global
--   number 0..1     -> its own opacity
--   "off"           -> not touched by the addon (stays at full opacity)
Logic.MODE_GLOBAL, Logic.MODE_OFF = "global", "off"

---@param value any
---@return number|nil
function Logic.Clamp01(value)
    value = tonumber(value)
    if not value or value ~= value then return nil end
    return math.max(0, math.min(1, value))
end

-- Fills missing fields of the saved table (keeps everything that is already there).
---@param db? table
---@return table
function Logic.NewSettings(db)
    db = type(db) == "table" and db or {}
    db.global = Logic.Clamp01(db.global) or Logic.DEFAULT_GLOBAL
    db.fadeSeconds = tonumber(db.fadeSeconds) or Logic.DEFAULT_FADE_SECONDS
    if type(db.elements) ~= "table" then db.elements = {} end
    if db.combatFull == nil then db.combatFull = false end
    if type(db.combat) ~= "table" then db.combat = {} end
    return db
end

-- Per element "full opacity in combat": db.combat[key] = true (full) / false (stays faded) / nil (uses db.combatFull).
---@param db table
---@param key string
---@return boolean
function Logic.CombatFull(db, key)
    local value = db.combat[key]
    if value == nil then return db.combatFull and true or false end
    return value
end

---@param db table
---@param key string
---@return string  "global" | "full" | "faded"
function Logic.CombatModeName(db, key)
    local value = db.combat[key]
    if value == nil then return "global" end
    return value and "full" or "faded"
end

-- "full" / "faded" / "global" -> true / false / nil; the second value says whether the text was valid.
---@param text string|nil
---@return boolean|nil value, boolean valid
function Logic.ParseCombatMode(text)
    text = (text or ""):lower()
    if text == "full" or text == "show" or text == "on" then return true, true end
    if text == "faded" or text == "fade" or text == "off" then return false, true end
    if text == "global" then return nil, true end
    return nil, false
end

-- The opacity an element has while the mouse is not over it, or nil when the addon leaves it alone.
---@param db table
---@param key string
---@return number|nil
function Logic.BaseAlpha(db, key)
    local mode = db.elements[key]
    if mode == Logic.MODE_OFF then return nil end
    if type(mode) == "number" then return Logic.Clamp01(mode) end
    return db.global
end

---@param db table
---@param key string
---@return string  "global" | "custom" | "off"
function Logic.ModeName(db, key)
    local mode = db.elements[key]
    if mode == Logic.MODE_OFF then return "off" end
    if type(mode) == "number" then return "custom" end
    return "global"
end

-- What the element should fade towards right now.
---@param base number   from BaseAlpha
---@param context table { hovered, inCombat, combatFull, editMode }
---@return number
function Logic.TargetAlpha(base, context)
    if context.editMode or context.hovered then return Logic.HOVER_ALPHA end
    if context.inCombat and context.combatFull then return Logic.HOVER_ALPHA end
    return base
end

-- Moves current towards target at a speed of one full fade per fadeSeconds.
---@return number
function Logic.Step(current, target, elapsed, fadeSeconds)
    if not fadeSeconds or fadeSeconds <= 0 then return target end
    local delta = elapsed / fadeSeconds
    if current < target then return math.min(target, current + delta) end
    return math.max(target, current - delta)
end

-- "40" / "40%" / "0.4" -> 0.4; "global" / "off" pass through; anything else -> nil.
---@param text string|nil
---@return number|string|nil
function Logic.ParseOpacity(text)
    text = (text or ""):lower():gsub("%%", "")
    if text == Logic.MODE_GLOBAL or text == Logic.MODE_OFF then return text end
    local number = tonumber(text)
    if not number then return nil end
    if number > 1 then number = number / 100 end
    return Logic.Clamp01(number)
end

---@param alpha number
---@return string
function Logic.Percent(alpha) return string.format("%d%%", math.floor(alpha * 100 + 0.5)) end

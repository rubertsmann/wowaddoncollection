local addonName, addon = ...

-- Recipe drop alerts (pure): the settings, the recipes that dropped for me and who answered, the drops other members
-- told me about, and the checks of the two messages:
--   DROP  {item}            on GUILD from the looter: "this recipe item just dropped into my bags"
--   DROPA {item, s, r}      whispered back by a member who can use it: s = "g" can learn it now, "r" skill too low; r = skill
-- Each receiver decides from its own tooltip (RecipeCheck); nothing but ids, a letter and a number travels.
-- Drops and answers live in memory for the session; only the settings are stored (SavedVariables ui.drops).

---@class RecipeDropSettings
---@field share boolean tell the guild about my recipe drops and answer theirs
---@field chat boolean chat lines (my drop, a drop I can learn)
---@field icon boolean minimap button shows the news icon for a drop I can learn

---@class DropAnswer
---@field s "g"|"r"
---@field r integer skill
---@field at number

---@class MyDrop
---@field itemID integer
---@field at number
---@field answers table<string, DropAnswer>

---@class DropAlert
---@field itemID integer
---@field from string looter
---@field rank integer|nil my skill
---@field at number

---@class HintRow
---@field name string escaped display name
---@field rank integer
---@field color "green"|"red"

---@class RecipeDropsModule
local RecipeDrops = {}
addon.RecipeDrops = RecipeDrops

---@type RecipeDropSettings
RecipeDrops.DEFAULTS = { share = true, chat = true, icon = true }
RecipeDrops.MAXIMUM_DROPS = 20          -- my drops kept for the tooltip
RecipeDrops.ANSWER_SECONDS = 15 * 60    -- answers accepted this long after the drop
RecipeDrops.DUPLICATE_SECONDS = 60      -- the same DROP from the same sender again within this time is ignored
RecipeDrops.HINT_NAMES = 3              -- names shown in the tooltip before "..."
RecipeDrops.MAXIMUM_ITEM_ID = 10000000
RecipeDrops.MAXIMUM_ALERTS = 10

---@type MyDrop[] newest first
RecipeDrops.mine = {}
---@type table<string, number> "sender:itemID" -> when that DROP was handled
RecipeDrops.seen = {}
---@type DropAlert[] newest first
RecipeDrops.alerts = {}

------------------------------------------------------------------ settings

-- A setting with its default; anything stored with the wrong type gives the default.
---@param interfaceSettings table|nil SavedVariables ui table
---@param settingKey string
---@return boolean
function RecipeDrops.Get(interfaceSettings, settingKey)
    local stored
    if type(interfaceSettings) == "table" and type(interfaceSettings.drops) == "table" then stored = interfaceSettings.drops[settingKey] end
    local defaultValue = RecipeDrops.DEFAULTS[settingKey]
    if type(stored) ~= type(defaultValue) then return defaultValue end
    return stored
end

---@param interfaceSettings table|nil
---@param settingKey string
---@param value boolean
---@return boolean changed false for an unknown key or no table
function RecipeDrops.Set(interfaceSettings, settingKey, value)
    if type(interfaceSettings) ~= "table" or RecipeDrops.DEFAULTS[settingKey] == nil or type(value) ~= "boolean" then return false end
    interfaceSettings.drops = type(interfaceSettings.drops) == "table" and interfaceSettings.drops or {}
    interfaceSettings.drops[settingKey] = value
    return true
end

------------------------------------------------------------------ message checks

---@param value any
---@return integer|nil
local function itemIDOf(value) return addon.Utility.SafeInteger(value, 1, RecipeDrops.MAXIMUM_ITEM_ID) end

-- The item id of a DROP message, or nil for anything malformed.
---@param message any
---@return integer|nil
function RecipeDrops.SanitizeDrop(message)
    return type(message) == "table" and itemIDOf(message.item) or nil
end

-- itemID, status, rank of a DROPA message, or nil for anything malformed.
---@param message any
---@return integer|nil itemID
---@return "g"|"r"|nil status
---@return integer|nil rank
function RecipeDrops.SanitizeAnswer(message)
    if type(message) ~= "table" then return nil end
    local itemID, rank = itemIDOf(message.item), addon.Utility.SafeInteger(message.r, 0, 1000)
    if not itemID or not rank or (message.s ~= "g" and message.s ~= "r") then return nil end
    return itemID, message.s, rank
end

-- What a receiver answers for its own decision (RecipeCheck.Decide): "g" learnable, "r" skill too low, nil otherwise.
---@param decision RecipeDecision|nil
---@return "g"|"r"|nil
function RecipeDrops.AnswerStatus(decision)
    if type(decision) ~= "table" then return nil end
    if decision.status == "learnable" then return "g" end
    if decision.status == "low" then return "r" end
    return nil
end

-- True when the same sender announced the same item within DUPLICATE_SECONDS (and notes it otherwise).
---@param sender string
---@param itemID integer
---@param now number
---@return boolean
function RecipeDrops.IsDuplicate(sender, itemID, now)
    local key = tostring(sender) .. ":" .. tostring(itemID)
    local previous = RecipeDrops.seen[key]
    if previous and now - previous < RecipeDrops.DUPLICATE_SECONDS then return true end
    RecipeDrops.seen[key] = now
    for seenKey, seenAt in pairs(RecipeDrops.seen) do   -- forget old entries
        if now - seenAt >= RecipeDrops.DUPLICATE_SECONDS then RecipeDrops.seen[seenKey] = nil end
    end
    return false
end

------------------------------------------------------------------ my drops and their answers

---@param itemID integer
---@return MyDrop|nil
function RecipeDrops.MyDrop(itemID)
    for _, drop in ipairs(RecipeDrops.mine) do if drop.itemID == itemID then return drop end end
    return nil
end

-- Notes a recipe that dropped for me (a second drop of the same item starts its answers anew).
---@param itemID integer
---@param now number
---@return MyDrop
function RecipeDrops.NoteMyDrop(itemID, now)
    for index, drop in ipairs(RecipeDrops.mine) do
        if drop.itemID == itemID then table.remove(RecipeDrops.mine, index) break end
    end
    local drop = { itemID = itemID, at = now, answers = {} }
    table.insert(RecipeDrops.mine, 1, drop)
    while #RecipeDrops.mine > RecipeDrops.MAXIMUM_DROPS do table.remove(RecipeDrops.mine) end
    return drop
end

-- Stores an answer to one of my drops; false for an answer to anything else (malformed, not my drop, too late).
---@param sender any
---@param message any
---@param now number
---@return boolean
function RecipeDrops.AddAnswer(sender, message, now)
    if not addon.Utility.IsSafeName(sender) then return false end
    local itemID, status, rank = RecipeDrops.SanitizeAnswer(message)
    local drop = itemID and RecipeDrops.MyDrop(itemID)
    if not drop or now - drop.at > RecipeDrops.ANSWER_SECONDS then return false end
    drop.answers[sender] = { s = status, r = rank, at = now }
    return true
end

-- The names to show for one of my drops: green before red, then higher skill, then name; at most HINT_NAMES.
-- nil when the item did not drop for me.
---@param itemID integer
---@param displayName? fun(name: string): string short display form of a member name
---@return { rows: HintRow[], more: integer, answered: integer }|nil
function RecipeDrops.HintRows(itemID, displayName)
    local drop = RecipeDrops.MyDrop(itemID)
    if not drop then return nil end
    local sorted = {}
    for name, answer in pairs(drop.answers) do sorted[#sorted + 1] = { name = name, answer = answer } end
    table.sort(sorted, function(left, right)
        if left.answer.s ~= right.answer.s then return left.answer.s == "g" end
        if left.answer.r ~= right.answer.r then return left.answer.r > right.answer.r end
        return left.name < right.name
    end)
    local rows = {}
    for index = 1, math.min(#sorted, RecipeDrops.HINT_NAMES) do
        local entry = sorted[index]
        local shown = displayName and displayName(entry.name) or entry.name
        rows[#rows + 1] = { name = addon.Utility.Escape(shown), rank = entry.answer.r, color = entry.answer.s == "g" and "green" or "red" }
    end
    return { rows = rows, more = math.max(0, #sorted - #rows), answered = #sorted }
end

------------------------------------------------------------------ alerts (drops I can learn)

---@param itemID integer
---@param from string
---@param rank integer|nil
---@param now number
---@return DropAlert
function RecipeDrops.AddAlert(itemID, from, rank, now)
    local alert = { itemID = itemID, from = from, rank = rank, at = now }
    table.insert(RecipeDrops.alerts, 1, alert)
    while #RecipeDrops.alerts > RecipeDrops.MAXIMUM_ALERTS do table.remove(RecipeDrops.alerts) end
    return alert
end

function RecipeDrops.ClearAlerts()
    for index = #RecipeDrops.alerts, 1, -1 do RecipeDrops.alerts[index] = nil end
end

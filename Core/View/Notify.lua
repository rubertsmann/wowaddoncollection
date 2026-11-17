local addonName, addon = ...

-- Feature 010: what is new on the order board for this player (pure; the UI plays the sound, sets the badge etc.).
--   seen[orderID] = the order's state when the player last looked at the Orders tab (see Notify.StateKey)
--   An order is unseen when
--     * someone else's OPEN order is relevant to me (scope, see Notify.Relevant) and I never saw it, or
--     * MY order got a new claimer or was marked done by someone and I have not looked since.
-- The setting keys below are stored in SavedVariables (db.ui.notify) and stay as they are.

---@alias NotifyScope "profession"|"known"|"all"

---@class NotifySettings
---@field badge boolean number on the minimap button
---@field icon boolean minimap button shows a letter while something is unseen
---@field sound boolean
---@field chat boolean one chat line per new order
---@field screen boolean message in the middle of the screen
---@field flash boolean flash the game's taskbar icon (when the game is in the background)
---@field mine boolean my orders: claimed / done by someone
---@field scope NotifyScope
---@field soundName string

---@class UnseenOrder
---@field id string order id
---@field kind "new"|"claimed"|"done"
---@field key string the state key that was not seen
---@field order Order

---@class NotifyModule
local Notify = {}
addon.Notify = Notify

---@type NotifyScope[]
Notify.SCOPES = { "profession", "known", "all" }
---@type NotifySettings
Notify.DEFAULTS = {
    badge = true,
    icon = true,
    sound = true,
    chat = true,
    screen = false,
    flash = false,
    mine = true,
    scope = "profession",
    soundName = "IG_PLAYER_INVITE",
}
-- SOUNDKIT names offered in the options, with the sound kit id used when SOUNDKIT lacks the name on this client.
---@type { [1]: string, [2]: integer }[]
Notify.SOUNDS = { { "IG_PLAYER_INVITE", 880 }, { "MAP_PING", 3175 }, { "AUCTION_WINDOW_OPEN", 5274 }, { "READY_CHECK", 8960 } }
Notify.THROTTLE_SECONDS = 10   -- seconds between two sounds / screen messages / flashes

-- Setting with default; `interfaceSettings` is the SavedVariables ui table (may be nil). Invalid stored values give the default.
---@param interfaceSettings table|nil
---@param settingKey string
---@return any
function Notify.Get(interfaceSettings, settingKey)
    local storedSettings = type(interfaceSettings) == "table" and type(interfaceSettings.notify) == "table" and interfaceSettings.notify or nil
    local storedValue = storedSettings and storedSettings[settingKey]
    local defaultValue = Notify.DEFAULTS[settingKey]
    if type(storedValue) ~= type(defaultValue) then return defaultValue end
    if settingKey == "scope" then
        for _, scope in ipairs(Notify.SCOPES) do if scope == storedValue then return storedValue end end
        return defaultValue
    end
    if settingKey == "soundName" then
        for _, sound in ipairs(Notify.SOUNDS) do if sound[1] == storedValue then return storedValue end end
        return defaultValue
    end
    return storedValue
end

---@param interfaceSettings table|nil
---@param settingKey string
---@param value any
function Notify.Set(interfaceSettings, settingKey, value)
    if type(interfaceSettings) ~= "table" or Notify.DEFAULTS[settingKey] == nil then return end
    interfaceSettings.notify = type(interfaceSettings.notify) == "table" and interfaceSettings.notify or {}
    interfaceSettings.notify[settingKey] = value
end

-- The part of an order whose change is worth telling its requester: status plus who claimed it.
---@param orderBoard OrderBoard
---@param order Order
---@return string
function Notify.StateKey(orderBoard, order)
    local status = orderBoard:Status(order)
    if status == "claimed" then return "claimed:" .. table.concat(orderBoard:Claimers(order), ",") end
    if status == "done" then return "done:" .. tostring(order.closedBy or "") end
    return status
end

-- Profession keys (Names.ProfessionKey: skill line id or name) that hold recipeID for anyone in the store.
---@param store StoreModule
---@param recipeID integer
---@return table<integer|string, boolean>
local function professionsWithRecipe(store, recipeID)
    local professionKeys = {}
    for _, characterRecord in ipairs(store.ListCharacters()) do
        for professionKey, profession in pairs(characterRecord.professions or {}) do
            if type(profession) == "table" and type(profession.recipes) == "table" and profession.recipes[recipeID] then
                professionKeys[addon.Names.ProfessionKey(professionKey, profession)] = true
            end
        end
    end
    return professionKeys
end

-- Is someone else's order for recipeID something I could craft?
--   "known": I know the recipe; "profession": I know it, or I have the profession it belongs to (taken from the guild
--   members who know it); "all": every order.
---@param store StoreModule
---@param myName string|nil
---@param recipeID integer
---@param scope NotifyScope
---@return boolean
function Notify.Relevant(store, myName, recipeID, scope)
    if scope == "all" then return true end
    local myRecord = store.GetCharacter(myName or "")
    if not myRecord then return false end
    if addon.Store.Knows(myRecord, recipeID) then return true end
    if scope ~= "profession" then return false end
    local recipeProfessionKeys = professionsWithRecipe(store, recipeID)
    for professionKey, profession in pairs(myRecord.professions or {}) do
        if type(profession) == "table" and recipeProfessionKeys[addon.Names.ProfessionKey(professionKey, profession)] then return true end
    end
    return false
end

---@class NotifyOptions
---@field scope NotifyScope
---@field mine boolean

-- Unseen orders, oldest first.
---@param store StoreModule
---@param orderBoard OrderBoard
---@param myName string|nil
---@param seen table<string, string>|nil
---@param options NotifyOptions
---@return UnseenOrder[]
function Notify.Unseen(store, orderBoard, myName, seen, options)
    seen = type(seen) == "table" and seen or {}
    local unseenOrders = {}
    for orderID, order in pairs(orderBoard.db) do
        local status = orderBoard:Status(order)
        if order.requester == myName then
            if options.mine and (status == "claimed" or status == "done") then
                local stateKey = Notify.StateKey(orderBoard, order)
                local changedBySomeoneElse = status == "done" and order.closedBy ~= myName
                if status == "claimed" then
                    for _, crafter in ipairs(orderBoard:Claimers(order)) do if crafter ~= myName then changedBySomeoneElse = true end end
                end
                if changedBySomeoneElse and seen[orderID] ~= stateKey then
                    unseenOrders[#unseenOrders + 1] = { id = orderID, kind = status, key = stateKey, order = order }
                end
            end
        elseif status == "open" and seen[orderID] == nil and Notify.Relevant(store, myName, order.recipeID, options.scope) then
            unseenOrders[#unseenOrders + 1] = { id = orderID, kind = "new", key = "new", order = order }
        end
    end
    table.sort(unseenOrders, function(left, right)
        local leftCreated, rightCreated = left.order.createdAt or 0, right.order.createdAt or 0
        if leftCreated ~= rightCreated then return leftCreated < rightCreated end
        return left.id < right.id
    end)
    return unseenOrders
end

-- Remember the current state of every order (the player looked at the board); forget orders that are gone.
-- Returns the (same or new) seen table.
---@param orderBoard OrderBoard
---@param seen table<string, string>|nil
---@return table<string, string>
function Notify.MarkSeen(orderBoard, seen)
    seen = type(seen) == "table" and seen or {}
    for orderID in pairs(seen) do
        if orderBoard.db[orderID] == nil then seen[orderID] = nil end
    end
    for orderID, order in pairs(orderBoard.db) do seen[orderID] = Notify.StateKey(orderBoard, order) end
    return seen
end

-- Items of `unseenOrders` that were not in the previous result (id + state key: a new claimer counts again), and the new
-- key set to pass next time.
---@param previousKeys table<string, boolean>|nil
---@param unseenOrders UnseenOrder[]
---@return UnseenOrder[] fresh
---@return table<string, boolean> currentKeys
function Notify.Fresh(previousKeys, unseenOrders)
    previousKeys = previousKeys or {}
    local freshOrders, currentKeys = {}, {}
    for _, unseenOrder in ipairs(unseenOrders) do
        local orderKey = unseenOrder.id .. "|" .. (unseenOrder.key or unseenOrder.kind)
        currentKeys[orderKey] = true
        if not previousKeys[orderKey] then freshOrders[#freshOrders + 1] = unseenOrder end
    end
    return freshOrders, currentKeys
end

return Notify

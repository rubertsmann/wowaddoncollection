local ADDON, ns = ...

-- Feature 010: what is new on the order board for this player (pure; the UI plays the sound, sets the badge etc.).
--   seen[id] = the order's state when the player last looked at the Orders tab (see Notify.StateKey)
--   An order is unseen when
--     * someone else's OPEN order is relevant to me (scope, see Notify.Relevant) and I never saw it, or
--     * MY order got a new claimer or was marked done by someone and I have not looked since.
local Notify = {}
ns.Notify = Notify

Notify.SCOPES = { "profession", "known", "all" }
Notify.DEFAULTS = {
    badge = true,      -- number on the minimap button
    icon = true,       -- minimap button shows a letter while something is unseen
    sound = true,
    chat = true,       -- one chat line per new order
    screen = false,    -- message in the middle of the screen
    flash = false,     -- flash the game's taskbar icon (when the game is in the background)
    mine = true,       -- my orders: claimed / done by someone
    scope = "profession",
    soundName = "IG_PLAYER_INVITE",
}
-- SOUNDKIT names offered in the options, with the sound kit id used when SOUNDKIT lacks the name on this client.
Notify.SOUNDS = { { "IG_PLAYER_INVITE", 880 }, { "MAP_PING", 3175 }, { "AUCTION_WINDOW_OPEN", 5274 }, { "READY_CHECK", 8960 } }
Notify.THROTTLE = 10   -- seconds between two sounds / screen messages / flashes

-- Setting with default; ui: the SavedVariables ui table (may be nil).
function Notify.Get(ui, key)
    local t = type(ui) == "table" and type(ui.notify) == "table" and ui.notify or nil
    local v = t and t[key]
    local d = Notify.DEFAULTS[key]
    if type(v) ~= type(d) then return d end
    if key == "scope" then
        for _, s in ipairs(Notify.SCOPES) do if s == v then return v end end
        return d
    end
    if key == "soundName" then
        for _, s in ipairs(Notify.SOUNDS) do if s[1] == v then return v end end
        return d
    end
    return v
end

function Notify.Set(ui, key, value)
    if type(ui) ~= "table" or Notify.DEFAULTS[key] == nil then return end
    ui.notify = type(ui.notify) == "table" and ui.notify or {}
    ui.notify[key] = value
end

-- The part of an order whose change is worth telling its requester: status plus who claimed it.
function Notify.StateKey(orders, o)
    local st = orders:Status(o)
    if st == "claimed" then return "claimed:" .. table.concat(orders:Claimers(o), ",") end
    if st == "done" then return "done:" .. tostring(o.closedBy or "") end
    return st
end

local function knows(rec, recipeID)
    for _, p in pairs(rec and rec.professions or {}) do
        if type(p) == "table" and type(p.recipes) == "table" and p.recipes[recipeID] then return true end
    end
    return false
end

-- Profession keys (Names.ProfKey: skill line id or name) that hold recipeID for anyone in the store.
local function recipeProfessions(store, recipeID)
    local out = {}
    for _, rec in ipairs(store.ListChars()) do
        for pname, p in pairs(rec.professions or {}) do
            if type(p) == "table" and type(p.recipes) == "table" and p.recipes[recipeID] then
                out[ns.Names.ProfKey(pname, p)] = true
            end
        end
    end
    return out
end

-- Is someone else's order for recipeID something I could craft?
--   "known": I know the recipe; "profession": I know it, or I have the profession it belongs to (taken from the guild
--   members who know it); "all": every order.
function Notify.Relevant(store, me, recipeID, scope)
    if scope == "all" then return true end
    local rec = store.GetChar(me or "")
    if not rec then return false end
    if knows(rec, recipeID) then return true end
    if scope ~= "profession" then return false end
    local profs = recipeProfessions(store, recipeID)
    for pname, p in pairs(rec.professions or {}) do
        if type(p) == "table" and profs[ns.Names.ProfKey(pname, p)] then return true end
    end
    return false
end

-- List of unseen orders { id, kind = "new"|"claimed"|"done", order }, oldest first.
-- opts: { scope, mine } (Notify.Get values)
function Notify.Unseen(store, orders, me, seen, opts)
    seen = type(seen) == "table" and seen or {}
    local out = {}
    for id, o in pairs(orders.db) do
        local st = orders:Status(o)
        if o.requester == me then
            if opts.mine and (st == "claimed" or st == "done") then
                local key = Notify.StateKey(orders, o)
                local claimedByOther = st == "done" and o.closedBy ~= me
                if st == "claimed" then
                    for _, c in ipairs(orders:Claimers(o)) do if c ~= me then claimedByOther = true end end
                end
                if claimedByOther and seen[id] ~= key then out[#out + 1] = { id = id, kind = st, key = key, order = o } end
            end
        elseif st == "open" and seen[id] == nil and Notify.Relevant(store, me, o.recipeID, opts.scope) then
            out[#out + 1] = { id = id, kind = "new", key = "new", order = o }
        end
    end
    table.sort(out, function(a, b)
        if (a.order.createdAt or 0) ~= (b.order.createdAt or 0) then return (a.order.createdAt or 0) < (b.order.createdAt or 0) end
        return a.id < b.id
    end)
    return out
end

-- Remember the current state of every order (the player looked at the board); forget orders that are gone.
-- Returns the (same or new) seen table.
function Notify.MarkSeen(orders, seen)
    seen = type(seen) == "table" and seen or {}
    for id in pairs(seen) do
        if orders.db[id] == nil then seen[id] = nil end
    end
    for id, o in pairs(orders.db) do seen[id] = Notify.StateKey(orders, o) end
    return seen
end

-- Items of `list` that were not in the previous result (id + state key: a new claimer counts again), and the new id set to pass next time.
function Notify.Fresh(prev, list)
    prev = prev or {}
    local fresh, now = {}, {}
    for _, it in ipairs(list) do
        local k = it.id .. "|" .. (it.key or it.kind)
        now[k] = true
        if not prev[k] then fresh[#fresh + 1] = it end
    end
    return fresh, now
end

return Notify

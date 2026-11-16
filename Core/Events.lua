local ADDON, ns = ...

-- Internal pub/sub + WoW event wiring. Scans are debounced; the guild gets a HELLO when my data changes.
local Ev = {}
ns.Events = Ev

local handlers = {}
function Ev.On(name, fn)
    handlers[name] = handlers[name] or {}
    table.insert(handlers[name], fn)
end

function Ev.Fire(name, ...)
    for _, fn in ipairs(handlers[name] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then ns.Util.ReportError(err) end
    end
end

-- /ts clean: deletes everything cached locally (guild characters, recipes, orders, learned names, debug log).
-- Two steps because it cannot be undone; your own data comes back when your professions are scanned again and
-- online guild members are asked to send theirs.
ns.Slash.clean = function(arg)
    local word = (arg or ""):match("^%s*(%S*)")
    if not ns.db then return end
    if word ~= "confirm" then
        local n = ns.Store.Counts()
        ns.Print(("clean would delete %d characters (%d recipes), %d catalog entries, %d orders. Type %s clean confirm to do it."):format(
            n.chars, n.recipes, n.catalog, n.orders, ns.SLASH[1]))
        return
    end
    local n = ns.Store.Clean()
    ns.Locale.version = ns.Locale.version + 1     -- invalidates the name caches
    if ns.UI then ns.UI.autoScanTried = false end -- the next window open scans your professions again
    Ev.Fire("DATA_CHANGED", "chars")
    ns.Comm.RequestHello(true, true)              -- ask online guild members to introduce themselves, then pull their data
    ns.Print(("cleaned: removed %d characters, %d catalog entries, %d orders. Reopen the window to rescan your professions."):format(
        n.chars, n.catalog, n.orders))
end

local pendingScan = false
local function scheduleScan(delay)
    if pendingScan then return end
    pendingScan = true
    C_Timer.After(delay or 1.0, function()
        pendingScan = false
        local changed = ns.Scanner.Refresh(ns.Util.Now())
        ns.Debug.Log("scan", changed and "changed" or "same")
        if changed then
            Ev.Fire("LOCAL_CHANGED")
            Ev.Fire("DATA_CHANGED", "chars")
        end
    end)
end

Ev.On("LOCAL_CHANGED", function() ns.Comm.RequestHello(false, true) end)
Ev.On("WINDOW_OPENED", function() ns.Comm.RequestHello(false, false) end)

local frame = CreateFrame("Frame")
local function reg(event)
    pcall(frame.RegisterEvent, frame, event)  -- unknown events on this client must not break loading
end

local onEvent = {}

function onEvent.ADDON_LOADED(name)
    if name ~= ADDON then return end
    _G[ns.SVNAME] = ns.Store.Init(_G[ns.SVNAME])
    ns.Locale.SetUI(ns.db.ui.locale)   -- /ts locale <code> override for testing translations; nil = game client language
    ns.orders = ns.Orders.New(ns.Util.Now, ns.db.orders)
    ns.Comm.Init()
end

function onEvent.PLAYER_LOGIN()
    ns.Store.db.me = ns.Api.GetPlayerInfo().name
    ns.Comm.Start()
    C_Timer.After(3, function()
        local changed = ns.Scanner.Refresh(ns.Util.Now())
        ns.Comm.Start()
        ns.Comm.RequestHello(true, true)  -- login=true: online peers answer with their own HELLO
        if changed then Ev.Fire("DATA_CHANGED", "chars") end
    end)
end

function onEvent.CHAT_MSG_ADDON(prefix, text, channel, sender)
    ns.Comm.OnAddonMessage(prefix, text, channel, sender)
end

function onEvent.GUILD_ROSTER_UPDATE()
    ns.Comm.Start()
    if ns.Comm.active then ns.Comm.PruneRoster() end
end

function onEvent.PLAYER_GUILD_UPDATE() ns.Comm.Start() end
function onEvent.PLAYER_LEVEL_UP() scheduleScan(2) end
function onEvent.TRADE_SKILL_SHOW() scheduleScan(1.5) end
function onEvent.TRADE_SKILL_LIST_UPDATE() scheduleScan(1.0) end
function onEvent.TRADE_SKILL_DATA_SOURCE_CHANGED() scheduleScan(1.0) end
function onEvent.SKILL_LINES_CHANGED() scheduleScan(2.0) end
function onEvent.NEW_RECIPE_LEARNED() scheduleScan(1.5) end   -- keeps the cache current without reopening the window
function onEvent.GET_ITEM_INFO_RECEIVED() Ev.Fire("ITEM_INFO") end

for event in pairs(onEvent) do reg(event) end
frame:SetScript("OnEvent", function(_, event, ...)
    local fn = onEvent[event]
    if fn then
        local ok, err = pcall(fn, ...)
        if not ok then ns.Util.ReportError(err) end
    end
end)

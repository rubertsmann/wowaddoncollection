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
function onEvent.GET_ITEM_INFO_RECEIVED() Ev.Fire("ITEM_INFO") end

for event in pairs(onEvent) do reg(event) end
frame:SetScript("OnEvent", function(_, event, ...)
    local fn = onEvent[event]
    if fn then
        local ok, err = pcall(fn, ...)
        if not ok then ns.Util.ReportError(err) end
    end
end)

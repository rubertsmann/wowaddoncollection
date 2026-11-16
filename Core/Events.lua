local ADDON, ns = ...

-- Internal pub/sub + WoW event wiring. Scans are debounced; the guild gets a HELLO when my data changes.
local Ev = {}
ns.Events = Ev

-- Events.lua loads after every module it depends on. If one is missing, the TOC in use is out of date: typically the
-- generated TalentShare-Dev.toc after a new file was added to TalentShare.toc (tools/deploy.ps1 regenerates it). Without
-- this the player only sees a chain of "attempt to index a nil value" errors from the files that needed the module.
do
    local missing = {}
    for _, key in ipairs({ "Util", "Locale", "Store", "Names", "Api", "Scanner", "Codec", "Guard", "Orders", "Offers", "Sync", "Model", "Comm", "Trace", "Diag" }) do
        if not ns[key] then missing[#missing + 1] = key end
    end
    if #missing > 0 then
        ns.Print("not loaded: " .. table.concat(missing, ", ") .. ". The TOC is out of date. Dev build: run tools/deploy.ps1 (it regenerates TalentShare-Dev.toc), then restart the game (/reload does not re-read the TOC).")
    end
end

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
        ns.Print(("clean would delete %d characters (%d recipes), %d catalog entries, %d orders, %d offered items. Type %s clean confirm to do it."):format(
            n.chars, n.recipes, n.catalog, n.orders, n.offers, ns.SLASH[1]))
        return
    end
    local n = ns.Store.Clean()
    ns.Locale.version = ns.Locale.version + 1     -- invalidates the name caches
    Ev.Fire("DATA_CHANGED", "chars")
    ns.Comm.RequestHello(true, true)              -- ask online guild members to introduce themselves, then pull their data
    ns.Print(("cleaned: removed %d characters, %d catalog entries, %d orders, %d offered items. Click your profession icons in the window to scan them again."):format(
        n.chars, n.catalog, n.orders, n.offers))
    Ev.ScanItems(1.0)                             -- my own items are read again right away
end

local pendingScan = false
local function scheduleScan(delay)
    if pendingScan then return end
    pendingScan = true
    C_Timer.After(delay or 1.0, function()
        pendingScan = false
        local changed = ns.Scanner.Refresh(ns.Util.Now())
        ns.Debug.Log("scan", changed and "changed" or "same", ns.Scanner.lastOpen)
        if changed then
            Ev.Fire("LOCAL_CHANGED")
        end
        Ev.Fire("DATA_CHANGED", "chars")   -- also when unchanged: the profession buttons' counters must stay current
    end)
end

-- Recipe items (feature 007): bags are read at any time, bank/mail/guild bank/auctions only while their window is open
-- (Api.open); a location that cannot be read keeps its last known state. A changed record is announced with a HELLO.
local pendingItems = false
local function scheduleItemScan(delay)
    if pendingItems then return end
    pendingItems = true
    C_Timer.After(delay or 1.5, function()
        pendingItems = false
        local me = ns.Store.db.me or ns.Api.GetPlayerInfo().name
        if not me then return end
        local ok, scans = pcall(ns.Api.ScanItems)
        if not ok then ns.Debug.Log("items.error", scans) return end
        local changed = ns.Offers.Update(me, scans, ns.Util.Now())
        ns.Debug.Log("items", changed and "changed" or "same", ns.Api.scanStats.recipes)
        if changed then Ev.Fire("OFFERS_CHANGED") end
        Ev.Fire("DATA_CHANGED", "offers-local")
    end)
end
Ev.ScanItems = scheduleItemScan

Ev.On("LOCAL_CHANGED", function() ns.Comm.RequestHello(false, true) end)
Ev.On("OFFERS_CHANGED", function() ns.Comm.RequestHello(false, true) end)
-- a record from a peer arrived: drop MY dibs on items that are gone (the new record may have removed them)
Ev.On("DATA_CHANGED", function(kind)
    if kind ~= "offers" or not ns.db or ns.db.readonly then return end
    local me = ns.Store.db.me
    if me and ns.Offers.Maintain(me, ns.Util.Now()) then
        Ev.Fire("OFFERS_CHANGED")
        Ev.Fire("DATA_CHANGED", "offers-local")
    end
    ns.Offers.PruneHidden()
end)
Ev.On("WINDOW_OPENED", function() ns.Comm.RequestHello(false, false) end)

local frame = CreateFrame("Frame")
local function reg(event)
    pcall(frame.RegisterEvent, frame, event)  -- unknown events on this client must not break loading
end

local onEvent = {}

function onEvent.ADDON_LOADED(name)
    if name ~= ADDON then return end
    -- status "newer": Init hands back the ORIGINAL table, so assigning it keeps the newer data on disk untouched while this
    -- session runs on a throwaway database (docs/protocol.md "Stored data")
    local sv, status = ns.Store.Init(_G[ns.SVNAME])
    _G[ns.SVNAME] = sv
    ns.dbStatus = status
    ns.Locale.SetUI(ns.db.ui.locale)   -- /ts locale <code> override for testing translations; nil = game client language
    ns.orders = ns.Orders.New(ns.Util.Now, ns.db.orders)
    ns.Comm.Init()
end

function onEvent.PLAYER_LOGIN()
    ns.Store.db.me = ns.Api.GetPlayerInfo().name
    ns.Store.Recanon()     -- names stored by older builds (or under another realm spelling) get their canonical key
    ns.Comm.canonVersion = ns.Util.realmAliasVersion
    -- first login with another version than the data was saved with: drop what other members sent (Store.ResetPeerData)
    local ver = (ns.BASE_VERSION:gsub("%-dev$", ""))
    if not ns.db.readonly and ns.db.version ~= ver then
        local n = ns.Store.ResetPeerData(ns.Store.db.me)
        if (n.chars + n.offers + n.catalog) > 0 then
            ns.Debug.Log("version.reset", tostring(ns.db.version) .. " -> " .. ver, n.chars, n.offers, n.catalog)
            C_Timer.After(5, function()
                ns.Print((ns.L["version %s: guild data is fetched again (your own recipes and orders are kept)"]):format(ver))
            end)
        end
        ns.db.version = ver
        ns.Locale.version = ns.Locale.version + 1   -- invalidates the name caches
    end
    ns.Comm.ready = true   -- the current character is known now; Comm.Start refuses to run before this
    ns.Comm.Start()
    if ns.dbStatus == "newer" then
        C_Timer.After(5, function()   -- after the chat frame is up
            ns.Print(ns.L["Saved data was written by a newer TalentShare and is left untouched. Nothing is saved this session. Please update the addon."])
        end)
    end
    C_Timer.After(3, function()
        -- the realm part comes from GetNormalizedRealmName, which can be empty very early at login: build the name again
        local name = ns.Api.GetPlayerInfo().name
        if name and name ~= ns.Store.db.me then
            ns.Trace.Sys("warn", "identity changed after login", tostring(ns.Store.db.me) .. " -> " .. name)
            ns.Store.db.me = name
            ns.Comm.canonVersion = nil
            ns.Comm.Recanon()
        end
        local changed = ns.Scanner.Refresh(ns.Util.Now())
        ns.Comm.Start()
        scheduleItemScan(0.5)
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
function onEvent.TRADE_SKILL_SHOW()
    ns.Debug.Log("event", "TRADE_SKILL_SHOW")   -- a profession window really opened (after a click on a profession button)
    scheduleScan(1.5)
end

-- The game's red error text (e.g. "no target", "action blocked") for 6 s after a click on a profession button, so a
-- button that opens nothing can be explained from the log.
function onEvent.UI_ERROR_MESSAGE(...)
    if not (ns.UI and ns.UI.RecentBarClick and ns.UI.RecentBarClick()) then return end
    local msg
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "string" then msg = v end
    end
    ns.Debug.Log("uierror", msg)
end
function onEvent.TRADE_SKILL_LIST_UPDATE() scheduleScan(1.0) end
function onEvent.TRADE_SKILL_DATA_SOURCE_CHANGED() scheduleScan(1.0) end
function onEvent.SKILL_LINES_CHANGED() scheduleScan(2.0) end
function onEvent.NEW_RECIPE_LEARNED() scheduleScan(1.5) end   -- keeps the cache current without reopening the window
function onEvent.GET_ITEM_INFO_RECEIVED() Ev.Fire("ITEM_INFO") end

-- recipe item locations (events that do not exist on this client are skipped by `reg`)
function onEvent.BAG_UPDATE_DELAYED() scheduleItemScan(1.5) end
local function openClose(key, isOpen)
    return function()
        ns.Api.open[key] = isOpen
        ns.Debug.Log("window", key, isOpen and "open" or "closed")
        if isOpen then scheduleItemScan(1.0) end
    end
end
onEvent.BANKFRAME_OPENED, onEvent.BANKFRAME_CLOSED = openClose("bank", true), openClose("bank", false)
onEvent.MAIL_SHOW, onEvent.MAIL_CLOSED = openClose("mail", true), openClose("mail", false)
onEvent.GUILDBANKFRAME_OPENED, onEvent.GUILDBANKFRAME_CLOSED = openClose("gbank", true), openClose("gbank", false)
onEvent.AUCTION_HOUSE_SHOW, onEvent.AUCTION_HOUSE_CLOSED = openClose("auction", true), openClose("auction", false)
function onEvent.PLAYERBANKSLOTS_CHANGED() scheduleItemScan(1.5) end
function onEvent.PLAYERBANKBAGSLOTS_CHANGED() scheduleItemScan(1.5) end
function onEvent.PLAYERREAGENTBANKSLOTS_CHANGED() scheduleItemScan(1.5) end
function onEvent.MAIL_INBOX_UPDATE() scheduleItemScan(1.5) end
function onEvent.GUILDBANKBAGSLOTS_CHANGED() scheduleItemScan(1.5) end
function onEvent.AUCTION_OWNED_LIST_UPDATE() scheduleItemScan(1.5) end
function onEvent.OWNED_AUCTIONS_UPDATED() scheduleItemScan(1.5) end

-- /ts offers [scan]: what the item scan can see on this client and what my offers record holds (also the in-game probe)
ns.Slash.offers = function(arg)
    local api = ns.Api
    if (arg or ""):match("^%s*scan") then
        local ok, scans = pcall(api.ScanItems)
        if not ok then ns.Print("scan failed: " .. tostring(scans)) return end
        local me = ns.Store.db.me or api.GetPlayerInfo().name
        local changed = ns.Offers.Update(me, scans, ns.Util.Now())
        if changed then Ev.Fire("OFFERS_CHANGED") end
        Ev.Fire("DATA_CHANGED", "offers-local")
        ns.Print("scan: " .. (changed and "updated" or "unchanged"))
    end
    local function has(v) return v and "yes" or "NO" end
    ns.Print(("APIs: C_Container %s, legacy container %s, item class %s, mail %s, guild bank %s, auction (modern/classic) %s/%s"):format(
        has(C_Container and C_Container.GetContainerItemInfo), has(GetContainerItemInfo),
        has((C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant), has(GetInboxItem and GetInboxNumItems),
        has(GetGuildBankItemLink), has(C_AuctionHouse and C_AuctionHouse.GetNumOwnedAuctions), has(GetNumAuctionItems)))
    local o = api.open
    ns.Print(("windows open: bank %s, mail %s, guild bank %s, auction %s"):format(tostring(o.bank), tostring(o.mail), tostring(o.gbank), tostring(o.auction)))
    local st = api.scanStats
    ns.Print(("last scan: %d items seen, %d recipes (%d bound, not offered), %d with unknown class"):format(st.items, st.recipes, st.bound, st.unknownClass))
    local rec = ns.Offers.Get(ns.Store.db.me or "")
    if not rec then ns.Print("no offers record yet (no tradeable recipe item found)") return end
    local perLoc = {}
    for id, locs in pairs(rec.items) do
        for loc, n in pairs(locs) do
            perLoc[loc] = perLoc[loc] or {}
            table.insert(perLoc[loc], ("%s x%d"):format(api.ItemName(id) or ("item:" .. id), n))
        end
    end
    for _, loc in ipairs(ns.Offers.LOC_ORDER) do
        if perLoc[loc] then ns.Print(("%s: %s"):format(loc, table.concat(perLoc[loc], ", "))) end
    end
    local dibs = 0
    for _, d in pairs(rec.dibs) do if d.on then dibs = dibs + 1 end end
    ns.Print(("record rev %s, %d active dibs; %d offers known from the guild"):format(tostring(rec.rev), dibs, select(2, ns.Offers.Counts())))
end

for event in pairs(onEvent) do reg(event) end
frame:SetScript("OnEvent", function(_, event, ...)
    local fn = onEvent[event]
    if fn then
        local ok, err = pcall(fn, ...)
        if not ok then ns.Util.ReportError(err) end
    end
end)

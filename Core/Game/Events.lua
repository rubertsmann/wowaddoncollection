local addonName, addon = ...

-- Internal pub/sub + WoW event wiring. Scans are debounced; the guild gets a HELLO when my data changes.
-- Internal events: DATA_CHANGED(kind), LOCAL_CHANGED, OFFERS_CHANGED, WINDOW_OPENED, TRADESKILL(isOpen), ITEM_INFO.
-- Every handler runs protected: an error in one handler is logged (Log.Exception, with stack) and the others still run.
---@class EventsModule
local Events = {}
addon.Events = Events

-- Events.lua loads after every module it depends on. If one is missing, the TOC in use is out of date: typically the
-- generated TalentShare-Dev.toc after a new file was added to TalentShare.toc (tools/deploy.ps1 regenerates it). Without
-- this the player only sees a chain of "attempt to index a nil value" errors from the files that needed the module.
do
    local missingModules = {}
    for _, moduleName in ipairs({ "Utility", "Log", "Locale", "Store", "Names", "Api", "Scanner", "Codec", "Guard", "Orders",
        "Offers", "Sync", "Model", "Communication", "Trace", "Diagnostics" }) do
        if not addon[moduleName] then missingModules[#missingModules + 1] = moduleName end
    end
    if #missingModules > 0 then
        addon.Print("not loaded: " .. table.concat(missingModules, ", ") .. ". The TOC is out of date. Dev build: run tools/deploy.ps1 (it regenerates TalentShare-Dev.toc), then restart the game (/reload does not re-read the TOC).")
    end
end

---@type table<string, function[]>
local handlersByEvent = {}

---@param eventName string
---@param handler function
function Events.On(eventName, handler)
    handlersByEvent[eventName] = handlersByEvent[eventName] or {}
    table.insert(handlersByEvent[eventName], handler)
end

---@param eventName string
---@param ... any
function Events.Fire(eventName, ...)
    for _, handler in ipairs(handlersByEvent[eventName] or {}) do
        addon.Log.Protected("events.fire", "an internal event handler failed (" .. tostring(eventName) .. ")", handler, ...)
    end
end

-- /ts clean: deletes everything cached locally (guild characters, recipes, orders, learned names, log).
-- Two steps because it cannot be undone; your own data comes back when your professions are scanned again and
-- online guild members are asked to send theirs.
addon.SlashCommands.clean = function(arguments)
    local confirmationWord = (arguments or ""):match("^%s*(%S*)")
    if not addon.db then return end
    if confirmationWord ~= "confirm" then
        local counts = addon.Store.Counts()
        addon.Print(("clean would delete %d characters (%d recipes), %d catalog entries, %d orders, %d offered items. Type %s clean confirm to do it."):format(
            counts.chars, counts.recipes, counts.catalog, counts.orders, counts.offers, addon.SLASH_COMMANDS[1]))
        return
    end
    local removed = addon.Store.Clean()
    addon.Log.Information("events.clean", "local data was deleted by /ts clean confirm",
        { chars = removed.chars, catalog = removed.catalog, orders = removed.orders, offers = removed.offers })
    addon.Locale.version = addon.Locale.version + 1          -- invalidates the name caches
    Events.Fire("DATA_CHANGED", "chars")
    addon.Communication.RequestHello(true, true)              -- ask online guild members to introduce themselves, then pull their data
    addon.Print(("cleaned: removed %d characters, %d catalog entries, %d orders, %d offered items. Click your profession icons in the window to scan them again."):format(
        removed.chars, removed.catalog, removed.orders, removed.offers))
    Events.ScanItems(1.0)                                     -- my own items are read again right away
end

local professionScanPending = false
---@param delaySeconds? number
local function scheduleProfessionScan(delaySeconds)
    if professionScanPending then return end
    professionScanPending = true
    C_Timer.After(delaySeconds or 1.0, function()
        professionScanPending = false
        local ok, changed = addon.Log.Protected("events.professionScan", "the profession scan failed", addon.Scanner.Refresh,
            addon.Utility.Now())
        if not ok then return end
        addon.Log.Debug("events.professionScan", changed and "my record changed" or "my record is unchanged",
            { scanned = addon.Scanner.lastScanSummary })
        if changed then
            Events.Fire("LOCAL_CHANGED")
        end
        Events.Fire("DATA_CHANGED", "chars")   -- also when unchanged: the profession buttons' counters must stay current
    end)
end

-- Recipe items (feature 007): bags are read at any time, bank/mail/guild bank/auctions only while their window is open
-- (Api.open); a location that cannot be read keeps its last known state. A changed record is announced with a HELLO.
local itemScanPending = false
---@param delaySeconds? number
local function scheduleItemScan(delaySeconds)
    if itemScanPending then return end
    itemScanPending = true
    C_Timer.After(delaySeconds or 1.5, function()
        itemScanPending = false
        local myName = addon.Utility.Me()
        if not myName then return end
        local ok, scans = addon.Log.Protected("events.itemScan", "the recipe item scan failed", addon.Api.ScanItems)
        if not ok then return end
        local changed = addon.Offers.Update(myName, scans, addon.Utility.Now())
        addon.Log.Debug("events.itemScan", changed and "my offers changed" or "my offers are unchanged",
            { recipeItems = addon.Api.scanStatistics.recipes })
        if changed then Events.Fire("OFFERS_CHANGED") end
        Events.Fire("DATA_CHANGED", "offers-local")
    end)
end
Events.ScanItems = scheduleItemScan

Events.On("LOCAL_CHANGED", function() addon.Communication.RequestHello(false, true) end)
Events.On("OFFERS_CHANGED", function() addon.Communication.RequestHello(false, true) end)
-- a record from a peer arrived: drop MY dibs on items that are gone (the new record may have removed them)
Events.On("DATA_CHANGED", function(kind)
    if kind ~= "offers" or not addon.db or addon.db.readonly then return end
    local myName = addon.Store.db.me
    if myName and addon.Offers.Maintain(myName, addon.Utility.Now()) then
        Events.Fire("OFFERS_CHANGED")
        Events.Fire("DATA_CHANGED", "offers-local")
    end
    addon.Offers.PruneHidden()
end)
Events.On("WINDOW_OPENED", function() addon.Communication.RequestHello(false, false) end)

local eventFrame = CreateFrame("Frame")
-- unknown events on this client must not break loading
---@param gameEvent string
local function registerGameEvent(gameEvent)
    local ok = pcall(eventFrame.RegisterEvent, eventFrame, gameEvent)
    if not ok then addon.Log.Debug("events.register", "this client does not know a game event", { event = gameEvent }) end
end

---@type table<string, function> handlers of game events, by event name
local onGameEvent = {}

function onGameEvent.ADDON_LOADED(loadedAddonName)
    if loadedAddonName ~= addonName then return end
    -- status "newer": Init hands back the ORIGINAL table, so assigning it keeps the newer data on disk untouched while this
    -- session runs on a throwaway database (docs/protocol.md "Stored data")
    local savedVariables, status = addon.Store.Init(_G[addon.SAVED_VARIABLES_NAME])
    _G[addon.SAVED_VARIABLES_NAME] = savedVariables
    addon.dbStatus = status
    addon.Locale.SetInterfaceLanguage(addon.db.ui.locale)   -- /ts locale <code> override for testing translations; nil = game client language
    addon.orders = addon.Orders.New(addon.Utility.Now, addon.db.orders)
    addon.Communication.Init()
    addon.Log.Information("events.load", "addon loaded", { version = addon.VERSION, build = addon.BUILD, store = status })
end

function onGameEvent.PLAYER_LOGIN()
    addon.Store.db.me = addon.Api.GetPlayerInformation().name
    addon.Store.CanonicalizeStoredNames()     -- names stored by older builds (or under another realm spelling) get their canonical key
    addon.Communication.canonicalNameVersion = addon.Utility.realmAliasVersion
    -- first login with another version than the data was saved with: drop what other members sent (Store.ResetPeerData)
    local baseVersion = (addon.BASE_VERSION:gsub("%-dev$", ""))
    if not addon.db.readonly and addon.db.version ~= baseVersion then
        local removed = addon.Store.ResetPeerData(addon.Store.db.me)
        if (removed.chars + removed.offers + removed.catalog) > 0 then
            addon.Log.Information("events.versionReset", "a new version dropped guild data; it is fetched again",
                { fromVersion = addon.db.version, toVersion = baseVersion, chars = removed.chars, offers = removed.offers,
                  catalog = removed.catalog })
            C_Timer.After(5, function()
                addon.Print((addon.Text["version %s: guild data is fetched again (your own recipes and orders are kept)"]):format(baseVersion))
            end)
        end
        addon.db.version = baseVersion
        addon.Locale.version = addon.Locale.version + 1   -- invalidates the name caches
    end
    addon.Communication.ready = true   -- the current character is known now; Communication.Start refuses to run before this
    addon.Communication.Start()
    if addon.dbStatus == "newer" then
        C_Timer.After(5, function()   -- after the chat frame is up
            addon.Print(addon.Text["Saved data was written by a newer TalentShare and is left untouched. Nothing is saved this session. Please update the addon."])
        end)
    end
    C_Timer.After(3, function()
        -- the realm part comes from GetNormalizedRealmName, which can be empty very early at login: build the name again
        local myName = addon.Api.GetPlayerInformation().name
        if myName and myName ~= addon.Store.db.me then
            addon.Trace.System("warn", "identity changed after login", tostring(addon.Store.db.me) .. " -> " .. myName)
            addon.Log.Warning("events.login", "my name changed after login (the realm was not known yet)",
                { before = addon.Store.db.me, after = myName })
            addon.Store.db.me = myName
            addon.Communication.canonicalNameVersion = nil
            addon.Communication.CanonicalizeStoredNames()
        end
        local changed = addon.Scanner.Refresh(addon.Utility.Now())
        addon.Communication.Start()
        scheduleItemScan(0.5)
        addon.Communication.RequestHello(true, true)  -- isLogin = true: online peers answer with their own HELLO
        if changed then Events.Fire("DATA_CHANGED", "chars") end
    end)
end

function onGameEvent.CHAT_MSG_ADDON(prefix, text, channel, sender)
    addon.Communication.OnAddonMessage(prefix, text, channel, sender)
end

function onGameEvent.GUILD_ROSTER_UPDATE()
    addon.Communication.Start()
    if addon.Communication.active then addon.Communication.PruneRoster() end
end

function onGameEvent.PLAYER_GUILD_UPDATE() addon.Communication.Start() end
function onGameEvent.PLAYER_LEVEL_UP() scheduleProfessionScan(2) end
function onGameEvent.TRADE_SKILL_SHOW()
    -- a profession window really opened (after a click on a profession button)
    addon.Log.Debug("events.tradeSkill", "a profession window opened")
    addon.Api.open.tradeskill = true
    scheduleProfessionScan(1.5)
    Events.Fire("TRADESKILL", true)   -- Orders tab: select a pending recipe, switch the Craft button (feature 009)
end
function onGameEvent.TRADE_SKILL_CLOSE()
    addon.Api.open.tradeskill = false
    Events.Fire("TRADESKILL", false)
end

-- The game's red error text (e.g. "no target", "action blocked") for 6 s after a click on a profession button, so a
-- button that opens nothing can be explained from the log.
function onGameEvent.UI_ERROR_MESSAGE(...)
    if not addon.UI.RecentBarClick() then return end
    local errorText
    for argumentIndex = 1, select("#", ...) do
        local argument = select(argumentIndex, ...)
        if type(argument) == "string" then errorText = argument end
    end
    addon.Log.Warning("events.uiError", "the game showed an error right after a profession button click", { text = errorText })
end
function onGameEvent.TRADE_SKILL_LIST_UPDATE() scheduleProfessionScan(1.0) end
function onGameEvent.TRADE_SKILL_DATA_SOURCE_CHANGED() scheduleProfessionScan(1.0) end
function onGameEvent.SKILL_LINES_CHANGED() scheduleProfessionScan(2.0) end
function onGameEvent.NEW_RECIPE_LEARNED() scheduleProfessionScan(1.5) end   -- keeps the cache current without reopening the window
function onGameEvent.GET_ITEM_INFO_RECEIVED() Events.Fire("ITEM_INFO") end

-- recipe item locations (events that do not exist on this client are skipped by registerGameEvent)
function onGameEvent.BAG_UPDATE_DELAYED() scheduleItemScan(1.5) end
---@param location "bank"|"mail"|"gbank"|"auction"
---@param isOpen boolean
---@return function
local function windowOpenedOrClosed(location, isOpen)
    return function()
        addon.Api.open[location] = isOpen
        addon.Log.Debug("events.window", isOpen and "a storage window opened" or "a storage window closed", { location = location })
        if isOpen then scheduleItemScan(1.0) end
    end
end
onGameEvent.BANKFRAME_OPENED, onGameEvent.BANKFRAME_CLOSED = windowOpenedOrClosed("bank", true), windowOpenedOrClosed("bank", false)
onGameEvent.MAIL_SHOW, onGameEvent.MAIL_CLOSED = windowOpenedOrClosed("mail", true), windowOpenedOrClosed("mail", false)
onGameEvent.GUILDBANKFRAME_OPENED, onGameEvent.GUILDBANKFRAME_CLOSED = windowOpenedOrClosed("gbank", true), windowOpenedOrClosed("gbank", false)
onGameEvent.AUCTION_HOUSE_SHOW, onGameEvent.AUCTION_HOUSE_CLOSED = windowOpenedOrClosed("auction", true), windowOpenedOrClosed("auction", false)
function onGameEvent.PLAYERBANKSLOTS_CHANGED() scheduleItemScan(1.5) end
function onGameEvent.PLAYERBANKBAGSLOTS_CHANGED() scheduleItemScan(1.5) end
function onGameEvent.PLAYERREAGENTBANKSLOTS_CHANGED() scheduleItemScan(1.5) end
function onGameEvent.MAIL_INBOX_UPDATE() scheduleItemScan(1.5) end
function onGameEvent.GUILDBANKBAGSLOTS_CHANGED() scheduleItemScan(1.5) end
function onGameEvent.AUCTION_OWNED_LIST_UPDATE() scheduleItemScan(1.5) end
function onGameEvent.OWNED_AUCTIONS_UPDATED() scheduleItemScan(1.5) end

-- /ts offers [scan]: what the item scan can see on this client and what my offers record holds (also the in-game probe)
addon.SlashCommands.offers = function(arguments)
    local Api = addon.Api
    if (arguments or ""):match("^%s*scan") then
        local ok, scans = addon.Log.Protected("events.offersCommand", "the recipe item scan failed", Api.ScanItems)
        if not ok then addon.Print("scan failed: " .. tostring(scans)) return end
        local changed = addon.Offers.Update(addon.Utility.Me(), scans, addon.Utility.Now())
        if changed then Events.Fire("OFFERS_CHANGED") end
        Events.Fire("DATA_CHANGED", "offers-local")
        addon.Print("scan: " .. (changed and "updated" or "unchanged"))
    end
    local function yesOrNo(value) return value and "yes" or "NO" end
    addon.Print(("APIs: C_Container %s, legacy container %s, item class %s, mail %s, guild bank %s, auction (modern/classic) %s/%s"):format(
        yesOrNo(C_Container and C_Container.GetContainerItemInfo), yesOrNo(GetContainerItemInfo),
        yesOrNo((C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant), yesOrNo(GetInboxItem and GetInboxNumItems),
        yesOrNo(GetGuildBankItemLink), yesOrNo(C_AuctionHouse and C_AuctionHouse.GetNumOwnedAuctions), yesOrNo(GetNumAuctionItems)))
    local openWindows = Api.open
    addon.Print(("windows open: bank %s, mail %s, guild bank %s, auction %s"):format(tostring(openWindows.bank),
        tostring(openWindows.mail), tostring(openWindows.gbank), tostring(openWindows.auction)))
    local statistics = Api.scanStatistics
    addon.Print(("last scan: %d items seen, %d recipes (%d bound, not offered), %d with unknown class"):format(statistics.items,
        statistics.recipes, statistics.bound, statistics.unknownClass))
    local myOffers = addon.Offers.Get(addon.Store.db.me or "")
    if not myOffers then addon.Print("no offers record yet (no tradeable recipe item found)") return end
    local itemTextsByLocation = {}
    for itemID, countByLocation in pairs(myOffers.items) do
        for location, itemCount in pairs(countByLocation) do
            itemTextsByLocation[location] = itemTextsByLocation[location] or {}
            table.insert(itemTextsByLocation[location], ("%s x%d"):format(Api.ItemName(itemID) or ("item:" .. itemID), itemCount))
        end
    end
    for _, location in ipairs(addon.Offers.LOCATION_ORDER) do
        if itemTextsByLocation[location] then addon.Print(("%s: %s"):format(location, table.concat(itemTextsByLocation[location], ", "))) end
    end
    local activeDibs = 0
    for _, dib in pairs(myOffers.dibs) do if dib.on then activeDibs = activeDibs + 1 end end
    addon.Print(("record rev %s, %d active dibs; %d offers known from the guild"):format(tostring(myOffers.rev), activeDibs,
        select(2, addon.Offers.Counts())))
end

for gameEvent in pairs(onGameEvent) do registerGameEvent(gameEvent) end
eventFrame:SetScript("OnEvent", function(_, gameEvent, ...)
    local handler = onGameEvent[gameEvent]
    if handler then
        addon.Log.Protected("events.game", "a game event handler failed (" .. tostring(gameEvent) .. ")", handler, ...)
    end
end)

local addonName, addon = ...

-- Internal pub/sub + WoW event wiring. Scans are debounced; the guild gets a HELLO when my data changes.
-- Internal events: DATA_CHANGED(kind), LOCAL_CHANGED, OFFERS_CHANGED, ACCESS_CHANGED, REPUTATION_CHANGED, COOLDOWNS_CHANGED, FEEDBACK_CHANGED, WINDOW_OPENED, TRADESKILL(isOpen), ITEM_INFO, SPELL_INFO.
-- Every handler runs protected: an error in one handler is logged (Log.Exception, with stack) and the others still run.
---@class EventsModule
local Events = {}
addon.Events = Events

-- Events.lua loads after every module it depends on. If one is missing, the TOC in use is out of date: typically the
-- generated ProfessionShare-Dev.toc after a new file was added to ProfessionShare.toc (tools/deploy.ps1 regenerates it). Without
-- this the player only sees a chain of "attempt to index a nil value" errors from the files that needed the module.
do
    local missingModules = {}
    for _, moduleName in ipairs({ "Utility", "Log", "Locale", "Store", "Names", "Api", "Scanner", "Codec", "Guard", "Orders",
        "Offers", "Access", "FactionHints", "Reputation", "CraftCooldowns", "RecipeCheck", "RecipeDrops", "Sync", "Model", "Communication", "Trace", "Diagnostics" }) do
        if not addon[moduleName] then missingModules[#missingModules + 1] = moduleName end
    end
    if #missingModules > 0 then
        addon.Print("not loaded: " .. table.concat(missingModules, ", ") .. ". The TOC is out of date. Dev build: run tools/deploy.ps1 (it regenerates ProfessionShare-Dev.toc), then restart the game (/reload does not re-read the TOC).")
    end
end

-- the bus itself is a LibGuildSync-1.0 Events instance (LibGuildSync/Events.lua): On(name, handler), Fire(name, ...)
do
    local bus = LibStub("LibGuildSync-1.0").Events.New(addon.Log)
    Events.On, Events.Fire = bus.On, bus.Fire
end

-- /ps clean: deletes everything cached locally (guild characters, recipes, orders, offers, learned names, item texts,
-- the log and the trace).
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
    addon.Log.Information("events.clean", "local data was deleted by /ps clean confirm",
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

-- Recipe items: bags are read at any time, bank/mail/guild bank/auctions only while their window is open
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
        -- keys and attunements ride on the same debounced scan (the same bag events); a change is rare
        local accessScanned, accessScan = addon.Log.Protected("events.accessScan", "the key and attunement scan failed",
            addon.Api.ScanAccess)
        if accessScanned and addon.Access.Update(myName, accessScan, addon.Utility.Now()) then
            addon.Log.Information("events.accessScan", "my keys or attunements changed", { keys = addon.Api.accessStatistics.keys })
            Events.Fire("ACCESS_CHANGED")
            Events.Fire("DATA_CHANGED", "access-local")
        end
    end)
end
Events.ScanItems = scheduleItemScan

-- Faction standings: read after UPDATE_FACTION (it fires for every reputation gain, so the scan is debounced) and at
-- login. A progress-only change that Reputation.Update holds back is read again when it may be shared.
local reputationScanPending, reputationRetryPending = false, false
---@param delaySeconds? number
local function scheduleReputationScan(delaySeconds)
    if reputationScanPending then return end
    reputationScanPending = true
    C_Timer.After(delaySeconds or 5, function()
        reputationScanPending = false
        local myName = addon.Utility.Me()
        if not myName then return end
        local ok, scan = addon.Log.Protected("events.reputationScan", "the reputation scan failed", addon.Api.ScanReputation)
        if not ok or not scan then return end
        local changed, retryAfter = addon.Reputation.Update(myName, scan, addon.Utility.Now())
        if changed then
            addon.Log.Debug("events.reputationScan", "my faction standings changed", { met = addon.Api.reputationStatistics.met })
            Events.Fire("REPUTATION_CHANGED")
            Events.Fire("DATA_CHANGED", "rep-local")
        elseif retryAfter and not reputationRetryPending then
            reputationRetryPending = true
            C_Timer.After(retryAfter + 1, function()
                reputationRetryPending = false
                scheduleReputationScan(0.1)
            end)
        end
    end)
end
Events.ScanReputation = scheduleReputationScan

-- Craft cooldowns: read from the game whenever it may have changed (login, cooldown updates, the profession window, a cast
-- of a timegated craft). A reading the game does not answer keeps the stored value (CraftCooldowns.Update).
-- castGroupKey: a group whose spell was just cast; when the game reports no cooldown for it, the fallback is used.
local cooldownReadPending, pendingCastGroups = false, {}
---@param delaySeconds? number
---@param castGroupKey? string
local function scheduleCooldownRead(delaySeconds, castGroupKey)
    if castGroupKey then pendingCastGroups[castGroupKey] = true end
    if cooldownReadPending then return end
    cooldownReadPending = true
    C_Timer.After(delaySeconds or 2, function()
        cooldownReadPending = false
        local castGroups = pendingCastGroups
        pendingCastGroups = {}
        local myName = addon.Utility.Me()
        if not myName then return end
        local ok, known, readings = addon.Log.Protected("events.cooldownRead", "the craft cooldown read failed",
            addon.Api.ReadCraftCooldowns)
        if not ok then return end
        for groupKey in pairs(castGroups) do
            local group = addon.CraftCooldowns.Group(groupKey)
            local reading = readings[groupKey]
            if group and not (reading and reading.remaining > 0) then
                known[groupKey] = true
                readings[groupKey] = { remaining = group.fallback, source = "cast" }
                addon.Log.Information("events.cooldownRead", "a timegated craft was cast but the game reports no cooldown; the fallback is used",
                    { group = groupKey, seconds = group.fallback })
            end
        end
        if addon.CraftCooldowns.Update(myName, known, readings, addon.Utility.Now()) then
            addon.Log.Debug("events.cooldownRead", "my craft cooldowns changed")
            Events.Fire("COOLDOWNS_CHANGED")
            Events.Fire("DATA_CHANGED", "cds-local")
        end
    end)
end
Events.ReadCooldowns = scheduleCooldownRead

-- My own changes are announced coalesced (at most one HELLO per Channel.HELLO_INTERVAL_SECONDS): while crafting, every
-- skill-up changes my record, and each announcement makes every online member pull the whole record again.
Events.On("LOCAL_CHANGED", function() addon.Communication.RequestHelloSoon() end)
Events.On("OFFERS_CHANGED", function() addon.Communication.RequestHelloSoon() end)
Events.On("ACCESS_CHANGED", function() addon.Communication.RequestHelloSoon() end)
Events.On("REPUTATION_CHANGED", function() addon.Communication.RequestHelloSoon() end)
Events.On("COOLDOWNS_CHANGED", function() addon.Communication.RequestHelloSoon() end)
Events.On("FEEDBACK_CHANGED", function() addon.Communication.RequestHelloSoon() end)
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
    addon.Locale.SetInterfaceLanguage(addon.db.ui.locale)   -- /ps locale <code> override for testing translations; nil = game client language
    addon.orders = addon.Orders.New(addon.Utility.Now, addon.db.orders)
    if addon.IS_DEVELOPMENT_BUILD and addon.DevProbe then addon.DevProbe.RestoreFakeMembers() end   -- fake members stay through the prune
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
            addon.Print(addon.Text["Saved data was written by a newer ProfessionShare and is left untouched. Nothing is saved this session. Please update the addon."])
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
        scheduleReputationScan(1.0)
        scheduleCooldownRead(2.0)
        -- if no cooldown update came by now, "ready" readings are believed anyway (nothing was cooling)
        C_Timer.After(20, function()
            addon.Api.cooldownState.trusted = true
            scheduleCooldownRead(0.1)
        end)
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
-- My last successful cast; a profession window that opens right after it was opened by that spell. The pair is noted in
-- db.windowSpells and sent in the HELLO (ProfessionSpells), so the developer learns the window spells of every
-- profession without asking anyone.
local WINDOW_SPELL_SECONDS = 2   -- a window opening later than this after the cast was not opened by it
local lastPlayerCast = nil

-- Reads which profession window is open (after the window has loaded) and notes the spell that opened it.
---@param spellID integer
local function noteWindowSpell(spellID)
    C_Timer.After(1.5, function()
        local openProfession = addon.Api.GetOpenProfession()
        if not (openProfession and openProfession.id and addon.db) then return end
        if addon.ProfessionSpells.Note(addon.db.windowSpells, openProfession.id, spellID) then
            addon.Log.Information("events.windowSpell", "a spell that opens a profession window was learned",
                { skillLine = openProfession.id, spellID = spellID, profession = openProfession.name })
            addon.Communication.RequestHelloSoon()
        end
    end)
end

function onGameEvent.TRADE_SKILL_SHOW()
    -- a profession window really opened (after a click on a profession button)
    addon.Log.Debug("events.tradeSkill", "a profession window opened")
    if lastPlayerCast and GetTime and GetTime() - lastPlayerCast.at <= WINDOW_SPELL_SECONDS then
        addon.Log.Protected("events.windowSpell", "noting the window spell failed", noteWindowSpell, lastPlayerCast.spellID)
    end
    lastPlayerCast = nil
    addon.Api.open.tradeskill = true
    scheduleProfessionScan(1.5)
    scheduleCooldownRead(1.5)
    Events.Fire("TRADESKILL", true)   -- Orders tab: select a pending recipe, switch the Craft button
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
-- a spell the client loaded on request (enchant effect texts)
function onGameEvent.SPELL_DATA_LOAD_RESULT(_, success) if success ~= false then Events.Fire("SPELL_INFO") end end
-- the game blocked one of our calls (protected action in combat, taint): recorded so /ps export shows what and where
local function logBlockedAction(kind)
    return function(blockedAddonName, blockedFunction)
        if blockedAddonName ~= addonName then return end
        addon.Log.Warning("events.blocked", "the game blocked an action of this addon",
            { kind = kind, call = tostring(blockedFunction), inCombat = addon.Api.InCombat() })
    end
end
onGameEvent.ADDON_ACTION_BLOCKED = logBlockedAction("blocked")
onGameEvent.ADDON_ACTION_FORBIDDEN = logBlockedAction("forbidden")

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
function onGameEvent.UPDATE_FACTION() scheduleReputationScan(5) end
-- the first cooldown update after login means the client's cooldown data has arrived; it also fires when one starts
function onGameEvent.SPELL_UPDATE_COOLDOWN()
    addon.Api.cooldownState.trusted = true
    scheduleCooldownRead(2)
end
function onGameEvent.BAG_UPDATE_COOLDOWN() scheduleCooldownRead(2) end
function onGameEvent.UNIT_SPELLCAST_SUCCEEDED(unit, _, spellID)
    if unit ~= "player" then return end
    if type(spellID) == "number" and GetTime then lastPlayerCast = { spellID = spellID, at = GetTime() } end
    local group = addon.CraftCooldowns.GroupOfCast(spellID)
    if group then
        addon.Log.Information("events.cooldownCast", "a timegated craft was cast", { group = group.key, spellID = spellID })
        scheduleCooldownRead(1.5, group.key)
    end
end
-- an attunement quest was handed in (the completed-quest flag is set a moment later)
function onGameEvent.QUEST_TURNED_IN() scheduleItemScan(3) end

-- /ps spellids: the spells that opened my profession windows, and on the developer's client what guild members reported,
-- compared with the static table (ProfessionSpells.WINDOW). Plain English: a developer report, not localized.
addon.SlashCommands.spellids = function()
    local database = addon.db or {}
    addon.Print("window spells I noted: " .. tostring(addon.ProfessionSpells.Encode(database.windowSpells) or "none yet (open a profession window)"))
    local rows = addon.ProfessionSpells.ReportRows(database.windowSpellReports)
    if #rows == 0 then addon.Print("no reports from guild members yet") return end
    local verdicts = { same = "in the table", other = "|cffff5555the table has another id|r", new = "|cff33ff99not in the table|r" }
    for _, row in ipairs(rows) do
        addon.Print(("  %s (skill line %d): spell %d, %d members, %s"):format(addon.Names.Profession(row.skillLine),
            row.skillLine, row.spellID, row.reporters, verdicts[row.static]))
    end
end

-- /ps offers [scan]: what the item scan can see on this client and what my offers record holds (also the in-game probe)
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

-- /ps access [scan]: which keys and attunements the scan sees on this client and what my access record holds (also the
-- in-game probe for the key ring, the quest API and the item and quest ids)
addon.SlashCommands.access = function(arguments)
    local Api, Access = addon.Api, addon.Access
    local myName = addon.Utility.Me()
    local ok, accessScan = addon.Log.Protected("events.accessCommand", "the key and attunement scan failed", Api.ScanAccess)
    if not ok then addon.Print("scan failed: " .. tostring(accessScan)) return end
    if (arguments or ""):match("^%s*scan") and myName then
        local changed = Access.Update(myName, accessScan, addon.Utility.Now())
        if changed then Events.Fire("ACCESS_CHANGED") end
        Events.Fire("DATA_CHANGED", "access-local")
        addon.Print("scan: " .. (changed and "updated" or "unchanged"))
    end
    local statistics = Api.accessStatistics
    addon.Print(("APIs: key ring %s (KEYRING_CONTAINER %s), quest API %s; last scan: %d keys, %d items with unknown class"):format(
        statistics.keyring and "yes" or "NO", tostring(KEYRING_CONTAINER), statistics.questApi and "yes" or "NO", statistics.keys,
        statistics.unknownClass))
    for location, heldKeys in pairs(accessScan.keys) do
        local keyTexts = {}
        for itemID in pairs(heldKeys) do keyTexts[#keyTexts + 1] = ("%s (%d)"):format(Api.ItemName(itemID) or "?", itemID) end
        table.sort(keyTexts)
        addon.Print(("%s: %s"):format(location, #keyTexts > 0 and table.concat(keyTexts, ", ") or "-"))
    end
    for _, attunement in ipairs(Access.ATTUNEMENTS) do
        local questTexts = {}
        for _, questID in ipairs(attunement.quests) do questTexts[#questTexts + 1] = questID .. "=" .. tostring(Api.QuestDone(questID)) end
        local itemText = attunement.item and (" item " .. attunement.item .. "=" .. tostring(Api.ItemCount(attunement.item))) or ""
        addon.Print(("%s: %s (quests %s%s)"):format(Access.InstanceName(attunement.instance) or attunement.key,
            tostring(accessScan.att[attunement.key]), table.concat(questTexts, " "), itemText))
    end
    local myRecord = myName and Access.Get(myName)
    local recordCount, keyCount = Access.Counts()
    addon.Print(("record rev %s; %d access records (%d keys) known from the guild"):format(
        tostring(myRecord and myRecord.rev), recordCount, keyCount))
end

-- /ps rep [scan]: what the reputation scan sees on this client (also the in-game probe for the API and the faction ids)
addon.SlashCommands.rep = function(arguments)
    local Api, Reputation = addon.Api, addon.Reputation
    local myName = addon.Utility.Me()
    local ok, scan = addon.Log.Protected("events.reputationCommand", "the reputation scan failed", Api.ScanReputation)
    if not ok then addon.Print("scan failed: " .. tostring(scan)) return end
    if (arguments or ""):match("^%s*scan") and myName and scan then
        local changed = Reputation.Update(myName, scan, addon.Utility.Now(), true)
        if changed then Events.Fire("REPUTATION_CHANGED") end
        Events.Fire("DATA_CHANGED", "rep-local")
        addon.Print("scan: " .. (changed and "updated" or "unchanged"))
    end
    local statistics = Api.reputationStatistics
    addon.Print(("APIs: GetFactionInfoByID %s, C_Reputation %s, faction API answers %s; %d factions in the shown list, %d listed factions met"):format(
        GetFactionInfoByID and "yes" or "NO", (C_Reputation and C_Reputation.GetFactionDataByID) and "yes" or "NO",
        statistics.api and "yes" or "NO", statistics.listed, statistics.met))
    for _, faction in ipairs(addon.FactionHints.FACTIONS) do
        local standing = scan and scan[faction.id]
        local clientName = Api.FactionName(faction.id)
        local standingText = standing and ("%s %d/%d"):format(Api.StandingLabel(standing.s) or tostring(standing.s), standing.v, standing.m) or "-"
        addon.Print(("%d %s (%s): %s"):format(faction.id, faction.name, clientName or "?", standingText))
    end
    local myRecord = myName and Reputation.Get(myName)
    local recordCount, standingCount = Reputation.Counts()
    addon.Print(("record rev %s; %d reputation records (%d standings) known from the guild"):format(
        tostring(myRecord and myRecord.rev), recordCount, standingCount))
end

-- /ps cd [scan]: what the craft cooldown read sees on this client: the raw values per group, what was taken, my stored
-- record; with a profession window open also every recipe in it that has a cooldown (the in-game probe for the recipe
-- ids, the APIs and the durations).
addon.SlashCommands.cd = function(arguments)
    local Api, CraftCooldowns = addon.Api, addon.CraftCooldowns
    local myName = addon.Utility.Me()
    local now = addon.Utility.Now()
    local ok, known, readings, probes = addon.Log.Protected("events.cooldownCommand", "the craft cooldown read failed",
        Api.ReadCraftCooldowns)
    if not ok then addon.Print("read failed: " .. tostring(known)) return end
    if (arguments or ""):match("^%s*scan") and myName then
        local changed = CraftCooldowns.Update(myName, known, readings, now)
        if changed then Events.Fire("COOLDOWNS_CHANGED") end
        Events.Fire("DATA_CHANGED", "cds-local")
        addon.Print("scan: " .. (changed and "updated" or "unchanged"))
    end
    local function yesOrNo(value) return value and "yes" or "NO" end
    addon.Print(("APIs: C_Spell.GetSpellCooldown %s, GetSpellCooldown %s, item cooldown %s, C_TradeSkillUI.GetRecipeCooldown %s, IsPlayerSpell %s, overlay glow %s"):format(
        yesOrNo(C_Spell and C_Spell.GetSpellCooldown), yesOrNo(GetSpellCooldown),
        yesOrNo((C_Container and C_Container.GetItemCooldown) or GetItemCooldown),
        yesOrNo(C_TradeSkillUI and C_TradeSkillUI.GetRecipeCooldown), yesOrNo(IsPlayerSpell), yesOrNo(ActionButton_ShowOverlayGlow)))
    addon.Print(("clock: server %s, local %s (difference %ss); cooldown data trusted %s; profession window open %s"):format(
        tostring(now), tostring(time and time()), tostring(time and (time() - now)), yesOrNo(Api.cooldownState.trusted),
        yesOrNo(Api.open.tradeskill)))
    local myRecord = myName and CraftCooldowns.Get(myName)
    local function seconds(value) return value and ("%ds"):format(math.floor(value + 0.5)) or "-" end
    for _, group in ipairs(CraftCooldowns.GROUPS) do
        local probe = probes[group.key]
        local stored = myRecord and myRecord.c[group.key]
        local storedText = stored == nil and "-" or (stored == 0 and "ready")
            or (stored <= now and "ready (passed)") or (addon.Model.FormatCooldownLong(stored - now))
        addon.Print(("%s: known %s (recipes %s, spell %s%s) | spell %s, window %s, item %s -> taken %s | stored %s%s%s"):format(
            group.key, yesOrNo(probe.known), yesOrNo(probe.byRecipes), yesOrNo(probe.bySpell),
            group.item and (", item held " .. tostring(probe.itemCount)) or "",
            seconds(probe.spell), seconds(probe.trade), seconds(probe.item),
            probe.reading and (seconds(probe.reading.remaining) .. " from " .. probe.reading.source) or "nothing",
            storedText, myRecord and myRecord.e[group.key] and " (estimate)" or "",
            group.verified and "" or " [ids unverified]"))
    end
    for _, recipe in ipairs(Api.OpenWindowCooldownRecipes()) do
        local group = CraftCooldowns.GroupOfRecipe(recipe.recipeID)
        addon.Print(("  window recipe %d %s: cooldown %s%s -> %s"):format(recipe.recipeID, tostring(recipe.name),
            seconds(recipe.cooldown), recipe.dayCooldown and " (day cooldown)" or "", group and group.key or "NOT IN ANY GROUP"))
    end
    local recordCount, entryCount = CraftCooldowns.Counts()
    addon.Print(("record rev %s; %d cooldown records (%d entries) known from the guild"):format(
        tostring(myRecord and myRecord.rev), recordCount, entryCount))
end

for gameEvent in pairs(onGameEvent) do registerGameEvent(gameEvent) end
eventFrame:SetScript("OnEvent", function(_, gameEvent, ...)
    local handler = onGameEvent[gameEvent]
    if handler then
        addon.Log.Protected("events.game", "a game event handler failed (" .. tostring(gameEvent) .. ")", handler, ...)
    end
end)

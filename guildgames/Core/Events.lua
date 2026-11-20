local addonName, addon = ...

-- WoW event wiring. The internal bus (addon.Events: On/Fire, handlers run protected) is made in Core/Library.lua.
-- Internal events: DATA_CHANGED(kind), GAMES_CHANGED (a play of mine was stored), WINDOW_OPENED.
local Events = addon.Events

-- Events.lua loads after every module it depends on. If one is missing, the TOC in use is out of date (typically the
-- generated GuildGames-Dev.toc after a file was added): one plain message instead of a chain of nil-index errors.
do
    local missingModules = {}
    for _, moduleName in ipairs({ "Utility", "Log", "Trace", "Locale", "Codec", "Store", "Api", "Games", "CoinFlip", "Slots",
        "Survivor", "Wallet", "AzeCaught", "Model", "Sync", "Communication", "Catcher" }) do
        if not addon[moduleName] then missingModules[#missingModules + 1] = moduleName end
    end
    if #missingModules > 0 then
        addon.Print("not loaded: " .. table.concat(missingModules, ", ") .. ". The TOC is out of date. Dev build: run tools/deploy.ps1 (it regenerates GuildGames-Dev.toc), then restart the game (/reload does not re-read the TOC).")
    end
end

-- a play is announced coalesced (at most one HELLO per 30 s), so play spam cannot flood the guild channel
Events.On("GAMES_CHANGED", function() addon.Communication.RequestHelloSoon() end)
Events.On("WINDOW_OPENED", function() addon.Communication.RequestHello(false, false) end)

-- /gg clean: deletes every game record (yours too), the log and the trace. Two steps because it cannot be undone.
addon.SlashCommands.clean = function(arguments)
    if not addon.db then return end
    if (arguments or ""):match("^%s*(%S*)") ~= "confirm" then
        addon.Print(("clean would delete %d game records. Type %s clean confirm to do it."):format(
            addon.Utility.Count(addon.db.games), addon.SLASH_COMMANDS[1]))
        return
    end
    local removed = addon.Store.Clean()
    addon.Log.Information("events.clean", "local data was deleted by clean confirm", { games = removed })
    Events.Fire("DATA_CHANGED", "games")
    addon.Communication.RequestHello(true, true)   -- online members introduce themselves; their records are pulled again
    addon.Print(("cleaned: removed %d game records."):format(removed))
end

-- /gg locale [code|auto]: UI language override for testing translations
addon.SlashCommands.locale = function(arguments)
    local languageCode = (arguments or ""):match("^%s*(%S*)") or ""
    if languageCode == "" then
        addon.Print(("UI language %s, game client %s"):format(addon.Locale.code, addon.Locale.clientCode))
        return
    end
    if not addon.db then return end
    addon.db.ui.locale = languageCode ~= "auto" and languageCode or nil
    addon.Print(("UI language set to %s: /reload to apply"):format(languageCode))
end

local eventFrame = CreateFrame("Frame")
---@type table<string, function> handlers of game events, by event name
local onGameEvent = {}

function onGameEvent.ADDON_LOADED(loadedAddonName)
    if loadedAddonName ~= addonName then return end
    local savedVariables, status = addon.Store.Init(_G[addon.SAVED_VARIABLES_NAME])
    _G[addon.SAVED_VARIABLES_NAME] = savedVariables
    addon.dbStatus = status
    addon.Locale.SetInterfaceLanguage(addon.db.ui.locale)
    addon.Communication.Init()
    addon.Log.Information("events.load", "addon loaded", { version = addon.VERSION, build = addon.BUILD, store = status })
    -- blocks that happened while the files loaded (before the log could store anything)
    for _, entry in ipairs(addon.blockedEarly or {}) do addon.OnActionBlocked(entry) end
    addon.blockedEarly = {}
end

function onGameEvent.PLAYER_LOGIN()
    addon.Log.Protected("window.minimap", "building the minimap button failed", addon.UI.BuildMinimapButton)
    addon.Store.db.me = addon.Api.GetPlayerInformation().name
    addon.Store.CanonicalizeStoredNames()
    -- a survivor run left open by a /reload, logout or crash is lost (its stake was booked as pending at the start)
    if addon.Survivor.ResolvePending(addon.Utility.Now()) then
        addon.Log.Information("games.survivor", "an unfinished survivor run was booked as lost")
        addon.Events.Fire("GAMES_CHANGED")
    end
    addon.Log.Protected("caught.start", "starting AZEcaught failed", addon.Catcher.Start)
    addon.Communication.canonicalNameVersion = addon.Utility.realmAliasVersion
    addon.Communication.ready = true   -- the current character is known now; Start refuses to run before this
    addon.Communication.Start()
    if addon.dbStatus == "newer" then
        C_Timer.After(5, function()
            addon.Print(addon.Text["Saved data was written by a newer GuildGames and is left untouched. Nothing is saved this session. Please update the addon."])
        end)
    end
    C_Timer.After(3, function()
        -- the realm part can be empty very early at login: build the name again
        local myName = addon.Api.GetPlayerInformation().name
        if myName and myName ~= addon.Store.db.me then
            addon.Trace.System("warn", "identity changed after login", tostring(addon.Store.db.me) .. " -> " .. myName)
            addon.Store.db.me = myName
            addon.Communication.canonicalNameVersion = nil
            addon.Communication.CanonicalizeStoredNames()
        end
        addon.Communication.Start()
        addon.Communication.RequestHello(true, true)   -- isLogin: online members answer with their own HELLO
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

-- The client blocked a function only Blizzard code may call ("reserved for the Blizzard UI" dialog) and blamed this
-- addon (the event is caught in Core/Init.lua, the first file). Logged with the function name, the combat state, the
-- stack and the last AZEcaught steps, so the cause can be found from /gg debug (or the SavedVariables file).
---@param details table { kind, function, combat, stack }
function addon.OnActionBlocked(details)
    if addon.AzeCaught then
        local recent = addon.AzeCaught.JournalLines(3)
        details.lastSteps = table.concat(recent, " || ")
    end
    if addon.AzeCaught then   -- the journal mirrors ERROR lines to the main log (/gg debug)
        addon.AzeCaught.Journal("ERROR", "blocked", "the client blocked a protected function and blamed this addon", details)
    else
        addon.Log.Error("events.blocked", "the client blocked a protected function and blamed this addon", details)
    end
end


for gameEvent in pairs(onGameEvent) do
    local ok = pcall(eventFrame.RegisterEvent, eventFrame, gameEvent)
    if not ok then addon.Log.Debug("events.register", "this client does not know a game event", { event = gameEvent }) end
end
eventFrame:SetScript("OnEvent", function(_, gameEvent, ...)
    local handler = onGameEvent[gameEvent]
    if handler then addon.Log.Protected("events.game", "a game event handler failed (" .. tostring(gameEvent) .. ")", handler, ...) end
end)

local addonName, addon = ...

-- Identity. The ONLY place that knows whether this is the live addon ("GuildGames") or the side-by-side development copy
-- ("GuildGames-Dev"); everything else reads these fields so both can run in one client without sharing state.
-- BUILD FLAG and the names derived from it come from LibGuildSync-1.0 Addon.Setup (LibGuildSync/Addon.lua), shared with
-- TalentShare: "dev" when the generated GuildGames-Dev.toc says "## X-Build: dev" (tools/deploy.ps1) OR the folder name
-- contains "dev"; either signal is enough, so a mismatch fails toward isolation. It sets addon.BUILD,
-- IS_DEVELOPMENT_BUILD, BASE_VERSION, VERSION, TITLE, PREFIX ("GGames"/"GGamesDev"), SAVED_VARIABLES_NAME, FRAME_PREFIX,
-- SLASH_COMMANDS (/gg /guildgames or /ggd /guildgamesdev), SlashCommands (handlers by word) and Print, warns when the TOC
-- saves another global than this build uses, and registers the slash commands.
-- The fallback version only matters for the offline tests.
LibStub("LibGuildSync-1.0").Addon.Setup(addon, addonName,
    { name = "GuildGames", prefix = "GGames", command = "gg", fallbackVersion = "0.2.0", color = "ffcc33" })

-- Wire protocol (docs/protocol.md): MAJOR must match exactly between peers, MINOR may differ (additive changes only).
---@type integer
addon.PROTOCOL_MAJOR = 1
---@type integer
addon.PROTOCOL_MINOR = 1   -- 1.1: the optional "caught" record section (feature 018)
---@type integer alias: the major is what the payload "v" field carries
addon.PROTOCOL = addon.PROTOCOL_MAJOR

-- Blocked actions ("reserved for the Blizzard UI" dialog). Registered in the FIRST file so a block while the other files
-- load is caught too. Until the saved data is loaded (and the log can store lines) entries wait in addon.blockedEarly;
-- Core/Game/Events.lua writes them to the log after ADDON_LOADED. The function name also goes to chat at once.
---@type table[]
addon.blockedEarly = {}
if CreateFrame then
    local blockedFrame = CreateFrame("Frame")
    for _, blockedEvent in ipairs({ "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED" }) do
        pcall(blockedFrame.RegisterEvent, blockedFrame, blockedEvent)
    end
    blockedFrame:SetScript("OnEvent", function(_, blockedEvent, blamedAddon, functionName)
        if blamedAddon ~= addonName then return end
        local entry = { kind = blockedEvent == "ADDON_ACTION_FORBIDDEN" and "forbidden" or "blocked",
            ["function"] = tostring(functionName), combat = tostring(InCombatLockdown and InCombatLockdown() or false),
            stack = type(debugstack) == "function" and debugstack(2, 12, 0) or nil }
        addon.Print(("the game blocked %s (%s). Details: %s debug"):format(entry["function"], entry.kind, addon.SLASH_COMMANDS[1]))
        if addon.OnActionBlocked and addon.db then addon.OnActionBlocked(entry) else table.insert(addon.blockedEarly, entry) end
    end)
end

addon.SlashCommands.version = function()
    local library = LibStub("LibGuildSync-1.0")
    addon.Print("v" .. addon.VERSION .. " (protocol " .. addon.PROTOCOL_MAJOR .. "." .. addon.PROTOCOL_MINOR .. ", schema "
        .. tostring(addon.Store.SCHEMA) .. ", prefix " .. addon.PREFIX .. ", LibGuildSync minor " .. tostring(library.MINOR) .. ")")
end

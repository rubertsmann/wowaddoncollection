local addonName, addon = ...

-- Identity. The ONLY place that knows whether this is the live addon ("GuildGames") or the side-by-side development copy
-- ("GuildGames-Dev"); everything else reads these fields so both can run in one client without sharing state.

-- A field of this addon's TOC file ("## <field>: value"), nil when the client cannot tell or the field is empty.
---@param field string
---@return string|nil
local function tableOfContentsField(field)
    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if not getMetadata then return nil end
    local ok, value = pcall(getMetadata, addonName, field)
    return ok and type(value) == "string" and value ~= "" and value or nil
end

-- BUILD FLAG: "dev" when the generated GuildGames-Dev.toc says "## X-Build: dev" (tools/deploy.ps1) OR the folder name
-- contains "dev". Either signal makes it a development build, so a mismatch fails toward isolation: development traffic
-- and data never reach the live build. Prefix, SavedVariables, frames and slash commands are derived here and nowhere else.
local buildField = (tableOfContentsField("X-Build") or ""):lower():match("^%s*(.-)%s*$")
local folderSaysDevelopment = type(addonName) == "string" and addonName:lower():find("dev", 1, true) ~= nil
---@type boolean
local IS_DEVELOPMENT_BUILD = buildField == "dev" or folderSaysDevelopment

---@type "dev"|"live"
addon.BUILD = IS_DEVELOPMENT_BUILD and "dev" or "live"
---@type boolean
addon.IS_DEVELOPMENT_BUILD = IS_DEVELOPMENT_BUILD
-- ONE version source: the TOC "## Version" line. The literal fallback only matters for the offline tests.
---@type string
addon.BASE_VERSION = tableOfContentsField("Version") or "0.1.0"
---@type string
addon.VERSION = addon.BASE_VERSION
    .. ((IS_DEVELOPMENT_BUILD and not addon.BASE_VERSION:find("-dev", 1, true)) and "-dev" or "")
-- Wire protocol (docs/protocol.md): MAJOR must match exactly between peers, MINOR may differ (additive changes only).
---@type integer
addon.PROTOCOL_MAJOR = 1
---@type integer
addon.PROTOCOL_MINOR = 1   -- 1.1: the optional "caught" record section (feature 018)
---@type integer alias: the major is what the payload "v" field carries
addon.PROTOCOL = addon.PROTOCOL_MAJOR
---@type string
addon.TITLE = IS_DEVELOPMENT_BUILD and "GuildGames (dev)" or "GuildGames"
---@type string addon-message prefix, at most 16 bytes
addon.PREFIX = IS_DEVELOPMENT_BUILD and "GGamesDev" or "GGames"
---@type string SavedVariables global (must match the TOC)
addon.SAVED_VARIABLES_NAME = IS_DEVELOPMENT_BUILD and "GuildGamesDevDB" or "GuildGamesDB"
---@type string prefix for global frame names
addon.FRAME_PREFIX = IS_DEVELOPMENT_BUILD and "GuildGamesDev" or "GuildGames"
---@type string[]
addon.SLASH_COMMANDS = IS_DEVELOPMENT_BUILD and { "/ggd", "/guildgamesdev" } or { "/gg", "/guildgames" }
-- Handlers of "/gg <word> <arguments>", by word.
---@type table<string, fun(arguments: string|nil)>
addon.SlashCommands = {}

-- A line in the chat frame for the player (not a log line: diagnostics go through addon.Log).
---@param message any
function addon.Print(message)
    print("|cffffcc33" .. addon.TITLE .. "|r: " .. tostring(message))
end

-- The TOC declares which global the game saves; if it is not the one this build uses, data would silently never persist.
do
    local declaredSavedVariables = tableOfContentsField("SavedVariables")
    if declaredSavedVariables and declaredSavedVariables ~= addon.SAVED_VARIABLES_NAME then
        addon.Print(("the TOC saves %s but this %s build uses %s: nothing will be saved. Dev build: run tools/deploy.ps1 and restart the game."):format(
            declaredSavedVariables, addon.BUILD, addon.SAVED_VARIABLES_NAME))
    end
end

if SlashCmdList then
    local slashKey = IS_DEVELOPMENT_BUILD and "GUILDGAMESDEV" or "GUILDGAMES"
    for index, command in ipairs(addon.SLASH_COMMANDS) do _G["SLASH_" .. slashKey .. index] = command end
    SlashCmdList[slashKey] = function(input)
        local command, arguments = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
        command = (command or ""):lower()
        if command == "" then
            addon.UI.Toggle()
        elseif addon.SlashCommands[command] then
            addon.SlashCommands[command](arguments)
        else
            local commandWords = addon.Utility.SortedKeys(addon.SlashCommands)
            addon.Print(addon.SLASH_COMMANDS[1] .. " [" .. table.concat(commandWords, "|") .. "]")
        end
    end
end

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

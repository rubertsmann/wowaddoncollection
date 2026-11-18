local addonName, addon = ...

-- Identity. The ONLY place that knows whether this is the live addon ("TalentShare") or the side-by-side development
-- copy ("TalentShare-Dev"); everything else reads these fields so both can run in one client without sharing state.

-- A field of this addon's TOC file ("## <field>: value"), nil when the client cannot tell or the field is empty.
---@param field string
---@return string|nil
local function tableOfContentsField(field)
    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if not getMetadata then return nil end
    local ok, value = pcall(getMetadata, addonName, field)
    return ok and type(value) == "string" and value ~= "" and value or nil
end

-- BUILD FLAG: addon.BUILD is "dev" or "live", addon.IS_DEVELOPMENT_BUILD is its boolean form. Everything that must differ
-- between the two builds (comms prefix, SavedVariables, frames, slash commands) is derived from it below and nowhere else;
-- do not test the addon folder name or hard-code "TShare" elsewhere. Two signals, and EITHER one makes it a development
-- build, so a mismatch (renamed folder, stale TOC) fails toward isolation and never lets development traffic or data
-- reach the live build:
--   1. the generated TalentShare-Dev.toc carries "## X-Build: dev" (tools/deploy.ps1)
--   2. the addon folder name contains "dev"
local buildField = (tableOfContentsField("X-Build") or ""):lower():match("^%s*(.-)%s*$")
local folderSaysDevelopment = type(addonName) == "string" and addonName:lower():find("dev", 1, true) ~= nil
---@type boolean
local IS_DEVELOPMENT_BUILD = buildField == "dev" or folderSaysDevelopment

---@type "dev"|"live"
addon.BUILD = IS_DEVELOPMENT_BUILD and "dev" or "live"
---@type boolean
addon.IS_DEVELOPMENT_BUILD = IS_DEVELOPMENT_BUILD
-- ONE version source: the TOC "## Version" line (read from addon metadata). The literal fallback only matters for the
-- offline tests, which have no client; tests/test_hardening.lua checks it against the TOC.
---@type string
addon.BASE_VERSION = tableOfContentsField("Version") or "0.7.3"
---@type string the development TOC already says "-dev"; never append it twice
addon.VERSION = addon.BASE_VERSION
    .. ((IS_DEVELOPMENT_BUILD and not addon.BASE_VERSION:find("-dev", 1, true)) and "-dev" or "")
-- Wire protocol (docs/protocol.md): MAJOR must match exactly between peers, MINOR may differ (additive changes only).
-- Bump MAJOR for any breaking change to the chunk header, serializer, compression or message meaning.
---@type integer
addon.PROTOCOL_MAJOR = 2
---@type integer
addon.PROTOCOL_MINOR = 3
---@type integer alias: the major is what the payload "v" field carries
addon.PROTOCOL = addon.PROTOCOL_MAJOR
---@type string
addon.TITLE = IS_DEVELOPMENT_BUILD and "TalentShare (dev)" or "TalentShare"
---@type string addon-message prefix, at most 16 bytes
addon.PREFIX = IS_DEVELOPMENT_BUILD and "TShareDev" or "TShare"
---@type string SavedVariables global (must match the TOC)
addon.SAVED_VARIABLES_NAME = IS_DEVELOPMENT_BUILD and "TalentShareDevDB" or "TalentShareDB"
---@type string prefix for global frame names
addon.FRAME_PREFIX = IS_DEVELOPMENT_BUILD and "TalentShareDev" or "TalentShare"
---@type string[]
addon.SLASH_COMMANDS = IS_DEVELOPMENT_BUILD and { "/tsd", "/talentsharedev" } or { "/ts", "/talentshare" }
-- Handlers of "/ts <word> <arguments>", by word. The words are what players type and stay as they are.
---@type table<string, fun(arguments: string|nil)>
addon.SlashCommands = {}

-- A line in the chat frame for the player (not a log line: diagnostics go through addon.Log).
---@param message any
function addon.Print(message)
    print("|cff33ccff" .. addon.TITLE .. "|r: " .. tostring(message))
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
    local slashKey = IS_DEVELOPMENT_BUILD and "TALENTSHAREDEV" or "TALENTSHARE"
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

addon.SlashCommands.version = function()
    addon.Print("v" .. addon.VERSION .. " (protocol " .. addon.PROTOCOL_MAJOR .. "." .. addon.PROTOCOL_MINOR .. ", schema "
        .. tostring(addon.Store.SCHEMA) .. ", prefix " .. addon.PREFIX .. ")")
end

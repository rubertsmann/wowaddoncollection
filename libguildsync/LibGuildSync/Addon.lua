-- LibGuildSync: what every addon that embeds the library sets up the same way: its identity (live or development build,
-- version, prefix, SavedVariables, frame names, slash commands), the slash command dispatcher, and the diagnostic slash
-- commands (comm, hello, debug, trace). TalentShare and GuildGames used to carry a copy each.
-- Identity names follow one pattern from three words, so the live and the development build never share state:
--   name "TalentShare", prefix "TShare", command "ts"  ->
--   live: title "TalentShare", prefix "TShare", SavedVariables "TalentShareDB", frames "TalentShare", /ts /talentshare
--   dev:  title "TalentShare (dev)", prefix "TShareDev", "TalentShareDevDB", frames "TalentShareDev", /tsd /talentsharedev
local lib = LibStub("LibGuildSync-1.0")
local Addon = lib:Module("Addon", 2)
if not Addon then return end

-- A field of addon `addonName`'s TOC file ("## <field>: value"), nil when the client cannot tell or the field is empty.
---@param addonName string
---@param field string
---@return string|nil
function Addon.TableOfContentsField(addonName, field)
    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if not getMetadata then return nil end
    local ok, value = pcall(getMetadata, addonName, field)
    return ok and type(value) == "string" and value ~= "" and value or nil
end

-- BUILD FLAG: a development build when EITHER the TOC says "## X-Build: dev" (the generated <Name>-Dev.toc, see the
-- addon's tools/deploy.ps1) OR the addon folder name contains "dev". A mismatch (renamed folder, stale TOC) fails toward
-- isolation: development traffic and data never reach the live build.
---@param addonName string the addon folder name (first value of `...` in an addon file)
---@return boolean
function Addon.IsDevelopmentBuild(addonName)
    local buildField = (Addon.TableOfContentsField(addonName, "X-Build") or ""):lower():match("^%s*(.-)%s*$")
    local folderSaysDevelopment = type(addonName) == "string" and addonName:lower():find("dev", 1, true) ~= nil
    return buildField == "dev" or folderSaysDevelopment
end

---@class AddonIdentityOptions
---@field name string the live addon's name ("TalentShare"): title, SavedVariables and frame names, long slash command
---@field prefix string the live build's addon-message prefix ("TShare"), at most 13 bytes ("Dev" is appended)
---@field command string the live build's short slash command without "/" ("ts")
---@field fallbackVersion string version when the client cannot read the TOC (only the offline tests)
---@field color string chat colour of the title as "rrggbb"

-- Sets the identity fields on `addon` (BUILD, IS_DEVELOPMENT_BUILD, BASE_VERSION, VERSION, TITLE, PREFIX,
-- SAVED_VARIABLES_NAME, FRAME_PREFIX, SLASH_COMMANDS, SlashCommands, Print), warns when the TOC saves another global than
-- this build uses, and registers the slash commands: no word toggles addon.UI, a known word runs
-- addon.SlashCommands[word](arguments), anything else lists the words.
---@param addon table the addon's namespace (second value of `...`)
---@param addonName string the addon folder name
---@param options AddonIdentityOptions
function Addon.Setup(addon, addonName, options)
    local isDevelopment = Addon.IsDevelopmentBuild(addonName)
    local name, lowerName = options.name, options.name:lower()
    ---@type "dev"|"live"
    addon.BUILD = isDevelopment and "dev" or "live"
    addon.IS_DEVELOPMENT_BUILD = isDevelopment
    -- ONE version source: the TOC "## Version" line; the development TOC already says "-dev", never append it twice
    addon.BASE_VERSION = Addon.TableOfContentsField(addonName, "Version") or options.fallbackVersion
    addon.VERSION = addon.BASE_VERSION
        .. ((isDevelopment and not addon.BASE_VERSION:find("-dev", 1, true)) and "-dev" or "")
    addon.TITLE = isDevelopment and (name .. " (dev)") or name
    addon.PREFIX = isDevelopment and (options.prefix .. "Dev") or options.prefix
    addon.SAVED_VARIABLES_NAME = isDevelopment and (name .. "DevDB") or (name .. "DB")
    addon.FRAME_PREFIX = isDevelopment and (name .. "Dev") or name
    addon.SLASH_COMMANDS = isDevelopment and { "/" .. options.command .. "d", "/" .. lowerName .. "dev" }
        or { "/" .. options.command, "/" .. lowerName }
    ---@type table<string, fun(arguments: string|nil)> handlers of "/<command> <word> <arguments>", by word
    addon.SlashCommands = addon.SlashCommands or {}

    local titleColor = "|cff" .. options.color
    -- A line in the chat frame for the player (not a log line: diagnostics go through the addon's Log).
    ---@param message any
    function addon.Print(message)
        print(titleColor .. addon.TITLE .. "|r: " .. tostring(message))
    end

    -- The TOC declares which global the game saves; if it is not the one this build uses, data would never persist.
    local declaredSavedVariables = Addon.TableOfContentsField(addonName, "SavedVariables")
    if declaredSavedVariables and declaredSavedVariables ~= addon.SAVED_VARIABLES_NAME then
        addon.Print(("the TOC saves %s but this %s build uses %s: nothing will be saved. Dev build: run tools/deploy.ps1 and restart the game."):format(
            declaredSavedVariables, addon.BUILD, addon.SAVED_VARIABLES_NAME))
    end

    if SlashCmdList then
        local slashKey = name:upper() .. (isDevelopment and "DEV" or "")
        for index, command in ipairs(addon.SLASH_COMMANDS) do _G["SLASH_" .. slashKey .. index] = command end
        SlashCmdList[slashKey] = function(input)
            local word, arguments = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
            word = (word or ""):lower()
            if word == "" then
                addon.UI.Toggle()
            elseif addon.SlashCommands[word] then
                addon.SlashCommands[word](arguments)
            else
                local words = lib.Utility.SortedKeys(addon.SlashCommands)
                addon.Print(addon.SLASH_COMMANDS[1] .. " [" .. table.concat(words, "|") .. "]")
            end
        end
    end
end

-- The diagnostic slash commands every addon has (English on purpose: they are read by whoever debugs):
--   comm                 transport state and counters
--   hello                sends a HELLO now
--   debug [count]        the last log lines (default 15)
--   trace [count] [problems]   the last network trace entries (default 20), newest first
-- They read addon.Communication (a Channel), addon.Trace, addon.db.debug and addon.PROTOCOL_* at use time.
---@param addon table
function Addon.AddDiagnosticCommands(addon)
    local Utility = lib.Utility
    addon.SlashCommands.comm = function()
        local Communication = addon.Communication
        local statistics = Communication.sync and Communication.sync.statistics or { sent = 0, received = 0, dropped = 0 }
        addon.Print(("comm: active=%s protocol=%d.%d sent=%d received=%d dropped=%d rejected=%d queue=%d chunks out/in=%d/%d send failures=%d roster=%d incompatible peers=%d"):format(
            tostring(Communication.active), addon.PROTOCOL_MAJOR, addon.PROTOCOL_MINOR, statistics.sent, statistics.received,
            statistics.dropped, Communication.rejected, #Communication.queue, Communication.chunksSent,
            Communication.chunksReceived, Communication.sendFailures, Utility.Count(Communication.roster), Communication.hints.count))
    end

    addon.SlashCommands.hello = function()
        if not addon.Communication.active then addon.Print("not active (not in a guild?)") return end
        addon.Communication.RequestHello(false, true)
        addon.Print("hello sent")
    end

    addon.SlashCommands.debug = function(arguments)
        local lineCount = tonumber((arguments or ""):match("%d+")) or 15
        local logLines = addon.db and addon.db.debug or {}
        for index = math.max(1, #logLines - lineCount + 1), #logLines do print(logLines[index]) end
    end

    addon.SlashCommands.trace = function(arguments)
        local entryCount = tonumber((arguments or ""):match("%d+")) or 20
        local traceEntries = addon.Trace.List((arguments or ""):match("problems") and "problems" or nil)
        for index = math.min(entryCount, #traceEntries), 1, -1 do print(Utility.Escape(addon.Trace.Format(traceEntries[index]))) end
    end
end

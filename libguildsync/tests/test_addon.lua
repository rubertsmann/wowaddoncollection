-- Addon (MINOR 2): identity, build flag, slash dispatcher and diagnostic commands shared by TalentShare and GuildGames.
local MAJOR = "LibGuildSync-1.0"

-- Runs `body(lib)` with the client globals Setup reads replaced: TOC metadata `tableOfContents`, a recording print and
-- SlashCmdList. Returns what was printed.
local function withClient(harness, tableOfContents, body)
    local saved = { C_AddOns = C_AddOns, GetAddOnMetadata = GetAddOnMetadata, print = print, SlashCmdList = SlashCmdList }
    local printed = {}
    C_AddOns = tableOfContents and { GetAddOnMetadata = function(_, field) return tableOfContents[field] end } or nil
    GetAddOnMetadata = nil
    print = function(text) printed[#printed + 1] = text end
    SlashCmdList = {}
    local ok, errorMessage = pcall(body, harness.library())
    for key, value in pairs(saved) do _G[key] = value end
    if not ok then error(errorMessage, 0) end
    return printed
end

local OPTIONS = { name = "TalentShare", prefix = "TShare", command = "ts", fallbackVersion = "0.7.3", color = "33ccff" }

return {
    ["addon: live identity from the three words; version from the TOC"] = function(harness)
        withClient(harness, { Version = "1.2.3", SavedVariables = "TalentShareDB" }, function(lib)
            local addon = {}
            lib.Addon.Setup(addon, "TalentShare", OPTIONS)
            harness.equal(addon.BUILD, "live"); harness.equal(addon.IS_DEVELOPMENT_BUILD, false)
            harness.equal(addon.VERSION, "1.2.3"); harness.equal(addon.BASE_VERSION, "1.2.3")
            harness.equal(addon.TITLE, "TalentShare"); harness.equal(addon.PREFIX, "TShare")
            harness.equal(addon.SAVED_VARIABLES_NAME, "TalentShareDB"); harness.equal(addon.FRAME_PREFIX, "TalentShare")
            harness.equal(addon.SLASH_COMMANDS[1], "/ts"); harness.equal(addon.SLASH_COMMANDS[2], "/talentshare")
            harness.equal(_G.SLASH_TALENTSHARE1, "/ts"); harness.truthy(SlashCmdList.TALENTSHARE)
        end)
    end,

    ["addon: the dev build (folder or TOC flag) is isolated; -dev is appended once"] = function(harness)
        withClient(harness, { Version = "1.2.3-dev", ["X-Build"] = " DEV ", SavedVariables = "GuildGamesDevDB" }, function(lib)
            local addon = {}
            lib.Addon.Setup(addon, "GuildGames", { name = "GuildGames", prefix = "GGames", command = "gg", fallbackVersion = "0.1.0", color = "ffcc33" })
            harness.equal(addon.BUILD, "dev", "the TOC flag alone selects dev")
            harness.equal(addon.VERSION, "1.2.3-dev")
            harness.equal(addon.TITLE, "GuildGames (dev)"); harness.equal(addon.PREFIX, "GGamesDev")
            harness.equal(addon.SAVED_VARIABLES_NAME, "GuildGamesDevDB"); harness.equal(addon.FRAME_PREFIX, "GuildGamesDev")
            harness.equal(addon.SLASH_COMMANDS[1], "/ggd"); harness.equal(addon.SLASH_COMMANDS[2], "/guildgamesdev")
            harness.truthy(SlashCmdList.GUILDGAMESDEV and not SlashCmdList.GUILDGAMES, "only the dev slash key")
        end)
        withClient(harness, nil, function(lib)
            local addon = {}
            lib.Addon.Setup(addon, "TalentShare-Dev", OPTIONS)
            harness.equal(addon.BUILD, "dev", "the folder name alone selects dev")
            harness.equal(addon.VERSION, "0.7.3-dev", "fallback version when the client cannot read the TOC")
        end)
    end,

    ["addon: a TOC that saves another global is reported; Print uses the title"] = function(harness)
        local printed = withClient(harness, { SavedVariables = "TalentShareDB" }, function(lib)
            lib.Addon.Setup({}, "TalentShare-Dev", OPTIONS)
        end)
        harness.equal(#printed, 1)
        harness.truthy(printed[1]:find("|cff33ccffTalentShare (dev)|r: the TOC saves TalentShareDB", 1, true), printed[1])
    end,

    ["addon: the slash dispatcher toggles, runs a word, or lists the words"] = function(harness)
        local printed = withClient(harness, {}, function(lib)
            local addon, toggled, received = {}, 0, nil
            lib.Addon.Setup(addon, "TalentShare", OPTIONS)
            addon.UI = { Toggle = function() toggled = toggled + 1 end }
            addon.SlashCommands.zeta = function(arguments) received = arguments end
            addon.SlashCommands.alpha = function() end
            SlashCmdList.TALENTSHARE("  ")
            harness.equal(toggled, 1)
            SlashCmdList.TALENTSHARE("ZETA  some words ")
            harness.equal(received, "some words")
            SlashCmdList.TALENTSHARE("nope")
        end)
        harness.truthy(printed[#printed]:find("/ts [alpha|zeta]", 1, true), printed[#printed])
    end,

    ["addon: diagnostic commands read the channel, the log and the trace at use time"] = function(harness)
        local printed = withClient(harness, {}, function(lib)
            local addon = {}
            lib.Addon.Setup(addon, "TalentShare", OPTIONS)
            lib.Addon.AddDiagnosticCommands(addon)
            local helloCount = 0
            addon.PROTOCOL_MAJOR, addon.PROTOCOL_MINOR = 2, 3
            addon.Communication = { active = false, rejected = 1, queue = { 1 }, chunksSent = 4, chunksReceived = 5, sendFailures = 0,
                roster = { a = true }, hints = { count = 2 }, RequestHello = function() helloCount = helloCount + 1 end }
            local _, trace = harness.logAndTrace(lib)
            addon.Trace = trace
            addon.db = { debug = { "one", "two", "three" } }
            addon.SlashCommands.comm()
            addon.SlashCommands.hello()
            harness.equal(helloCount, 0, "no HELLO while inactive")
            addon.Communication.active = true
            addon.SlashCommands.hello()
            harness.equal(helloCount, 1)
            addon.SlashCommands.debug("2")
            addon.SlashCommands.trace("5")
        end)
        harness.truthy(printed[1]:find("comm: active=false protocol=2.3 sent=0 received=0 dropped=0 rejected=1 queue=1 chunks out/in=4/5 send failures=0 roster=1 incompatible peers=2", 1, true), printed[1])
        harness.truthy(printed[2]:find("not active", 1, true))
        harness.truthy(printed[3]:find("hello sent", 1, true))
        harness.equal(printed[4], "two"); harness.equal(printed[5], "three")
    end,

    ["addon: a MINOR 1 copy without Addon.lua is upgraded by a MINOR 2 copy that brings it"] = function(harness)
        harness.unloadLibrary()
        harness.loadLibrary(function(source, path)
            source = source:gsub('local MAJOR, MINOR = "LibGuildSync%-1%.0", %d+', 'local MAJOR, MINOR = "LibGuildSync-1.0", 1')
            source = source:gsub('lib:Module%("(%w+)", %d+%)', 'lib:Module("%1", 1)')
            if path:find("Addon.lua", 1, true) then return "" end   -- the MINOR 1 copy has no such file
            return source
        end)
        harness.equal(LibStub(MAJOR).Addon, nil)
        harness.loadLibrary()
        local lib = LibStub(MAJOR)
        harness.equal(lib.MINOR, 2)
        harness.equal(type(lib.Addon.Setup), "function")
    end,
}

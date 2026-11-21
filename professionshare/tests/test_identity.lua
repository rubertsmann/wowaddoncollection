-- Feature 001: live and dev builds must never share state (R2, R3, RF1, RF3)
local function load(addonFolderName)
    local addon = {}
    local chunk = assert(loadfile("Core/Base/Init.lua"))
    chunk(addonFolderName, addon)
    return addon
end

return {
    ["identity: live build uses the live names"] = function(harness)
        local addon = load("ProfessionShare")
        harness.equal(addon.IS_DEVELOPMENT_BUILD, false)
        harness.equal(addon.PREFIX, "PShare")
        harness.equal(addon.SAVED_VARIABLES_NAME, "ProfessionShareDB")
        harness.equal(addon.SLASH_COMMANDS[1], "/ps")
        harness.equal(addon.FRAME_PREFIX, "ProfessionShare")
        harness.equal(addon.VERSION, addon.BASE_VERSION)
    end,

    ["identity: dev build shares nothing with live (RF3)"] = function(harness)
        local live, dev = load("ProfessionShare"), load("ProfessionShare-Dev")
        harness.equal(dev.IS_DEVELOPMENT_BUILD, true)
        for _, field in ipairs({ "PREFIX", "SAVED_VARIABLES_NAME", "FRAME_PREFIX", "TITLE" }) do
            harness.truthy(live[field] ~= dev[field], field .. " is shared between live and dev")
        end
        harness.truthy(live.SLASH_COMMANDS[1] ~= dev.SLASH_COMMANDS[1] and live.SLASH_COMMANDS[2] ~= dev.SLASH_COMMANDS[2], "slash commands shared")
        harness.equal(dev.VERSION, dev.BASE_VERSION .. "-dev")
        harness.equal(dev.PROTOCOL, live.PROTOCOL)
    end,

    ["identity: addon-message prefixes fit the 16 byte limit (RF1)"] = function(harness)
        for _, addonFolderName in ipairs({ "ProfessionShare", "ProfessionShare-Dev" }) do
            local addon = load(addonFolderName)
            harness.truthy(#addon.PREFIX >= 1 and #addon.PREFIX <= 16, addon.PREFIX .. " has an invalid length")
        end
    end,

    ["identity: TOC and Init agree on the live SavedVariables name and version"] = function(harness)
        local f = assert(io.open("ProfessionShare.toc", "rb"))
        local toc = f:read("*a"); f:close()
        local addon = load("ProfessionShare")
        harness.equal(toc:match("## SavedVariables:%s*(%S+)"), addon.SAVED_VARIABLES_NAME, "TOC SavedVariables differs from addon.SAVED_VARIABLES_NAME")
        harness.equal(toc:match("## Version:%s*(%S+)"), addon.BASE_VERSION, "TOC version differs from addon.BASE_VERSION")
    end,
}

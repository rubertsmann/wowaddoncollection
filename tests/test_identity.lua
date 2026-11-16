-- Feature 001: live and dev builds must never share state (R2, R3, RF1, RF3)
local function load(addon)
    local ns = {}
    local chunk = assert(loadfile("Core/Init.lua"))
    chunk(addon, ns)
    return ns
end

return {
    ["identity: live build uses the live names"] = function(h)
        local ns = load("TalentShare")
        h.eq(ns.IS_DEV, false)
        h.eq(ns.PREFIX, "TShare")
        h.eq(ns.SVNAME, "TalentShareDB")
        h.eq(ns.SLASH[1], "/ts")
        h.eq(ns.FRAME, "TalentShare")
        h.eq(ns.VERSION, ns.BASE_VERSION)
    end,

    ["identity: dev build shares nothing with live (RF3)"] = function(h)
        local live, dev = load("TalentShare"), load("TalentShare-Dev")
        h.eq(dev.IS_DEV, true)
        for _, field in ipairs({ "PREFIX", "SVNAME", "FRAME", "TITLE" }) do
            h.truthy(live[field] ~= dev[field], field .. " is shared between live and dev")
        end
        h.truthy(live.SLASH[1] ~= dev.SLASH[1] and live.SLASH[2] ~= dev.SLASH[2], "slash commands shared")
        h.eq(dev.VERSION, dev.BASE_VERSION .. "-dev")
        h.eq(dev.PROTOCOL, live.PROTOCOL)
    end,

    ["identity: addon-message prefixes fit the 16 byte limit (RF1)"] = function(h)
        for _, addon in ipairs({ "TalentShare", "TalentShare-Dev" }) do
            local ns = load(addon)
            h.truthy(#ns.PREFIX >= 1 and #ns.PREFIX <= 16, ns.PREFIX .. " has an invalid length")
        end
    end,

    ["identity: TOC and Init agree on the live SavedVariables name and version"] = function(h)
        local f = assert(io.open("TalentShare.toc", "rb"))
        local toc = f:read("*a"); f:close()
        local ns = load("TalentShare")
        h.eq(toc:match("## SavedVariables:%s*(%S+)"), ns.SVNAME, "TOC SavedVariables differs from ns.SVNAME")
        h.eq(toc:match("## Version:%s*(%S+)"), ns.BASE_VERSION, "TOC version differs from ns.BASE_VERSION")
    end,
}

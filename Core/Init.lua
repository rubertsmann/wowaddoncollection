local ADDON, ns = ...

-- Identity. The ONLY place that knows whether this is the live addon ("TalentShare") or the side-by-side dev copy
-- ("TalentShare-Dev"); everything else reads these fields so both can run in one client without sharing state.
local IS_DEV = type(ADDON) == "string" and ADDON:lower():find("dev", 1, true) ~= nil
ns.IS_DEV = IS_DEV
-- ONE version source: the TOC "## Version" line (read from addon metadata). The literal fallback only matters for the
-- offline tests, which have no client; tests/test_hardening.lua checks it against the TOC.
local function tocField(field)
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if not get then return nil end
    local ok, v = pcall(get, ADDON, field)
    return ok and type(v) == "string" and v ~= "" and v or nil
end
ns.BASE_VERSION = tocField("Version") or "0.3.0"
ns.VERSION = ns.BASE_VERSION .. (IS_DEV and "-dev" or "")
-- Wire protocol (docs/protocol.md): MAJOR must match exactly between peers, MINOR may differ (additive changes only).
-- Bump MAJOR for any breaking change to the chunk header, serializer, compression or message meaning.
ns.PROTO_MAJOR = 2
ns.PROTO_MINOR = 0
ns.PROTOCOL = ns.PROTO_MAJOR                              -- alias: the major is what the payload "v" field carries
ns.TITLE = IS_DEV and "TalentShare (dev)" or "TalentShare"
ns.PREFIX = IS_DEV and "TShareDev" or "TShare"            -- addon-message prefix, max 16 bytes
ns.SVNAME = IS_DEV and "TalentShareDevDB" or "TalentShareDB" -- SavedVariables global (must match the TOC)
ns.FRAME = IS_DEV and "TalentShareDev" or "TalentShare"      -- prefix for global frame names
ns.SLASH = IS_DEV and { "/tsd", "/talentsharedev" } or { "/ts", "/talentshare" }
ns.Slash = {}

function ns.Print(msg)
    print("|cff33ccff" .. ns.TITLE .. "|r: " .. tostring(msg))
end

if SlashCmdList then
    local key = IS_DEV and "TALENTSHAREDEV" or "TALENTSHARE"
    for i, cmd in ipairs(ns.SLASH) do _G["SLASH_" .. key .. i] = cmd end
    SlashCmdList[key] = function(input)
        local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
        cmd = (cmd or ""):lower()
        if cmd == "" then
            if ns.UI and ns.UI.Toggle then
                ns.UI.Toggle()
            else
                ns.Print("v" .. ns.VERSION)
            end
        elseif ns.Slash[cmd] then
            ns.Slash[cmd](rest)
        else
            local names = {}
            for k in pairs(ns.Slash) do names[#names + 1] = k end
            table.sort(names)
            ns.Print(ns.SLASH[1] .. " [" .. table.concat(names, "|") .. "]")
        end
    end
end

ns.Slash.version = function()
    ns.Print("v" .. ns.VERSION .. " (protocol " .. ns.PROTO_MAJOR .. "." .. ns.PROTO_MINOR .. ", schema " .. tostring(ns.Store and ns.Store.SCHEMA) .. ", prefix " .. ns.PREFIX .. ")")
end

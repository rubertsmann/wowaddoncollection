local ADDON, ns = ...

-- Identity. The ONLY place that knows whether this is the live addon ("TalentShare") or the side-by-side dev copy
-- ("TalentShare-Dev"); everything else reads these fields so both can run in one client without sharing state.
local IS_DEV = type(ADDON) == "string" and ADDON:lower():find("dev", 1, true) ~= nil
ns.IS_DEV = IS_DEV
ns.BASE_VERSION = "0.2.0"
ns.VERSION = ns.BASE_VERSION .. (IS_DEV and "-dev" or "")
ns.PROTOCOL = 1
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

ns.Slash.version = function() ns.Print("v" .. ns.VERSION .. " (protocol " .. ns.PROTOCOL .. ", prefix " .. ns.PREFIX .. ")") end

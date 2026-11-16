local ADDON, ns = ...

ns.VERSION = "0.1.0"
ns.PROTOCOL = 1
ns.PREFIX = "TShare"
ns.Slash = {}

function ns.Print(msg)
    print("|cff33ccffTalentShare|r: " .. tostring(msg))
end

if SlashCmdList then
    SLASH_TALENTSHARE1 = "/ts"
    SLASH_TALENTSHARE2 = "/talentshare"
    SlashCmdList["TALENTSHARE"] = function(input)
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
            ns.Print("/ts [" .. table.concat(names, "|") .. "]")
        end
    end
end

ns.Slash.version = function() ns.Print("v" .. ns.VERSION .. " (protocol " .. ns.PROTOCOL .. ")") end

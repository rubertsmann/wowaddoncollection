local addonName, addon = ...

-- /fbui editmode: lists every Edit Mode setting the client knows (Enum.EditMode<System>Setting) and marks the ones the
-- Edit Mode dialog has no control for (no entry in EditModeSettingDisplayInfoManager) as HIDDEN. Settings whose name
-- mentions opacity/alpha/fade/visibility are highlighted. Everything goes to the log (/fbui log, or the
-- SavedVariables file); chat only gets the hidden and the opacity-related ones.
local Probe = {}
addon.EditModeProbe = Probe

local INTERESTING = { "opacity", "alpha", "fade", "visib", "transparen" }

local function interesting(name)
    local lower = name:lower()
    for _, word in ipairs(INTERESTING) do if lower:find(word, 1, true) then return true end end
    return false
end

local function displayedSettings()
    local shown = {}
    local manager = EditModeSettingDisplayInfoManager
    local bySystem = manager and manager.systemSettingDisplayInfo
    if type(bySystem) ~= "table" then return shown, false end
    for system, infos in pairs(bySystem) do
        if type(infos) == "table" then
            for _, info in pairs(infos) do
                if type(info) == "table" and info.setting ~= nil then
                    shown[tostring(system) .. ":" .. tostring(info.setting)] = info.name or true
                end
            end
        end
    end
    return shown, true
end

---@param print fun(message: string)
function Probe.Run(print)
    if type(Enum) ~= "table" then return print("this client has no Enum table.") end
    local shown, haveDisplayInfo = displayedSettings()
    local systems = Enum.EditModeSystem or {}
    local enumNames = {}
    for enumName, values in pairs(Enum) do
        if type(values) == "table" and enumName:match("^EditMode.+Setting$") then enumNames[#enumNames + 1] = enumName end
    end
    table.sort(enumNames)
    if #enumNames == 0 then return print("no Enum.EditMode*Setting tables found.") end

    local hiddenCount, total = 0, 0
    addon.Log.Write("editmode", "---- probe ----", { displayInfo = haveDisplayInfo, enums = #enumNames })
    for _, enumName in ipairs(enumNames) do
        local systemName = enumName:match("^EditMode(.+)Setting$")
        local system = systems[systemName]
        local entries = {}
        for name, id in pairs(Enum[enumName]) do
            if type(id) == "number" then entries[#entries + 1] = { name = name, id = id } end
        end
        table.sort(entries, function(a, b) return a.id < b.id end)
        for _, entry in ipairs(entries) do
            total = total + 1
            local hidden = haveDisplayInfo and system ~= nil and not shown[system .. ":" .. entry.id]
            local line = string.format("%s.%s = %d%s%s", enumName, entry.name, entry.id,
                system == nil and " (no system)" or "", hidden and "  HIDDEN" or "")
            addon.Log.Write("editmode", line)
            if hidden then hiddenCount = hiddenCount + 1 end
            if hidden or interesting(entry.name) then
                print((interesting(entry.name) and "|cffffd100" or "|cffaaaaaa") .. line .. "|r")
            end
        end
    end
    print(string.format("%d Edit Mode settings, %d without a control in the dialog%s. Full list: /fbui log 200.",
        total, hiddenCount, haveDisplayInfo and "" or " (display info not found, cannot tell hidden ones)"))
end

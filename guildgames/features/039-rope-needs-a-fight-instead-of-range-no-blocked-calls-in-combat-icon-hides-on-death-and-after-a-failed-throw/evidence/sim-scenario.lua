local MODE = "nofight"
local GUID = "Creature-0-1-2-3-2248-000000AAAA"
local REPORT = {}
local function out(...) local parts = {} for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end REPORT[#REPORT + 1] = table.concat(parts, " ") end
if DEFAULT_CHAT_FRAME and hooksecurefunc then hooksecurefunc(DEFAULT_CHAT_FRAME, "AddMessage", function(_, text) out("chat:", tostring(text)) end) end
UnitExists = function(u) return u == "target" end
UnitGUID = function(u) if u == "target" then return GUID end if u == "player" then return "Player-1-00000001" end end
UnitHealth = function(u) if u == "target" then return MODE == "dead" and 0 or 20 end return 100 end
UnitHealthMax = function() return 100 end
UnitLevel = function() return 10 end
UnitCanAttack = function(a, b) return b == "target" end
UnitName = function(u) if u == "target" then return "Testwolf" end return "Me" end
UnitClassification = function() return "normal" end
UnitIsDead = function(u) return u == "target" and MODE == "dead" end
UnitIsTapDenied = function() return false end
CheckInteractDistance = function() out("PROBLEM: CheckInteractDistance was called") return true end
UnitThreatSituation = function(p, u) if u == "target" and MODE == "fight" then return 1 end return nil end
if TargetFrame then pcall(TargetFrame.Show, TargetFrame) end
local slash = SlashCmdList["GUILDGAMES"]
slash("caught icon target on")
local function iconState(label)
    local found = 0
    local frame = EnumerateFrames and EnumerateFrames()
    while frame do
        local ok, point, relative = pcall(frame.GetPoint, frame, 1)
        if ok and relative == TargetFrame and frame:GetObjectType() == "Button" then
            found = found + 1
            local grey = false
            for _, region in ipairs({ frame:GetRegions() }) do
                if region.IsDesaturated and region:IsDesaturated() then grey = true end
            end
            out(label, "icon shown", tostring(frame:IsShown()), "alpha", tostring(frame:GetAlpha()), "greyed", tostring(grey))
        end
        frame = EnumerateFrames(frame)
    end
    if found == 0 then out(label, "no icon button anchored at the target frame") end
end
iconState("before throw:")
local ok, err = pcall(_G.GuildGamesAzeCaughtThrow)
out("throw binding ran", tostring(ok), tostring(err))
iconState("after throw:")
error("SIMREPORT " .. MODE .. " | " .. table.concat(REPORT, " | "), 0)

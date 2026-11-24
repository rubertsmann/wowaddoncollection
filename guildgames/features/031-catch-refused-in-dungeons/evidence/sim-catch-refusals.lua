local seen, recording = {}, true
hooksecurefunc(UIErrorsFrame, "AddMessage", function(_, text) if recording then seen[#seen + 1] = "overlay: " .. tostring(text) end end)
hooksecurefunc(DEFAULT_CHAT_FRAME, "AddMessage", function(_, text) if recording then seen[#seen + 1] = "chat: " .. tostring(text) end end)
local function run(label)
    seen[#seen + 1] = "== " .. label
    local ok, err = pcall(SlashCmdList["GUILDGAMES"], "catch")
    if not ok then seen[#seen + 1] = "error: " .. tostring(err) end
end
IsInInstance = function() return true, "party" end
run("dungeon")
IsInInstance = function() return false, "none" end
UnitExists = function() return true end
UnitGUID = function() return "Creature-0-1-2-3-299-0000AB" end
UnitHealth = function() return 10 end
UnitHealthMax = function() return 100 end
UnitLevel = function() return 10 end
UnitCanAttack = function() return true end
UnitName = function() return "Wolf" end
UnitIsDead = function() return false end
UnitIsTapDenied = function() return true end
CheckInteractDistance = function() return true end
run("tagged by someone else")
UnitIsTapDenied = function() return false end
CheckInteractDistance = function() return false end
run("out of range")
recording = false
for _, line in ipairs(seen) do print("SIMSEEN " .. line) end

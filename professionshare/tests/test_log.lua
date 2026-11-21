-- Core/Base/Log.lua: the one logging helper. The log is the only evidence of what happened on a player's client, so its
-- line format, escaping, bounds and the error paths (Exception, Protected) are pinned here.
local tests = {}

local function lastLine(addon) return addon.db.debug[#addon.db.debug] end

tests["log: every level writes '<time> LEVEL [area] message :: key=value' with sorted keys"] = function(harness)
    local addon = harness.addon()
    addon.Log.Reset()
    addon.Log.Error("communication.send", "the client refused an addon message", { target = "Bob-R", channel = "GUILD" })
    local line = lastLine(addon)
    harness.truthy(line:find("ERROR [communication.send] the client refused an addon message :: channel=GUILD target=Bob-R", 1, true), line)
    harness.truthy(line:match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d "), "time stamp first: " .. line)
    addon.Log.Warning("store.load", "dropped invalid records", { count = 2 })
    harness.truthy(lastLine(addon):find("WARNING [store.load] dropped invalid records :: count=2", 1, true))
    addon.Log.Information("scanner.profession", "profession scanned")
    harness.truthy(lastLine(addon):find("INFORMATION [scanner.profession] profession scanned", 1, true))
    harness.truthy(not lastLine(addon):find(" :: ", 1, true), "no details -> no separator")
    addon.Log.Debug("window.click", "row clicked", { row = 3 })
    harness.truthy(lastLine(addon):find("DEBUG [window.click] row clicked :: row=3", 1, true))
end

tests["log: peer text is escaped and line breaks are flattened, because /ps debug prints to the chat frame"] = function(harness)
    local addon = harness.addon()
    addon.Log.Warning("communication.decode", "message rejected", { sender = "|cffff0000Evil-R", link = "|Hitem:1|h", note = "a\nb" })
    local line = lastLine(addon)
    harness.truthy(line:find("||cffff0000Evil-R", 1, true), line)
    harness.truthy(not line:find("[^|]|[^|]"), "unescaped | in: " .. line)
    harness.truthy(not line:find("\n", 1, true), "line break in: " .. line)
end

tests["log: long values are cut, repeats are folded, the ring is bounded"] = function(harness)
    local addon = harness.addon()
    addon.Log.Reset()
    addon.Log.Information("test.long", "long value", { value = string.rep("x", 500) })
    harness.truthy(#lastLine(addon) < 300, "value must be truncated")
    local before = #addon.db.debug
    for _ = 1, 5 do addon.Log.Warning("test.repeat", "same thing again", { count = 1 }) end
    harness.equal(#addon.db.debug, before + 1, "repeats are folded into one line")
    harness.truthy(lastLine(addon):find("(repeated 5 times)", 1, true), lastLine(addon))
    for index = 1, addon.Log.MAXIMUM_ENTRIES + 20 do addon.Log.Debug("test.bound", "entry", { index = index }) end
    harness.equal(#addon.db.debug, addon.Log.MAXIMUM_ENTRIES)
end

tests["log: Exception records the error and a stack and calls the game's error handler"] = function(harness)
    local addon = harness.addon()
    local handled
    local savedHandler = geterrorhandler
    geterrorhandler = function() return function(text) handled = text end end
    addon.Log.Exception("sync.message", "a message handler failed", "boom", { messageType = "SNAP" })
    geterrorhandler = savedHandler
    local line = lastLine(addon)
    harness.truthy(line:find("ERROR [sync.message] a message handler failed :: error=boom messageType=SNAP stack=", 1, true), line)
    harness.truthy(handled and handled:find("sync.message: boom", 1, true), tostring(handled))
end

tests["log: Protected returns pcall's results and logs a failure with the failing function in the stack"] = function(harness)
    local addon = harness.addon()
    local ok, first, second = addon.Log.Protected("test.protected", "adds", function(left, right) return left + right, "fine" end, 2, 3)
    harness.equal(ok, true); harness.equal(first, 5); harness.equal(second, "fine")
    local before = #addon.db.debug
    local savedHandler = geterrorhandler
    geterrorhandler = nil
    local function failingFunction() error("broken input") end
    local failed, errorMessage = addon.Log.Protected("test.protected", "runs a failing function", failingFunction)
    geterrorhandler = savedHandler
    harness.equal(failed, false)
    harness.truthy(tostring(errorMessage):find("broken input", 1, true))
    harness.equal(#addon.db.debug, before + 1)
    local line = lastLine(addon)
    harness.truthy(line:find("ERROR [test.protected] runs a failing function :: error=", 1, true), line)
    harness.truthy(line:find("stack=", 1, true), line)
end

tests["log: nothing is stored before the saved data exists, and nothing breaks"] = function(harness)
    local addon = harness.addon()
    local database = addon.db
    addon.db = nil
    local body = addon.Log.Error("events.load", "too early")
    addon.db = database
    harness.truthy(body:find("ERROR [events.load] too early", 1, true))
end

return tests

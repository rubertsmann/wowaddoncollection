-- Core: one active copy of the library when several addons embed it (spec RF1), and the MINOR rule.
local MAJOR = "LibGuildSync-1.0"

-- rewrites every file of a copy to another MINOR and marks the copy, so the test can see which copy's code runs
local function copyWithMinor(minor, mark)
    return function(source)
        source = source:gsub('local MAJOR, MINOR = "LibGuildSync%-1%.0", %d+', 'local MAJOR, MINOR = "LibGuildSync-1.0", ' .. minor)
        source = source:gsub('lib:Module%("(%w+)", %d+%)', 'lib:Module("%1", ' .. minor .. ')')
        source = source:gsub("function Locale%.Format%(template, values%)",
            "function Locale.CopyMark() return '" .. mark .. "' end\nfunction Locale.Format(template, values)")
        return source
    end
end

return {
    ["core: every library file registers with Core's MINOR"] = function(harness)
        local handle = assert(io.open(harness.LIBRARY_FOLDER .. "Core.lua", "rb"))
        local core = handle:read("*a"); handle:close()
        local minor = core:match('local MAJOR, MINOR = "LibGuildSync%-1%.0", (%d+)')
        harness.truthy(minor, "Core.lua declares MINOR")
        for _, path in ipairs(harness.libraryFiles()) do
            if not path:find("Core.lua", 1, true) then
                local file = assert(io.open(path, "rb"))
                local source = file:read("*a"); file:close()
                local moduleName, moduleMinor = source:match('lib:Module%("(%w+)", (%d+)%)')
                harness.truthy(moduleName, path .. " does not register with lib:Module")
                harness.equal(moduleMinor, minor, path .. " registers a different MINOR")
                harness.truthy(source:find("if not " .. moduleName .. " then return end", 1, true), path .. " must stop when skipped")
            end
        end
    end,

    ["core: a newer copy loaded second upgrades every module in place; instances see the new code"] = function(harness)
        harness.unloadLibrary()
        harness.loadLibrary(copyWithMinor(1, "old"))
        local lib = LibStub(MAJOR)
        local utility, sync = lib.Utility, lib.Sync
        lib.Utility.LearnMyRealm("Some Realm")
        local version = lib.Utility.realmAliasVersion
        local instance = lib.Sync.New({ send = function() end, now = function() return 1 end, random = math.random, me = "A-R", protocol = 1 })
        harness.equal(lib.Locale.CopyMark(), "old")
        harness.loadLibrary(copyWithMinor(2, "new"))
        harness.equal(LibStub(MAJOR), lib, "same library table")
        harness.equal(lib.MINOR, 2)
        harness.equal(lib.Utility, utility, "module tables keep their identity")
        harness.equal(lib.Sync, sync)
        harness.equal(lib.Locale.CopyMark(), "new", "the newer code is active")
        harness.equal(lib.Utility.realmAliasVersion, version, "state survives the upgrade")
        harness.truthy(lib.Utility.RealmAliases()[1], "learned realm spelling survives the upgrade")
        harness.equal(getmetatable(instance).__index, lib.Sync, "old instances use the upgraded module")
    end,

    ["core: an older copy loaded second is skipped file by file"] = function(harness)
        harness.unloadLibrary()
        harness.loadLibrary(copyWithMinor(3, "newer"))
        harness.loadLibrary(copyWithMinor(2, "older"))
        local lib = LibStub(MAJOR)
        harness.equal(lib.MINOR, 3)
        harness.equal(lib.Locale.CopyMark(), "newer")
    end,

    ["core: a second copy of the same version is skipped, so its state is not reset"] = function(harness)
        harness.unloadLibrary()
        harness.loadLibrary(copyWithMinor(1, "first"))
        local lib = LibStub(MAJOR)
        lib.Channel.shared.tokens = 2.5
        lib.Utility.LearnMyRealm("Other Realm")
        harness.loadLibrary(copyWithMinor(1, "second"))
        harness.equal(lib.Locale.CopyMark(), "first")
        harness.equal(lib.Channel.shared.tokens, 2.5, "shared bucket kept")
        harness.truthy(lib.Utility.RealmAliases()[1], "realm aliases kept")
    end,

    ["utility: the name state is shared, Me is not part of the library"] = function(harness)
        local lib = harness.library()
        harness.equal(lib.Utility.Me, nil, "Me belongs to each addon")
        harness.truthy(lib.Utility.CanonicalName and lib.Utility.SafeInteger and lib.Utility.SearchKey, "helpers present")
    end,

    ["log: dot-call instance writes the one line format into its own table"] = function(harness)
        local lib = harness.library()
        local log, _, db = harness.logAndTrace(lib)
        log.Warning("test.area", "something happened", { b = 2, a = "x|y" })
        harness.truthy(db.debug[1]:find("WARNING [test.area] something happened :: a=x||y b=2", 1, true), db.debug[1])
        log.Warning("test.area", "something happened", { b = 2, a = "x|y" })
        harness.equal(#db.debug, 1, "repeats folded")
        harness.truthy(db.debug[1]:find("(repeated 2 times)", 1, true))
        local ok = log.Protected("test.protected", "fails", function() error("boom") end)
        harness.equal(ok, false)
        harness.truthy(db.debug[2]:find("ERROR [test.protected] fails", 1, true))
        local other, _, otherDb = harness.logAndTrace(lib)
        other.Information("x.y", "separate")
        harness.equal(#otherDb.debug, 1); harness.equal(#db.debug, 2, "instances do not share storage")
    end,

    ["trace: bounded ring, problems filter, custom summary"] = function(harness)
        local lib = harness.library()
        local db = { debug = {}, trace = {} }
        local log = lib.Log.New({ entries = function() return db.debug end, title = "T" })
        local trace = lib.Trace.New({ entries = function() return db.trace end, log = log,
            summarize = function(message) return "n=" .. tostring(message.n) end })
        for index = 1, trace.MAXIMUM_ENTRIES + 5 do trace.Add({ dir = "out", mt = "X", st = index % 2 == 0 and "failed" or "sent" }) end
        harness.equal(#db.trace, trace.MAXIMUM_ENTRIES)
        for _, entry in ipairs(trace.List("problems")) do harness.equal(entry.st, "failed") end
        harness.equal(trace.Summarize({ n = 4 }), "n=4")
        harness.equal(trace.Summarize("x"), "?")
        harness.truthy(trace.Format({ t = 3661, dir = "in", st = "ok", mt = "HELLO" }):find("01:01:01 <- HELLO [ok]", 1, true))
    end,

    ["locale: instances have their own strings; Format keeps unknown placeholders"] = function(harness)
        local lib = harness.library()
        local first, second = lib.Locale.New(), lib.Locale.New()
        first.RegisterStrings("deDE", { ["Hello"] = "Hallo" })
        first.SetInterfaceLanguage("deDE"); second.SetInterfaceLanguage("deDE")
        harness.equal(first.Text["Hello"], "Hallo")
        harness.equal(second.Text["Hello"], "Hello")
        harness.equal(lib.Locale.Format("{n} of {m}", { n = 1 }), "1 of {m}")
        harness.equal(lib.Locale.Plural(1, "{n} item", "{n} items"), "1 item")
    end,

    ["events: a failing handler is logged and the others still run"] = function(harness)
        local lib = harness.library()
        local log, _, db = harness.logAndTrace(lib)
        local events = lib.Events.New(log)
        local seen = {}
        events.On("X", function() error("first fails") end)
        events.On("X", function(value) seen[#seen + 1] = value end)
        events.Fire("X", 7)
        harness.equal(seen[1], 7)
        harness.truthy(db.debug[1]:find("ERROR [events.fire]", 1, true))
    end,

    ["codec: per-addon protocol in the header and the payload"] = function(harness)
        local lib = harness.library()
        local codecA, codecB = lib.Codec.New({ major = 2, minor = 3 }), lib.Codec.New({ major = 1, minor = 0 })
        local encoded = codecA.Encode({ t = "HELLO", rev = 5 })
        local message = assert(codecA.Decode(encoded))
        harness.equal(message.rev, 5); harness.equal(message.v, 2)
        harness.equal(select(2, codecB.Decode(encoded)), "protocol version", "another addon's protocol is refused")
        harness.equal(codecA.Header("ab12", 1, 2), "2.3|ab12|1|2|")
        local header = codecB.ParseHeader("2.3|ab12|1|2|x")
        harness.equal(header.major, 2); harness.equal(header.transferID, nil, "foreign major: only the version is parsed")
        harness.equal(codecB.Compatibility(1, 4), "newer-minor"); harness.equal(codecB.Compatibility(0, 9), "older")
        harness.equal(codecA.CHUNK_BYTES, lib.Codec.CHUNK_BYTES)
        harness.equal((codecA.Decode(string.rep("x", codecA.MAXIMUM_ENCODED_BYTES + 1))), nil)
    end,
}

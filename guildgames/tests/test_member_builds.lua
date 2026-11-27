-- The maintainer's "member builds" button: who may see it (Model.IsBuildViewer) and the rows its tooltip lists
-- (Model.MemberBuilds: the live HELLO build next to the version the synced record carries).

return {
    ["member builds: only the viewer's name (any case, with or without realm) shows the button"] = function(harness)
        local Model = harness.addon().Model
        local savedHashes = Model.BUILD_VIEWER_HASHES
        Model.BUILD_VIEWER_HASHES = { [Model.NameHash("test viewer")] = true }   -- a made-up name: no real ones in the repo
        harness.equal(Model.IsBuildViewer("Test Viewer"), true)
        harness.equal(Model.IsBuildViewer("test viewer-Some Realm"), true, "the realm is ignored")
        harness.equal(Model.IsBuildViewer(" TEST VIEWER "), true)
        harness.equal(Model.IsBuildViewer("Test Viewers"), false)
        harness.equal(Model.IsBuildViewer(""), false); harness.equal(Model.IsBuildViewer(nil), false)
        Model.BUILD_VIEWER_HASHES = savedHashes
        harness.equal(Model.NameHash("a"), (5381 * 33 + 97) % 4294967296)
        harness.equal(Model.IsBuildViewer("Test Viewer"), false, "the shipped list has exactly one entry, not this name")
        local count = 0
        for _ in pairs(savedHashes) do count = count + 1 end
        harness.equal(count, 1)
    end,

    ["member builds: record version next to the live build, stale records first, escaped"] = function(harness)
        local Model = harness.addon().Model
        local records = {
            ["Me-Realm"] = { name = "Me-Realm", rev = 900, arena = { ver = "0.13.0" } },
            ["Current-Realm"] = { name = "Current-Realm", rev = 800, arena = { ver = "0.13.0" } },
            ["Stale-Realm"] = { name = "Stale-Realm", rev = 100, arena = { ver = "0.12.0" } },
            ["NoArena-Realm"] = { name = "NoArena-Realm", rev = 700 },
            ["BadVer-Realm"] = { name = "BadVer-Realm", rev = 600, arena = { ver = { "table" } } },
            ["Pipe|cffff0000X"] = { rev = 500, arena = { ver = "0.13.0" } },
            ["Garbage-Realm"] = "not a table",
            ["Dev-Realm"] = { rev = 400, arena = { ver = "0.13.0-dev" } },
        }
        local versionRows = {
            { name = "Current-Realm", ver = "0.13.0/3", t = 850 },
            { name = "Stale-Realm", ver = "0.13.0/3", t = 950 },
            { name = "HelloOnly-Realm", ver = "0.13.0/3", t = 990 },
            { name = "Dev-Realm", ver = "0.13.0-dev/3", t = 10 },
            { name = "", ver = "0.13.0/3", t = 1 },
            "garbage",
        }
        local rows = Model.MemberBuilds(records, versionRows, "Me-Realm")
        local byName = {}
        for _, row in ipairs(rows) do byName[row.name] = row end
        harness.equal(byName["Me-Realm"], nil, "my own row is left out (my build is the header line)")
        harness.equal(rows[1].name, "Stale-Realm", "a mismatch sorts first")
        harness.equal(rows[1].live, "0.13.0/3"); harness.equal(rows[1].record, "0.12.0"); harness.equal(rows[1].mismatch, true)
        harness.equal(rows[1].rev, 100)
        harness.equal(byName["Current-Realm"].mismatch, false)
        harness.equal(byName["Dev-Realm"].mismatch, false, "only the /minor part of the live tag is cut")
        harness.equal(byName["HelloOnly-Realm"].record, nil); harness.equal(byName["HelloOnly-Realm"].mismatch, false)
        harness.equal(byName["NoArena-Realm"].record, nil); harness.equal(byName["NoArena-Realm"].live, nil)
        harness.equal(byName["BadVer-Realm"].record, nil)
        harness.equal(byName["Pipe||cffff0000X"] ~= nil, true, "names are escaped")
        harness.equal(byName["Garbage-Realm"], nil)
        harness.equal(#rows, 7)
        harness.equal(rows[2].name, "HelloOnly-Realm", "then the most recent (HELLO or record time)")
        harness.equal(#Model.MemberBuilds(nil, nil, nil), 0)
    end,

    ["arena version: my section is rewritten when missing or from another build, not without a record"] = function(harness)
        local addon = harness.addon()
        local Arena = addon.Arena
        harness.equal(Arena.SectionStale(nil), false, "no record yet: nothing to fix")
        harness.equal(Arena.SectionStale({ rev = 1 }), true, "a record without an arena section")
        harness.equal(Arena.SectionStale({ rev = 1, arena = "garbage" }), true)
        harness.equal(Arena.SectionStale({ rev = 1, arena = { ver = "0.11.0" } }), true, "an older build")
        harness.equal(Arena.SectionStale({ rev = 1, arena = { ver = addon.VERSION } }), false)
        local section = Arena.BuildSection()
        harness.equal(Arena.SectionStale({ rev = 1, arena = section }), false, "a freshly built section is current")
    end,
}

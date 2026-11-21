-- The live "member builds" button: who may see it, and the rows its tooltip lists (Model.IsBuildViewer, Model.MemberBuilds).

return {
    ["member builds: only the viewer's name (any case, with or without realm) shows the button"] = function(harness)
        local Model = harness.addon().Model
        local savedHashes = Model.BUILD_VIEWER_HASHES
        Model.BUILD_VIEWER_HASHES = { [Model.NameHash("test viewer")] = true }   -- a made-up name: no real ones in the repo
        harness.equal(Model.IsBuildViewer("Test Viewer"), true)
        harness.equal(Model.IsBuildViewer("test viewer-Some Realm"), true, "the realm is ignored")
        harness.equal(Model.IsBuildViewer(" TEST VIEWER "), true)
        harness.equal(Model.IsBuildViewer("Test Viewers"), false)
        harness.equal(Model.IsBuildViewer("Someone Else"), false)
        harness.equal(Model.IsBuildViewer(""), false); harness.equal(Model.IsBuildViewer(nil), false)
        Model.BUILD_VIEWER_HASHES = savedHashes
        harness.equal(Model.NameHash("a"), (5381 * 33 + 97) % 4294967296)
        harness.equal(Model.IsBuildViewer("Test Viewer"), false, "the shipped list has exactly one entry, not this name")
        local count = 0
        for _ in pairs(savedHashes) do count = count + 1 end
        harness.equal(count, 1)
    end,

    ["member builds: senders from the trace with the build each announced, most recent first, escaped"] = function(harness)
        local Model = harness.addon().Model
        local inbound = {
            { dir = "in", peer = "Old Build", t = 300, st = "ok" },
            { dir = "in", peer = "New Build", t = 200, st = "ok" },
            { dir = "in", peer = "New Build", t = 100, st = "ok" },
            { dir = "in", t = 50, st = "dropped" },   -- no peer: skipped
            { dir = "in", peer = "Pipe|cffff0000Name", t = 10, st = "rejected" },
        }
        local versions = { { name = "New Build", ver = "1.0.1/3", t = 250 }, { name = "Only Hello", ver = "1.0.2/3", t = 5 } }
        local rows = Model.MemberBuilds(inbound, versions)
        harness.equal(#rows, 4)
        harness.equal(rows[1].name, "Old Build"); harness.equal(rows[1].ver, nil); harness.equal(rows[1].messages, 1)
        harness.equal(rows[2].name, "New Build"); harness.equal(rows[2].ver, "1.0.1/3"); harness.equal(rows[2].messages, 2)
        harness.equal(rows[2].t, 250, "the newest of trace and HELLO time")
        harness.equal(rows[3].name, "Pipe||cffff0000Name", "peer names are escaped")
        harness.equal(rows[4].name, "Only Hello"); harness.equal(rows[4].messages, 0)
        harness.equal(#Model.MemberBuilds(nil, nil), 0)
        harness.equal(#Model.MemberBuilds({ "garbage", { peer = 5 } }, { "garbage", { name = "" } }), 0)
    end,
}

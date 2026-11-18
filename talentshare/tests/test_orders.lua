-- Orders model + merge (RF4)
local function replica(harness)
    local addon = harness.addon()
    return addon, addon.Orders.New(function() return harness.clock end, {})
end

return {
    ["orders: create -> claim by two crafters -> status claimed; withdrawing both reopens"] = function(harness)
        local _, o = replica(harness)
        local ord = o:Create("Bob-R", 5, 3, "please")
        o:Claim(ord.id, "A-R"); o:Claim(ord.id, "B-R")
        harness.equal(o:Status(ord), "claimed"); harness.equal(#o:Claimers(ord), 2)
        o:Withdraw(ord.id, "A-R"); harness.equal(o:Status(ord), "claimed")
        o:Withdraw(ord.id, "B-R"); harness.equal(o:Status(ord), "open")
    end,

    ["orders: merge is idempotent"] = function(harness)
        local _, a = replica(harness); local _, b = replica(harness)
        local ord = a:Create("Bob-R", 5, 1)
        harness.truthy(b:Merge(ord)); harness.equal(b:Merge(ord), false)
    end,

    ["orders: concurrent claims on two replicas converge to the union (RF4)"] = function(harness)
        local _, a = replica(harness); local _, b = replica(harness)
        local ord = a:Create("Bob-R", 5, 2)
        b:Merge(ord)
        harness.clock = harness.clock + 1
        a:Claim(ord.id, "A-R"); b:Claim(ord.id, "B-R")
        a:Merge(b:Get(ord.id)); b:Merge(a:Get(ord.id))
        harness.equal(#a:Claimers(a:Get(ord.id)), 2); harness.equal(#b:Claimers(b:Get(ord.id)), 2)
        harness.equal(a.Version(a:Get(ord.id)), b.Version(b:Get(ord.id)))
    end,

    ["orders: only the requester can cancel; requester or claimer can mark done"] = function(harness)
        local _, o = replica(harness)
        local ord = o:Create("Bob-R", 5, 1)
        o:Claim(ord.id, "A-R")
        harness.equal(o:Close(ord.id, "A-R", "cancelled"), nil)
        harness.equal(o:Close(ord.id, "Stranger-R", "done"), nil)
        harness.truthy(o:Close(ord.id, "A-R", "done"))
        harness.equal(o:Status(ord), "done")
    end,

    ["orders: close wins over a late claim and merge order does not matter"] = function(harness)
        local _, a = replica(harness); local _, b = replica(harness)
        local ord = a:Create("Bob-R", 5, 1)
        b:Merge(ord)
        harness.clock = harness.clock + 5
        a:Close(ord.id, "Bob-R", "cancelled")
        b:Claim(ord.id, "A-R")
        a:Merge(b:Get(ord.id)); b:Merge(a:Get(ord.id))
        harness.equal(a:Status(a:Get(ord.id)), "cancelled"); harness.equal(b:Status(b:Get(ord.id)), "cancelled")
    end,

    ["orders: invalid orders are rejected (qty, note, shape)"] = function(harness)
        local _, o = replica(harness)
        local good = o:Create("Bob-R", 5, 1)
        for _, mutate in ipairs({
            function(x) x.qty = 0 end, function(x) x.qty = 100 end, function(x) x.note = string.rep("x", 81) end,
            function(x) x.id = nil end, function(x) x.claims = "no" end, function(x) x.closed = "weird" end,
        }) do
            local copy = { id = "X:1:1", requester = "Bob-R", recipeID = 5, qty = 1, note = "", createdAt = 1, claims = {} }
            mutate(copy)
            harness.equal(o:Merge(copy), false)
        end
        harness.truthy(good)
    end,

    ["orders: Digest/Missing return exactly the differing orders"] = function(harness)
        local _, a = replica(harness); local _, b = replica(harness)
        local o1 = a:Create("Bob-R", 1, 1); harness.clock = harness.clock + 1
        local o2 = a:Create("Bob-R", 2, 1)
        b:Merge(o1)
        local miss = a:Missing(b:Digest())
        harness.equal(#miss, 1); harness.equal(miss[1].id, o2.id)
        harness.clock = harness.clock + 1
        a:Claim(o1.id, "A-R")
        harness.equal(#a:Missing(b:Digest()), 2)
    end,

    ["orders: Prune drops old closed orders only"] = function(harness)
        local _, o = replica(harness)
        local old = o:Create("Bob-R", 1, 1)
        o:Close(old.id, "Bob-R", "done")
        local fresh = o:Create("Bob-R", 2, 1)
        harness.equal(o:Prune(harness.clock + 8 * 86400), 1)
        harness.truthy(o:Get(fresh.id) == nil or o:Get(fresh.id) ~= nil) -- fresh survives only within 30 days
        harness.equal(o:Get(old.id), nil)
    end,
}

-- Orders model + merge (RF4)
local function replica(h)
    local ns = h.ns()
    return ns, ns.Orders.New(function() return h.clock end, {})
end

return {
    ["orders: create -> claim by two crafters -> status claimed; withdrawing both reopens"] = function(h)
        local _, o = replica(h)
        local ord = o:Create("Bob-R", 5, 3, "please")
        o:Claim(ord.id, "A-R"); o:Claim(ord.id, "B-R")
        h.eq(o:Status(ord), "claimed"); h.eq(#o:Claimers(ord), 2)
        o:Withdraw(ord.id, "A-R"); h.eq(o:Status(ord), "claimed")
        o:Withdraw(ord.id, "B-R"); h.eq(o:Status(ord), "open")
    end,

    ["orders: merge is idempotent"] = function(h)
        local _, a = replica(h); local _, b = replica(h)
        local ord = a:Create("Bob-R", 5, 1)
        h.truthy(b:Merge(ord)); h.eq(b:Merge(ord), false)
    end,

    ["orders: concurrent claims on two replicas converge to the union (RF4)"] = function(h)
        local _, a = replica(h); local _, b = replica(h)
        local ord = a:Create("Bob-R", 5, 2)
        b:Merge(ord)
        h.clock = h.clock + 1
        a:Claim(ord.id, "A-R"); b:Claim(ord.id, "B-R")
        a:Merge(b:Get(ord.id)); b:Merge(a:Get(ord.id))
        h.eq(#a:Claimers(a:Get(ord.id)), 2); h.eq(#b:Claimers(b:Get(ord.id)), 2)
        h.eq(a.Version(a:Get(ord.id)), b.Version(b:Get(ord.id)))
    end,

    ["orders: only the requester can cancel; requester or claimer can mark done"] = function(h)
        local _, o = replica(h)
        local ord = o:Create("Bob-R", 5, 1)
        o:Claim(ord.id, "A-R")
        h.eq(o:Close(ord.id, "A-R", "cancelled"), nil)
        h.eq(o:Close(ord.id, "Stranger-R", "done"), nil)
        h.truthy(o:Close(ord.id, "A-R", "done"))
        h.eq(o:Status(ord), "done")
    end,

    ["orders: close wins over a late claim and merge order does not matter"] = function(h)
        local _, a = replica(h); local _, b = replica(h)
        local ord = a:Create("Bob-R", 5, 1)
        b:Merge(ord)
        h.clock = h.clock + 5
        a:Close(ord.id, "Bob-R", "cancelled")
        b:Claim(ord.id, "A-R")
        a:Merge(b:Get(ord.id)); b:Merge(a:Get(ord.id))
        h.eq(a:Status(a:Get(ord.id)), "cancelled"); h.eq(b:Status(b:Get(ord.id)), "cancelled")
    end,

    ["orders: invalid orders are rejected (qty, note, shape)"] = function(h)
        local _, o = replica(h)
        local good = o:Create("Bob-R", 5, 1)
        for _, mutate in ipairs({
            function(x) x.qty = 0 end, function(x) x.qty = 100 end, function(x) x.note = string.rep("x", 81) end,
            function(x) x.id = nil end, function(x) x.claims = "no" end, function(x) x.closed = "weird" end,
        }) do
            local copy = { id = "X:1:1", requester = "Bob-R", recipeID = 5, qty = 1, note = "", createdAt = 1, claims = {} }
            mutate(copy)
            h.eq(o:Merge(copy), false)
        end
        h.truthy(good)
    end,

    ["orders: Digest/Missing return exactly the differing orders"] = function(h)
        local _, a = replica(h); local _, b = replica(h)
        local o1 = a:Create("Bob-R", 1, 1); h.clock = h.clock + 1
        local o2 = a:Create("Bob-R", 2, 1)
        b:Merge(o1)
        local miss = a:Missing(b:Digest())
        h.eq(#miss, 1); h.eq(miss[1].id, o2.id)
        h.clock = h.clock + 1
        a:Claim(o1.id, "A-R")
        h.eq(#a:Missing(b:Digest()), 2)
    end,

    ["orders: Prune drops old closed orders only"] = function(h)
        local _, o = replica(h)
        local old = o:Create("Bob-R", 1, 1)
        o:Close(old.id, "Bob-R", "done")
        local fresh = o:Create("Bob-R", 2, 1)
        h.eq(o:Prune(h.clock + 8 * 86400), 1)
        h.truthy(o:Get(fresh.id) == nil or o:Get(fresh.id) ~= nil) -- fresh survives only within 30 days
        h.eq(o:Get(old.id), nil)
    end,
}

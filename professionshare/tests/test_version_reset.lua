-- After an update, data other members sent is dropped once (mixed state from older builds broke the UI until /ps clean);
-- my own record, offers, the catalog entries of my recipes and all orders stay.
return {
    ["version reset: peer data goes, my own data and orders stay"] = function(harness)
        local addon = harness.addon()
        local S = addon.Store
        local ME, P = "Me-Realm", "Peer-Realm"
        S.PutCharacter(harness.character(ME, 10, { 100, 101 }))
        S.PutCharacter(harness.character(P, 20, { 200 }))
        S.db.catalog[100] = { name = "mine" }
        S.db.catalog[200] = { name = "theirs" }
        S.db.offers[ME] = { name = ME, rev = 1, items = {}, dibs = {} }
        S.db.offers[P] = { name = P, rev = 1, items = {}, dibs = {} }
        S.db.hidden["Peer-Realm:5"] = 1
        S.db.orders["o"] = { id = "o" }
        local chars, catalog, orders = S.db.chars, S.db.catalog, S.db.orders
        local n = S.ResetPeerData(ME)
        harness.equal(n.chars, 1); harness.equal(n.offers, 1); harness.equal(n.catalog, 1)
        harness.truthy(S.GetCharacter(ME)); harness.equal(S.GetCharacter(P), nil)
        harness.truthy(S.db.catalog[100]); harness.equal(S.db.catalog[200], nil)
        harness.truthy(S.db.offers[ME]); harness.equal(S.db.offers[P], nil)
        harness.equal(next(S.db.hidden), nil)
        harness.truthy(S.db.orders["o"])
        -- emptied in place: Orders and Sync keep their references
        harness.truthy(chars == S.db.chars and catalog == S.db.catalog and orders == S.db.orders)
    end,
}

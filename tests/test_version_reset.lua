-- After an update, data other members sent is dropped once (mixed state from older builds broke the UI until /ts clean);
-- my own record, offers, the catalog entries of my recipes and all orders stay.
return {
    ["version reset: peer data goes, my own data and orders stay"] = function(h)
        local ns = h.ns()
        local S = ns.Store
        local ME, P = "Me-Realm", "Peer-Realm"
        S.PutChar(h.char(ME, 10, { 100, 101 }))
        S.PutChar(h.char(P, 20, { 200 }))
        S.db.catalog[100] = { name = "mine" }
        S.db.catalog[200] = { name = "theirs" }
        S.db.offers[ME] = { name = ME, rev = 1, items = {}, dibs = {} }
        S.db.offers[P] = { name = P, rev = 1, items = {}, dibs = {} }
        S.db.hidden["Peer-Realm:5"] = 1
        S.db.orders["o"] = { id = "o" }
        local chars, catalog, orders = S.db.chars, S.db.catalog, S.db.orders
        local n = S.ResetPeerData(ME)
        h.eq(n.chars, 1); h.eq(n.offers, 1); h.eq(n.catalog, 1)
        h.truthy(S.GetChar(ME)); h.eq(S.GetChar(P), nil)
        h.truthy(S.db.catalog[100]); h.eq(S.db.catalog[200], nil)
        h.truthy(S.db.offers[ME]); h.eq(S.db.offers[P], nil)
        h.eq(next(S.db.hidden), nil)
        h.truthy(S.db.orders["o"])
        -- emptied in place: Orders and Sync keep their references
        h.truthy(chars == S.db.chars and catalog == S.db.catalog and orders == S.db.orders)
    end,
}

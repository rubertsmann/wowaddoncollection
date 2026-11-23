-- Games records are replaceable answers in the send queue: a newer one to the same member replaces one still waiting.
return {
    ["send queue: GAMES answers are replaceable, requests are not"] = function(harness)
        local addon = harness.addon()
        local options = addon.Communication.options
        harness.truthy(options.replaceableTypes.GAMES)
        harness.equal(options.replaceableTypes.WANTG, nil); harness.equal(options.replaceableTypes.HELLO, nil)
    end,
}

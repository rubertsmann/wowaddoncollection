-- docs/comment-policy.md: this addon's comments pass tools/comment-audit.lua --strict (no provenance in code, no dead
-- paths or Module.Name references, no ---@param that is not a parameter of its function).
return {
    ["comments: the comment audit of guildgames finds nothing"] = function(harness)
        local pipe = assert(io.popen("cd .. && luajit tools/comment-audit.lua --strict guildgames 2>&1"))
        local output = pipe:read("*a")
        pipe:close()
        harness.truthy(output:find("comment-audit guildgames: ", 1, true) and output:find(" comments, 0 findings", 1, true), output)
    end,
}

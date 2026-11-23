-- Finds comments that are wrong or do not belong in the code. Run from the repo root:
--   luajit tools/comment-audit.lua [--strict] [--summary] <addon folder> ...
-- Checks (see docs/comment-policy.md):
--   provenance   who asked for it and when ("user 2026-11-20"), feature / requirement ids: history, not code
--   path         a *.lua / *.toc path (with a "/") that exists neither in the commenting file's addon nor, for
--                "LibGuildSync/...", in libguildsync
--   member       Module.Name where Module is a table of this addon or LibGuildSync but Name is defined in neither
--   param        a ---@param that is not a parameter of the function below it
-- --strict exits with 1 when anything is found (for tests/run.lua).
-- --code-only <revision> exits with 1 when a changed Lua file differs from <revision> in more than comments/whitespace.

local VENDORED_FOLDERS = { "/Libs/", "/libs/", "/dist/", "/eval/", "/features/", "/review/" }

local function readFile(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local content = handle:read("*a")
    handle:close()
    return content
end

local function fileExists(path)
    local handle = io.open(path, "rb")
    if handle then handle:close() return true end
    return false
end

local function listLuaFiles(root)
    local command = ('git ls-files "%s"'):format(root)
    local pipe = assert(io.popen(command))
    local files = {}
    for line in pipe:lines() do
        local vendored = false
        for _, folder in ipairs(VENDORED_FOLDERS) do
            if ("/" .. line):find(folder, 1, true) then vendored = true end
        end
        if line:match("%.lua$") and not vendored then files[#files + 1] = line end
    end
    pipe:close()
    return files
end

-- Splits Lua source into comments, each { line = n, text = "...", trailing = bool }, and the code with comments blanked.
local function extractComments(source)
    local comments, codeParts = {}, {}
    local position, line, length = 1, 1, #source
    local lineHasCode = false
    local function longBracketEnd(start)
        local equals = source:match("^%[(=*)%[", start)
        if not equals then return nil end
        local closing = "]" .. equals .. "]"
        local finish = source:find(closing, start, true)
        return (finish or length) + #closing - 1, #equals + 2
    end
    while position <= length do
        local character = source:sub(position, position)
        if character == "\n" then
            line, lineHasCode = line + 1, false
            codeParts[#codeParts + 1] = character
            position = position + 1
        elseif source:sub(position, position + 1) == "--" then
            local finish, openLength = longBracketEnd(position + 2)
            local text
            if finish then
                text = source:sub(position + 2 + openLength, finish - openLength)
            else
                finish = (source:find("\n", position, true) or length + 1) - 1
                text = source:sub(position + 2, finish)
            end
            comments[#comments + 1] = { line = line, text = text, trailing = lineHasCode }
            local _, newlines = source:sub(position, finish):gsub("\n", "")
            codeParts[#codeParts + 1] = (" "):rep(0) .. ("\n"):rep(newlines)
            line = line + newlines
            position = finish + 1
        elseif character == '"' or character == "'" then
            local scan = position + 1
            while scan <= length do
                local current = source:sub(scan, scan)
                if current == "\\" then scan = scan + 2
                elseif current == character or current == "\n" then break
                else scan = scan + 1 end
            end
            codeParts[#codeParts + 1] = source:sub(position, scan)
            lineHasCode, position = true, scan + 1
        elseif character == "[" and longBracketEnd(position) then
            local finish = longBracketEnd(position)
            local chunk = source:sub(position, finish)
            local _, newlines = chunk:gsub("\n", "")
            codeParts[#codeParts + 1] = chunk
            line, lineHasCode, position = line + newlines, true, finish + 1
        else
            if not character:match("%s") then lineHasCode = true end
            codeParts[#codeParts + 1] = character
            position = position + 1
        end
    end
    return comments, table.concat(codeParts)
end

local PROVENANCE_PATTERNS = {
    "user %d%d%d%d%-%d%d%-%d%d", "[Ss]pike S%d", "%(user[ ,%)]", "[Ff]eature %d%d%d", "%f[%w]RF?%d+%f[%W]", "%f[%w]T%d+%f[%W]",
}

local function pathExists(path, addonRoot)
    if fileExists(path) or fileExists(addonRoot .. "/" .. path) then return true end
    -- "LibGuildSync/X.lua" means the library; any other path must exist in the commenting file's own addon
    if path:match("^LibGuildSync/") then return fileExists("libguildsync/" .. path) end
    return false
end

local function audit(root)
    local files = listLuaFiles(root)
    local nameSources = listLuaFiles("libguildsync")
    local findings, commentCount, codeByFile = {}, 0, {}
    local function add(file, line, kind, message) findings[#findings + 1] = { file = file, line = line, kind = kind, message = message } end
    local parsed = {}
    for _, file in ipairs(files) do
        local source = readFile(file) or ""
        local comments, code = extractComments(source)
        parsed[file] = { comments = comments, source = source }
        codeByFile[file] = code
        commentCount = commentCount + #comments
    end
    local allCode = {}
    for _, code in pairs(codeByFile) do allCode[#allCode + 1] = code end
    for _, file in ipairs(nameSources) do
        if not codeByFile[file] then
            local _, code = extractComments(readFile(file) or "")
            allCode[#allCode + 1] = code
        end
    end
    allCode = table.concat(allCode, "\n")
    local definedNames = {}
    for name in allCode:gmatch("[%.:]([%a_][%w_]*)%s*=") do definedNames[name] = true end
    -- multiple assignment ("Module.A, Module.B = 1, 2"): every name left of the "="
    for targets in allCode:gmatch("%f[^\n%z]%s*([%w_%.:]+%s*,[%w_%.:%s,]+)=[^=]") do
        for name in targets:gmatch("[%.:]([%a_][%w_]*)") do definedNames[name] = true end
    end
    for name in allCode:gmatch("function%s+[%w_%.:]-([%a_][%w_]*)%s*%(") do definedNames[name] = true end
    for name in allCode:gmatch("local%s+([%a_][%w_]*)") do definedNames[name] = true end
    for name in allCode:gmatch("[{,]%s*([%a_][%w_]*)%s*=") do definedNames[name] = true end
    local moduleNames = {}
    for module in allCode:gmatch("addon%.([%u][%w_]*)%s*=") do moduleNames[module] = true end
    for module in allCode:gmatch("library%.([%u][%w_]*)%s*=") do moduleNames[module] = true end
    for module in allCode:gmatch("lib%.([%u][%w_]*)%s*=") do moduleNames[module] = true end
    for module in allCode:gmatch("local%s+([%u][%w_]*)%s*=%s*{}") do moduleNames[module] = true end

    for _, file in ipairs(files) do
        local entry = parsed[file]
        local sourceLines = {}
        for sourceLine in (entry.source .. "\n"):gmatch("([^\n]*)\n") do sourceLines[#sourceLines + 1] = sourceLine end
        local isTest = file:find("/tests/", 1, true) ~= nil
        for _, comment in ipairs(entry.comments) do
            local text = comment.text
            if not isTest then
                for _, pattern in ipairs(PROVENANCE_PATTERNS) do
                    local match = text:match(pattern)
                    if match then add(file, comment.line, "provenance", match) break end
                end
            end
            for path in text:gmatch("([%w_%-/%.]+%.[lt][uo][ac])%f[^%w]") do
                if path:find("/", 1, true) and not path:match("^%.%./") then
                    if not pathExists(path, file:match("^([^/]+)/")) then add(file, comment.line, "path", path) end
                end
            end
            if not text:match("^%-@") then
                for module, member in text:gmatch("%f[%w_]([%u][%w_]*)%.([%a_][%w_]*)") do
                    local isFileName = member == "lua" or member == "toc" or member == "md" or member == "xml"
                    if moduleNames[module] and not isFileName and not definedNames[member] then add(file, comment.line, "member", module .. "." .. member) end
                end
            end
            local paramName = text:match("^%-@param%s+([%w_%.]+)")
            if paramName and paramName ~= "..." then
                for scan = comment.line + 1, math.min(#sourceLines, comment.line + 40) do
                    local parameters = sourceLines[scan]:match("function[^%(]*%(([^%)]*)%)")
                    if parameters then
                        local found = false
                        for parameter in parameters:gmatch("[%w_%.]+") do
                            if parameter == paramName:gsub("%?$", "") then found = true end
                        end
                        if not found then add(file, comment.line, "param", paramName .. " not in (" .. parameters .. ")") end
                        break
                    end
                    if not sourceLines[scan]:match("^%s*%-%-") then break end
                end
            end
        end
    end
    return findings, #files, commentCount
end

-- --code-only <git revision>: proves that the Lua files changed since <revision> differ only in comments and whitespace
-- (tools/ is left out: this tool itself changes code).
local function codeOnly(revision)
    local pipe = assert(io.popen(('git diff --name-only "%s" -- "*.lua" ":!tools"'):format(revision)))
    local changed = 0
    for file in pipe:lines() do
        local before = assert(io.popen(('git show "%s:%s" 2>nul'):format(revision, file))):read("*a")
        local after = readFile(file) or ""
        local _, beforeCode = extractComments(before)
        local _, afterCode = extractComments(after)
        local function squeeze(code) return (code:gsub("%s+", " ")) end
        if before ~= "" and squeeze(beforeCode) ~= squeeze(afterCode) then
            print("CODE CHANGED: " .. file)
            changed = changed + 1
        end
    end
    pipe:close()
    print(("comment-audit --code-only %s: %d file(s) with code changes"):format(revision, changed))
    os.exit(changed == 0 and 0 or 1)
end

local strict, summary, roots = false, false, {}
for index, argument in ipairs(arg) do
    if argument == "--code-only" then codeOnly(arg[index + 1]) end
    if argument == "--strict" then strict = true
    elseif argument == "--summary" then summary = true
    else roots[#roots + 1] = argument end
end
if #roots == 0 then roots = { "." } end
local total = 0
for _, root in ipairs(roots) do
    local findings, fileCount, commentCount = audit(root)
    local byKind = {}
    for _, finding in ipairs(findings) do
        byKind[finding.kind] = (byKind[finding.kind] or 0) + 1
        if not summary then print(("%s:%d: [%s] %s"):format(finding.file, finding.line, finding.kind, finding.message)) end
    end
    local kinds = {}
    for kind, count in pairs(byKind) do kinds[#kinds + 1] = kind .. "=" .. count end
    table.sort(kinds)
    print(("comment-audit %s: %d files, %d comments, %d findings %s"):format(root, fileCount, commentCount, #findings,
        table.concat(kinds, " ")))
    total = total + #findings
end
if strict and total > 0 then os.exit(1) end

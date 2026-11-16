local ADDON, ns = ...

local U = {}
ns.Util = U

-- "Bob" + "Area 52" -> "Bob-Area52"; names that already contain a realm are returned untouched.
function U.FullName(name, realm)
    if type(name) ~= "string" or name == "" then return nil end
    if name:find("-", 1, true) then return name end
    realm = realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or ""
    realm = (realm:gsub("%s", ""))
    if realm == "" then return name end
    return name .. "-" .. realm
end

function U.DeepCopy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = U.DeepCopy(v) end
    return c
end

function U.Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function U.Now()
    if GetServerTime then return GetServerTime() end
    return time()
end

-- Debug ring buffer persisted in SavedVariables (readable after /reload for offline verification).
ns.Debug = {}
function ns.Debug.Log(tag, ...)
    if not ns.db then return end
    local parts = { tostring(tag) }
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local log = ns.db.debug
    log[#log + 1] = U.Now() .. " " .. table.concat(parts, " ")
    while #log > 200 do table.remove(log, 1) end
end

function U.ReportError(err)
    if geterrorhandler then geterrorhandler()(err) else print(err) end
end

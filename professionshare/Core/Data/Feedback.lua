local addonName, addon = ...

-- Feedback, feature requests and bug reports for the addon developer. Pure Lua: the UI side is the Feedback tab in
-- UI/Window.lua.
--
-- One record per character, authored ONLY by that character and replaced as a whole by the newer `rev` (like an access
-- record). Its revision rides in HELLO (`frev`), but only the developer's client pulls and stores other members' records
-- (Feedback.IsReader); every other client keeps just its own. Nothing is relayed: a message reaches the developer when
-- both are online at the same time and waits in the sender's record until then. Not a secret: the text travels as a
-- normal addon message, so anyone with their own code could read it off the wire.
-- The status the developer gives a message (declined / answered / fixed) stays on the developer's client.
-- The field names are the wire and saved-data format and stay as they are.

---@class FeedbackItem
---@field t integer when it was sent (server time); unique within the record
---@field k string type: "feedback" | "feature" | "bug"
---@field text string the player's words
---@field log string|nil diagnostic snapshot taken when it was sent (lines joined by "\n")

---@class FeedbackRecord
---@field name string the owner, canonical name
---@field rev integer revision: the newer one wins
---@field items FeedbackItem[] oldest first

---@class FeedbackModule
local Feedback = {}
addon.Feedback = Feedback

Feedback.TYPES = { "feedback", "feature", "bug" }
Feedback.MAXIMUM_ITEMS = 10
Feedback.MAXIMUM_TEXT_BYTES = 300
Feedback.MAXIMUM_LOG_BYTES = 1200
-- only this many of the newest messages keep their diagnostic snapshot (keeps the record small)
Feedback.MAXIMUM_LOGS = 3
Feedback.STATUSES = { "declined", "answered", "fixed" }

local TYPE_KNOWN, STATUS_KNOWN = {}, {}
for _, feedbackType in ipairs(Feedback.TYPES) do TYPE_KNOWN[feedbackType] = true end
for _, status in ipairs(Feedback.STATUSES) do STATUS_KNOWN[status] = true end

---@param feedbackType any
---@return boolean
function Feedback.IsType(feedbackType) return TYPE_KNOWN[feedbackType] == true end

---@return table
local function database() return addon.Store.db end

-- Whether this client reads other members' feedback: the developer's character (the same name hash as the member
-- builds button, so no real name is in the code) or a development build.
---@param myName any
---@return boolean
function Feedback.IsReader(myName)
    if addon.IS_DEVELOPMENT_BUILD then return true end
    return addon.Model.IsBuildViewer(myName)
end

-- Whether a reader (the developer's character) is in `roster` (name -> true): only then can my messages be delivered.
---@param roster table<string, boolean>|nil
---@return boolean
function Feedback.ReaderInRoster(roster)
    for playerName in pairs(type(roster) == "table" and roster or {}) do
        if addon.Model.IsBuildViewer(playerName) then return true end
    end
    return false
end

------------------------------------------------------------------ text

-- The player's text as it is sent: line breaks become " / ", control characters go, surrounding spaces go, cut to
-- MAXIMUM_TEXT_BYTES without splitting a character. nil when nothing is left or it is not UTF-8.
---@param text any
---@return string|nil
function Feedback.CleanText(text)
    local Utility = addon.Utility
    if type(text) ~= "string" or not Utility.IsValidUtf8(text) then return nil end
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\r\n]*)[\r\n]") do
        line = Utility.StripControlCharacters(line):match("^%s*(.-)%s*$")
        if line ~= "" then lines[#lines + 1] = line end
    end
    text = Utility.TruncateUtf8(table.concat(lines, " / "), Feedback.MAXIMUM_TEXT_BYTES)
    if text == "" then return nil end
    return text
end

------------------------------------------------------------------ validation (network and persisted data)

---@param log any
---@return string|nil|false the clean snapshot, nil when absent, false when invalid
local function cleanLog(log)
    if log == nil then return nil end
    if type(log) ~= "string" or #log > Feedback.MAXIMUM_LOG_BYTES then return false end
    if not addon.Utility.CleanString(log:gsub("\n", ""), Feedback.MAXIMUM_LOG_BYTES) then return false end
    return log
end

-- Returns a CLEAN COPY of a feedback record or nil. A single bad entry rejects the whole record.
---@param feedbackRecord any
---@return FeedbackRecord|nil
function Feedback.Sanitize(feedbackRecord)
    local Utility = addon.Utility
    if type(feedbackRecord) ~= "table" or not Utility.IsSafeName(feedbackRecord.name) then return nil end
    local horizon = addon.Store.Horizon()
    local revision = Utility.SafeInteger(feedbackRecord.rev, 0, horizon)
    if not revision or type(feedbackRecord.items) ~= "table" then return nil end
    local itemCount = Utility.Count(feedbackRecord.items)
    if itemCount > Feedback.MAXIMUM_ITEMS or #feedbackRecord.items ~= itemCount then return nil end
    local items, seenTimes, logCount = {}, {}, 0
    for index, item in ipairs(feedbackRecord.items) do
        if type(item) ~= "table" then return nil end
        local sentAt = Utility.SafeInteger(item.t, 1, horizon)
        local text = Utility.CleanString(item.text, Feedback.MAXIMUM_TEXT_BYTES)
        local log = cleanLog(item.log)
        if not sentAt or seenTimes[sentAt] or not TYPE_KNOWN[item.k] or not text or text == "" or log == false then return nil end
        if log then logCount = logCount + 1 end
        seenTimes[sentAt] = true
        items[index] = { t = sentAt, k = item.k, text = text, log = log }
    end
    if logCount > Feedback.MAXIMUM_LOGS then return nil end
    return { name = feedbackRecord.name, rev = revision, items = items }
end

------------------------------------------------------------------ store access

---@param playerName string
---@return FeedbackRecord|nil
function Feedback.Get(playerName) return database().feedback[playerName] end

-- Stores a peer's record only on a reader's client and only if it is newer than what is held. Returns true when stored.
---@param feedbackRecord FeedbackRecord
---@param myName string|nil
---@return boolean
function Feedback.Put(feedbackRecord, myName)
    if type(feedbackRecord) ~= "table" or type(feedbackRecord.name) ~= "string" then return false end
    if feedbackRecord.name ~= myName and not Feedback.IsReader(myName) then return false end
    local storedRecord = database().feedback[feedbackRecord.name]
    if storedRecord and (storedRecord.rev or 0) >= (feedbackRecord.rev or 0) then return false end
    database().feedback[feedbackRecord.name] = feedbackRecord
    return true
end

-- Re-validates persisted records and statuses (SavedVariables are untrusted on load). Returns the number dropped.
---@param savedVariables table
---@return integer droppedCount
function Feedback.SanitizePersisted(savedVariables)
    local Utility = addon.Utility
    local feedbackRecords, droppedCount = Utility.SanitizeMap(savedVariables.feedback, Feedback.Sanitize,
        function(playerName, clean) return clean.name == playerName end)
    savedVariables.feedback = feedbackRecords
    local states = {}
    for messageKey, status in pairs(type(savedVariables.feedbackState) == "table" and savedVariables.feedbackState or {}) do
        if type(messageKey) == "string" and #messageKey <= 100 and STATUS_KNOWN[status] then states[messageKey] = status
        else droppedCount = droppedCount + 1 end
    end
    savedVariables.feedbackState = states
    local delivered = {}
    for sentAt, isDelivered in pairs(type(savedVariables.feedbackDelivered) == "table" and savedVariables.feedbackDelivered or {}) do
        if Utility.SafeInteger(sentAt, 1, 2147483647) and isDelivered == true then delivered[sentAt] = true
        else droppedCount = droppedCount + 1 end
    end
    savedVariables.feedbackDelivered = delivered
    return droppedCount
end

------------------------------------------------------------------ my record

---@alias FeedbackRefusal "type"|"empty"|"duplicate"

-- Adds a message to my record (the oldest goes beyond MAXIMUM_ITEMS; only the newest MAXIMUM_LOGS keep a snapshot).
-- Returns true, or false and why it was refused.
---@param myName string
---@param feedbackType string
---@param text any
---@param now integer
---@param log string|nil diagnostic snapshot (Feedback.Snapshot)
---@return boolean added
---@return FeedbackRefusal|nil refusal
function Feedback.Add(myName, feedbackType, text, now, log)
    if type(myName) ~= "string" or not TYPE_KNOWN[feedbackType] then return false, "type" end
    local cleanText = Feedback.CleanText(text)
    if not cleanText then return false, "empty" end
    local Utility = addon.Utility
    local previousRecord = database().feedback[myName]
    local feedbackRecord = previousRecord and Utility.DeepCopy(previousRecord) or { name = myName, rev = 0, items = {} }
    local lastItem = feedbackRecord.items[#feedbackRecord.items]
    if lastItem and lastItem.text == cleanText and lastItem.k == feedbackType then return false, "duplicate" end
    local sentAt = math.max(now, lastItem and lastItem.t + 1 or now)
    local cleanSnapshot = cleanLog(type(log) == "string" and Utility.TruncateUtf8(log, Feedback.MAXIMUM_LOG_BYTES) or nil)
    table.insert(feedbackRecord.items, { t = sentAt, k = feedbackType, text = cleanText, log = cleanSnapshot or nil })
    while #feedbackRecord.items > Feedback.MAXIMUM_ITEMS do table.remove(feedbackRecord.items, 1) end
    local logCount = 0
    for index = #feedbackRecord.items, 1, -1 do
        local item = feedbackRecord.items[index]
        if item.log then
            logCount = logCount + 1
            if logCount > Feedback.MAXIMUM_LOGS then item.log = nil end
        end
    end
    feedbackRecord.rev = math.max(now, (previousRecord and previousRecord.rev or 0) + 1)
    database().feedback[myName] = feedbackRecord
    return true
end

-- My client answers a request for my record: only a reader asks for it, so every message in that record counts as
-- delivered to the developer. Marks are kept only for messages still in my record.
---@param feedbackRecord FeedbackRecord the record being answered with
function Feedback.MarkDelivered(feedbackRecord)
    if type(feedbackRecord) ~= "table" or type(feedbackRecord.items) ~= "table" then return end
    local delivered, inRecord = database().feedbackDelivered, {}
    for _, item in ipairs(feedbackRecord.items) do
        inRecord[item.t] = true
        delivered[item.t] = true
    end
    for sentAt in pairs(delivered) do
        if not inRecord[sentAt] then delivered[sentAt] = nil end
    end
end

---@class MyFeedbackRow
---@field t integer
---@field k string
---@field text string
---@field delivered boolean the developer's client has asked for it

---@class MyFeedbackSummary
---@field rows MyFeedbackRow[] newest first
---@field sent integer messages in my record
---@field delivered integer of those, delivered
---@field waiting integer of those, not delivered yet

-- my own messages and how many of them reached the developer
---@param myName string|nil
---@return MyFeedbackSummary
function Feedback.MySummary(myName)
    local summary = { rows = {}, sent = 0, delivered = 0, waiting = 0 }
    local feedbackRecord = myName and database().feedback[myName]
    if not feedbackRecord then return summary end
    local delivered = database().feedbackDelivered
    for index = #feedbackRecord.items, 1, -1 do
        local item = feedbackRecord.items[index]
        local isDelivered = delivered[item.t] == true
        summary.rows[#summary.rows + 1] = { t = item.t, k = item.k, text = item.text, delivered = isDelivered }
        summary.sent = summary.sent + 1
        if isDelivered then summary.delivered = summary.delivered + 1 else summary.waiting = summary.waiting + 1 end
    end
    return summary
end

---@param myName string|nil
---@return integer messages of mine kept in my record
function Feedback.MyCount(myName)
    local feedbackRecord = myName and database().feedback[myName]
    return feedbackRecord and #feedbackRecord.items or 0
end

------------------------------------------------------------------ diagnostic snapshot (bug reports)

---@class FeedbackSnapshotContext
---@field version string|nil
---@field protocol string|nil "2.5"
---@field schema integer|nil
---@field locale string|nil
---@field client string|nil client build text
---@field sync string|nil one line of sync state
---@field logLines string[]|nil the stored log lines, oldest first

local PROBLEM_LEVELS = { "ERROR", "WARNING" }
local MAXIMUM_LINE_BYTES = 180
local PROBLEM_LINE_COUNT, RECENT_LINE_COUNT = 6, 4

---@param line string
---@return boolean
local function isProblemLine(line)
    for _, level in ipairs(PROBLEM_LEVELS) do
        if line:find(" " .. level .. " [", 1, true) then return true end
    end
    return false
end

-- A short diagnostic text for a bug report: versions, sync state, the newest ERROR/WARNING log lines and the last few
-- lines of any level. Lines are cut to MAXIMUM_LINE_BYTES; the whole snapshot to MAXIMUM_LOG_BYTES (whole lines only).
---@param context FeedbackSnapshotContext
---@return string
function Feedback.Snapshot(context)
    local Utility = addon.Utility
    context = type(context) == "table" and context or {}
    local function clean(text)
        text = Utility.StripControlCharacters(tostring(text or "?"))
        if not Utility.IsValidUtf8(text) then text = text:gsub("[\128-\255]", "?") end
        return Utility.TruncateUtf8(text, MAXIMUM_LINE_BYTES)
    end
    local lines = {
        clean(("v%s protocol %s schema %s locale %s client %s"):format(tostring(context.version), tostring(context.protocol),
            tostring(context.schema), tostring(context.locale), tostring(context.client))),
    }
    if context.sync then lines[#lines + 1] = clean(context.sync) end
    local logLines = type(context.logLines) == "table" and context.logLines or {}
    local chosen, chosenIndex = {}, {}
    local problemCount = 0
    for index = #logLines, 1, -1 do
        if problemCount >= PROBLEM_LINE_COUNT then break end
        if type(logLines[index]) == "string" and isProblemLine(logLines[index]) then
            problemCount = problemCount + 1
            chosenIndex[index] = true
        end
    end
    for index = #logLines, math.max(1, #logLines - RECENT_LINE_COUNT + 1), -1 do
        if type(logLines[index]) == "string" then chosenIndex[index] = true end
    end
    for index = 1, #logLines do
        if chosenIndex[index] then chosen[#chosen + 1] = clean(logLines[index]) end
    end
    -- the newest lines matter most: drop from the oldest chosen line until it fits
    local function totalBytes()
        local total = 0
        for _, line in ipairs(lines) do total = total + #line + 1 end
        for _, line in ipairs(chosen) do total = total + #line + 1 end
        return total
    end
    while #chosen > 0 and totalBytes() > Feedback.MAXIMUM_LOG_BYTES do table.remove(chosen, 1) end
    for _, line in ipairs(chosen) do lines[#lines + 1] = line end
    return Utility.TruncateUtf8(table.concat(lines, "\n"), Feedback.MAXIMUM_LOG_BYTES)
end

------------------------------------------------------------------ the developer's list

---@param owner string
---@param sentAt integer
---@return string
function Feedback.MessageKey(owner, sentAt) return owner .. "#" .. tostring(sentAt) end

---@param messageKey string
---@return string|nil status
function Feedback.GetStatus(messageKey) return database().feedbackState[messageKey] end

-- Sets the status; the same status again (or nil) clears it. Returns the new status.
---@param messageKey string
---@param status string|nil
---@return string|nil
function Feedback.SetStatus(messageKey, status)
    if type(messageKey) ~= "string" then return nil end
    if status == nil or not STATUS_KNOWN[status] or database().feedbackState[messageKey] == status then
        database().feedbackState[messageKey] = nil
    else
        database().feedbackState[messageKey] = status
    end
    return database().feedbackState[messageKey]
end

---@class FeedbackRow
---@field key string Feedback.MessageKey
---@field owner string
---@field t integer
---@field k string
---@field text string raw (escape before display)
---@field log string|nil raw (escape before display)
---@field status string|nil

-- every held message, newest first
---@return FeedbackRow[]
function Feedback.List()
    local rows = {}
    for owner, feedbackRecord in pairs(database().feedback) do
        for _, item in ipairs(feedbackRecord.items) do
            local messageKey = Feedback.MessageKey(owner, item.t)
            rows[#rows + 1] = { key = messageKey, owner = owner, t = item.t, k = item.k, text = item.text, log = item.log,
                status = database().feedbackState[messageKey] }
        end
    end
    table.sort(rows, function(left, right)
        if left.t ~= right.t then return left.t > right.t end
        return left.owner < right.owner
    end)
    return rows
end

-- counts for the diagnostics: records held, messages held
---@return integer recordCount
---@return integer messageCount
function Feedback.Counts()
    local messageCount = 0
    for _, feedbackRecord in pairs(database().feedback) do messageCount = messageCount + #feedbackRecord.items end
    return addon.Utility.Count(database().feedback), messageCount
end

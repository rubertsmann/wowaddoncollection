local addonName, addon = ...

-- A panel next to the open mailbox while the mail queue has jobs: every queued mail with what the bags hold for it and
-- what is missing, and per mail Fill (fills the Send Mail form; the player sends), Done (takes what is attached off the
-- job; nothing attached removes it) and Delete. A status line on top says how many mails can be filled now.
---@class MailPanelModule
local MailPanel = {}
addon.MailPanel = MailPanel

local Text, Format = addon.Text, addon.Locale.Format
local Widgets = LibStub("LibGuildSync-1.0").Widgets

local MAXIMUM_ROWS = 8
local ROW_HEIGHT, PANEL_WIDTH = 38, 340

---@type table|nil
local panel

---@param parent table
---@param index integer
---@return table row
local function createRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(PANEL_WIDTH - 20, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 10, -48 - (index - 1) * ROW_HEIGHT)
    row.highlight = row:CreateTexture(nil, "BACKGROUND"); row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(0.2, 0.8, 0.4, 0.15)
    row.title = Widgets.CreateFontString(row, "GameFontHighlightSmall")
    row.title:SetPoint("TOPLEFT", 2, -3); row.title:SetPoint("RIGHT", -150, 0); row.title:SetJustifyH("LEFT")
    if row.title.SetWordWrap then row.title:SetWordWrap(false) end
    row.detail = Widgets.CreateFontString(row, "GameFontDisableSmall")
    row.detail:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3); row.detail:SetPoint("RIGHT", -150, 0); row.detail:SetJustifyH("LEFT")
    if row.detail.SetWordWrap then row.detail:SetWordWrap(false) end
    local MailSender = addon.MailSender
    row.deleteButton = Widgets.CreateButton(row, Text["Delete"], 48, 20, function() if row.jobID then MailSender.Remove(row.jobID) end end)
    row.deleteButton:SetPoint("RIGHT", 0, 0)
    row.doneButton = Widgets.CreateButton(row, Text["Done"], 46, 20, function() if row.jobID then MailSender.Done(row.jobID) end end)
    row.doneButton:SetPoint("RIGHT", row.deleteButton, "LEFT", -2, 0)
    row.fillButton = Widgets.CreateButton(row, Text["Fill"], 46, 20, function()
        if not row.jobID then return end
        local started, reason = MailSender.FillJob(row.jobID)
        if not started and reason == "notEmpty" then addon.Print(Text["The mail form holds other items: take them out first."])
        elseif not started and reason == "nothingInBags" then addon.Print(Text["Nothing in your bags for this mail."]) end
    end)
    row.fillButton:SetPoint("RIGHT", row.doneButton, "LEFT", -2, 0)
    return row
end

local function build()
    if panel or type(MailFrame) ~= "table" then return end
    panel = Widgets.CreateDialogFrame(nil, addon.Log)
    panel:SetParent(MailFrame)
    panel:SetWidth(PANEL_WIDTH)
    panel:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 4, 0)
    panel:SetFrameStrata("HIGH")
    panel.title = Widgets.CreateFontString(panel, "GameFontNormal")
    panel.title:SetPoint("TOP", 0, -6)
    panel.statusText = Widgets.CreateFontString(panel, "GameFontHighlightSmall")
    panel.statusText:SetPoint("TOPLEFT", 12, -28); panel.statusText:SetPoint("RIGHT", -12, 0); panel.statusText:SetJustifyH("LEFT")
    panel.rows = {}
    for index = 1, MAXIMUM_ROWS do panel.rows[index] = createRow(panel, index) end
    panel.moreText = Widgets.CreateFontString(panel, "GameFontDisableSmall")
    panel.moreText:SetJustifyH("LEFT")
    panel.listButton = Widgets.CreateButton(panel, Text["Mail tab"], 80, 20, function()
        if addon.UI.Show then addon.UI.Show() end
        addon.UI.SelectTab("mail")
    end)
end

-- "2 ready, 1 missing" style counts for one job: what the bags hold toward it and what they lack
---@param job MailJob
---@param held table<integer, integer> mailable bag counts, shared by the jobs in queue order
---@return integer ready
---@return integer missing
local function jobCounts(job, held)
    local ready, missing = 0, 0
    for itemID, amount in pairs(job.items) do
        local have = math.min(held[itemID] or 0, amount)
        ready, missing = ready + have, missing + (amount - have)
        held[itemID] = (held[itemID] or 0) - have
    end
    return ready, missing
end

function MailPanel.Refresh()
    local MailSender = addon.MailSender
    local mailQueue = MailSender and MailSender.Queue()
    local jobs = mailQueue and mailQueue:List() or {}
    if not MailSender or not MailSender.MailboxOpen() or #jobs == 0 then
        if panel then panel:Hide() end
        return
    end
    build()
    if not panel then return end
    local held = MailSender.MailableCounts()
    local rows = addon.Model.BuildMailRows(jobs, MailSender.MailableCounts(), addon.Api.ItemName,
        MailSender.current and MailSender.current.jobID, addon.Store)
    local fillable, itemsReady, itemsMissing = 0, 0, 0
    for index, job in ipairs(jobs) do
        local ready, missing = jobCounts(job, held)
        itemsReady, itemsMissing = itemsReady + ready, itemsMissing + missing
        if ready > 0 then fillable = fillable + 1 end
        local row, viewRow = panel.rows[index], rows[index]
        if row then
            row.jobID = job.id
            local modeText = job.mode == "mats" and Text["Mats"] or Text["Item"]
            row.title:SetText(("|cffffd100%s|r %s: %dx %s"):format(modeText,
                Format(Text["to {name}"], { name = addon.Utility.ShortName(job.recipient) }), viewRow.qty, viewRow.label))
            local detail = Format(Text["{ready} ready, {missing} missing"], { ready = ready, missing = missing })
            if viewRow.missingText ~= "" then detail = detail .. " |cffff7777(" .. viewRow.missingText .. ")|r" end
            row.detail:SetText(detail)
            row.highlight:SetShown(viewRow.isCurrent)
            row.fillButton:SetEnabled(ready > 0 and MailSender.state ~= "filling")
            row:Show()
        end
    end
    for index = #jobs + 1, MAXIMUM_ROWS do panel.rows[index]:Hide(); panel.rows[index].jobID = nil end
    local shownRows = math.min(#jobs, MAXIMUM_ROWS)
    panel.title:SetText(Format(Text["ProfessionShare mail queue ({n})"], { n = #jobs }))
    panel.statusText:SetText(Format(Text["{fillable} of {n} mails can be filled now; items: {ready} in your bags, {missing} missing."],
        { fillable = fillable, n = #jobs, ready = itemsReady, missing = itemsMissing }) .. "\n" .. (addon.UI.MailStatusText and addon.UI.MailStatusText() or ""))
    panel.moreText:ClearAllPoints(); panel.moreText:SetPoint("TOPLEFT", 12, -52 - shownRows * ROW_HEIGHT)
    panel.moreText:SetText(#jobs > MAXIMUM_ROWS and Format(Text["{n} more on the Mail tab."], { n = #jobs - MAXIMUM_ROWS }) or "")
    panel.listButton:ClearAllPoints(); panel.listButton:SetPoint("BOTTOMRIGHT", -10, 10)
    panel:SetHeight(48 + shownRows * ROW_HEIGHT + 44)
    panel:Show()
end

if addon.Events then addon.Events.On("DATA_CHANGED", function() MailPanel.Refresh() end) end

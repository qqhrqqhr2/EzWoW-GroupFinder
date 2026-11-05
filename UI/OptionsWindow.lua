--===========================================================================
-- EzWoW - Group Finder
-- UI/OptionsWindow.lua : EzWoW Style Settings Window, Blizzard Launcher & Slash
--===========================================================================
local _, ns = ...
local type, pairs, ipairs, tonumber, tostring, pcall = type, pairs, ipairs, tonumber, tostring, pcall

local UIKit = ns.UIKit
local configFrame, optionsPanel, copyBox

local function rgba(c) return c[1], c[2], c[3], c[4] or 1 end

-----------------------------------------------------------------------------
-- Donate Copy Modal
-----------------------------------------------------------------------------
local function showDonatePopup()
    local S = ns.Style
    if not copyBox then
        copyBox = CreateFrame("Frame", "EzWoWGroupFinderDonate", UIParent, "BackdropTemplate")
        copyBox:SetSize(390, 116)
        copyBox:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        UIKit:ApplyBackdrop(copyBox)
        copyBox:SetBackdropColor(S.bgPrimary[1], S.bgPrimary[2], S.bgPrimary[3], 0.98)
        copyBox:SetBackdropBorderColor(rgba(S.accent))

        copyBox.label = copyBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        copyBox.label:SetPoint("TOP", 0, -14)
        copyBox.label:SetTextColor(rgba(S.accent))

        local box, edit = UIKit:CreateEditBox(copyBox, 346, 27)
        box:SetPoint("TOP", 0, -43)
        box:SetFrameLevel(copyBox:GetFrameLevel() + 5)
        edit:SetText(ns.DONATE_URL)
        edit:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
        edit:SetScript("OnEscapePressed", function() copyBox:Hide() end)
        edit:SetScript("OnEnterPressed", function() copyBox:Hide() end)
        edit:SetScript("OnTextChanged", function(self, userInput) if userInput then self:SetText(ns.DONATE_URL) self:HighlightText() end end)
        copyBox.edit = edit

        local close = UIKit:CreateCloseButton(copyBox, function() copyBox:Hide() end)
        close:SetPoint("TOPRIGHT", -6, -6)
    end
    copyBox.label:SetText(ns:L("copy"))
    UIKit:ElevateModal(copyBox, 260)
    copyBox:Show()
    copyBox.edit:SetFocus()
    copyBox.edit:HighlightText()
end

-----------------------------------------------------------------------------
-- Settings Window (EzWoWGroupFinderConfig)
-----------------------------------------------------------------------------
local function blockedCount()
    local n = 0
    for _ in pairs(ns.db.blocked) do n = n + 1 end
    return n
end

function ns:ToggleOptions()
    if not self.db then return end
    if configFrame then
        configFrame:SetShown(not configFrame:IsShown())
        if configFrame:IsShown() then configFrame:Raise() end
        return
    end

    local S = ns.Style
    local db = self.db
    configFrame = CreateFrame("Frame", "EzWoWGroupFinderConfig", UIParent, "BackdropTemplate")
    configFrame:SetSize(420, 692)
    configFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    configFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    configFrame:SetToplevel(true)
    configFrame:SetClampedToScreen(true)
    configFrame:SetMovable(true)
    configFrame:EnableMouse(true)
    if UISpecialFrames then tinsert(UISpecialFrames, "EzWoWGroupFinderConfig") end
    UIKit:ApplyBackdrop(configFrame, 1, 1)
    configFrame:SetBackdropColor(rgba(S.bgPrimary))
    configFrame:SetBackdropBorderColor(rgba(S.border))

    local top = UIKit:CreateHeader(configFrame, ns.TITLE)
    top.subtitle:SetWidth(320)
    local close = UIKit:CreateCloseButton(top, function() configFrame:Hide() end)
    close:SetPoint("TOPRIGHT", top, "TOPRIGHT", -10, -10)

    local headings = {}
    local function section(key, y)
        local t = UIKit:CreateSectionLabel(configFrame, 20, y)
        local line = configFrame:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(S.border[1], S.border[2], S.border[3], 0.85)
        line:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 20, y - 20)
        line:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -20, y - 20)
        line:SetHeight(1)
        headings[#headings + 1] = { fs = t, key = key }
    end

    local checks = {}
    local function option(dbKey, labelKey, y, onChange)
        local c, t = UIKit:CreateCheck(configFrame, function(value)
            db[dbKey] = value
            if onChange then onChange(value) end
            ns.RefreshMainWindow()
        end)
        c:SetPoint("TOPLEFT", 20, y)
        checks[#checks + 1] = { check = c, label = t, dbKey = dbKey, labelKey = labelKey }
    end

    -- 1. Collect
    section("secCollect", -70)
    option("collectChannel", "optChannels", -94)
    option("collectSay", "optSay", -120)
    option("collectGuild", "optGuild", -146)
    option("autoJoinLFG", "optAutoJoin", -172, function() ns.EnsureLFGChannel(true) end)

    local joinLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    joinLabel:SetPoint("TOPLEFT", 24, -206)
    joinLabel:SetJustifyH("LEFT")
    local joinBox, joinEdit = UIKit:CreateEditBox(configFrame, 376, 26, function() return ns:L("joinPlaceholder") end)
    joinBox:SetPoint("TOPLEFT", 22, -226)
    joinEdit:SetMaxLetters(120)
    local function saveChannels(self)
        local text = self:GetText() or ""
        if text ~= db.joinChannels then
            db.joinChannels = text
            ns.EnsureLFGChannel()
        end
        self:ClearFocus()
    end
    joinEdit:SetScript("OnEnterPressed", saveChannels)
    joinEdit:HookScript("OnEditFocusLost", function(self)
        if (self:GetText() or "") ~= db.joinChannels then
            db.joinChannels = self:GetText() or ""
            ns.EnsureLFGChannel()
        end
    end)
    local joinHint = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    joinHint:SetPoint("TOPLEFT", 24, -258)
    joinHint:SetWidth(372)
    joinHint:SetJustifyH("LEFT")
    joinHint:SetTextColor(rgba(S.textMuted))

    local expireLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    expireLabel:SetPoint("TOPLEFT", 24, -296)
    expireLabel:SetJustifyH("LEFT")
    local minus = UIKit:CreateButton(configFrame, 27, 27, "-", false, "GameFontNormalLarge")
    minus:SetPoint("TOPLEFT", 250, -289)
    local expireValue = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    expireValue:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    expireValue:SetWidth(50)
    local plus = UIKit:CreateButton(configFrame, 27, 27, "+", false, "GameFontNormalLarge")
    plus:SetPoint("LEFT", minus, "RIGHT", 58, 0)

    -- 2. Display
    section("secView", -330)
    option("myLevelOnly", "optMyLevel", -354)
    option("hideBoost", "optHideBoost", -380)
    option("showIcon", "optIcon", -406, function(value) ns.SetLauncherShown(value) end)

    -- 3. Alerts
    section("secAlert", -446)
    option("alertMyLevel", "optAlertMyLevel", -470)
    option("alertSound", "optSound", -496)
    local watchHint = configFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    watchHint:SetPoint("TOPLEFT", 24, -526)
    watchHint:SetWidth(372)
    watchHint:SetJustifyH("LEFT")
    watchHint:SetTextColor(rgba(S.textMuted))

    -- language & blocked players
    local langBtn = UIKit:CreateButton(configFrame, 187, 28, "")
    langBtn:SetPoint("TOPLEFT", 20, -562)
    local unblockBtn = UIKit:CreateButton(configFrame, 187, 28, "")
    unblockBtn:SetPoint("TOPLEFT", 213, -562)

    -- bottom buttons
    local resetBtn = UIKit:CreateButton(configFrame, 185, 33, "")
    resetBtn:SetPoint("BOTTOMLEFT", 20, 36)
    local donateBtn = UIKit:CreateButton(configFrame, 185, 33, "", true)
    donateBtn:SetPoint("BOTTOMRIGHT", -20, 36)
    donateBtn:SetScript("OnClick", showDonatePopup)

    local foot = configFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    foot:SetPoint("BOTTOM", 0, 12)

    local function updateLabels()
        ns.FitText(top.subtitle, ns:L("settingsSub"), 320, 10, 8)
        for _, h in ipairs(headings) do ns.FitText(h.fs, ns:L(h.key), 375, 13, 10) end
        for _, item in ipairs(checks) do
            item.check:SetChecked(db[item.dbKey] and true or false)
            ns.FitText(item.label, ns:L(item.labelKey), 345, 12, 9)
        end
        ns.FitText(joinLabel, ns:L("optJoinChannels"), 372, 12, 9)
        if not joinEdit:HasFocus() then joinEdit:SetText(db.joinChannels or "") end
        joinBox.UpdatePlaceholder()
        joinHint:SetText(ns:L("joinHint"))
        ns.FitText(expireLabel, ns:L("optExpire"), 220, 12, 9)
        expireValue:SetText(string.format(ns:L("minutes"), db.expireMinutes))
        watchHint:SetText(ns:L("watchHint"))
        langBtn:SetLabel(ns:L("language") .. ": " .. ns:GetLanguageDisplayLabel() .. " ▼")
        local blocked = blockedCount()
        unblockBtn:SetLabel(string.format(ns:L("unblock"), blocked))
        unblockBtn:SetEnabledState(blocked > 0)
        resetBtn:SetLabel(ns:L("resetPos"))
        donateBtn:SetLabel(ns:L("donate"))
        local ver = ns.GetVersion()
        foot:SetText(ns.TITLE .. (ver ~= "" and (" " .. ver) or "") .. "  ·  /ezgf")
        if copyBox and copyBox:IsShown() then copyBox.label:SetText(ns:L("copy")) end
        if optionsPanel and optionsPanel.refreshText then optionsPanel.refreshText() end
    end

    minus:SetScript("OnClick", function()
        db.expireMinutes = math.max(3, db.expireMinutes - 1)
        updateLabels()
        ns.PrunePosts()
        ns.RefreshMainWindow()
    end)
    plus:SetScript("OnClick", function()
        db.expireMinutes = math.min(30, db.expireMinutes + 1)
        updateLabels()
        ns.RefreshMainWindow()
    end)
    unblockBtn:SetScript("OnClick", function()
        wipe(db.blocked)
        updateLabels()
        ns.RefreshMainWindow()
    end)
    resetBtn:SetScript("OnClick", function()
        ns.ResetMainWindowPosition()
        db.frames.icon = nil
        local icon = _G.EzWoW_GroupFinderIcon
        if icon then
            icon:ClearAllPoints()
            ns.PlaceLauncherDefault(icon)
        end
    end)

    local langItems = {}
    for i, v in ipairs(ns.LANGUAGE_OPTIONS) do langItems[i] = { value = v[1], text = v[2] } end
    ns.LanguageDropdown.Attach(langBtn, {
        items = langItems,
        colors = { accent = ns.Style.accent },
        get = function() return db.language end,
        set = function(code)
            db.language = code
            updateLabels()
            ns.RefreshMainWindow()
        end,
    })

    configFrame:SetScript("OnShow", updateLabels)
    configFrame.updateLabels = updateLabels
    updateLabels()
    configFrame:Raise()
end

-----------------------------------------------------------------------------
-- Blizzard Settings Canvas Launcher
-----------------------------------------------------------------------------
function ns:RegisterBlizzardOptions()
    if optionsPanel then return end
    local S = ns.Style
    optionsPanel = CreateFrame("Frame", "EzWoWGroupFinderOptionsPanel", UIParent)
    optionsPanel.name = ns.TITLE

    local icon = optionsPanel:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("TOPLEFT", 18, -18)
    icon:SetTexture(ns.MEDIA_PATH .. "Icon")

    local heading = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    heading:SetPoint("LEFT", icon, "RIGHT", 10, 0)
    heading:SetText(ns.TITLE)
    heading:SetTextColor(rgba(S.accent))

    local desc = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -14)
    desc:SetWidth(520)
    desc:SetJustifyH("LEFT")

    local open = UIKit:CreateButton(optionsPanel, 220, 28, "", true)
    open:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -18)
    open:SetScript("OnClick", function() ns.ToggleMainWindow("browse") end)

    local settings = UIKit:CreateButton(optionsPanel, 220, 28, "")
    settings:SetPoint("LEFT", open, "RIGHT", 8, 0)
    settings:SetScript("OnClick", function() ns:ToggleOptions() end)

    local hint = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -14)
    hint:SetTextColor(rgba(S.textMuted))

    optionsPanel.refreshText = function()
        desc:SetText(ns:L("panelDesc"))
        open:SetLabel(ns:L("panelOpen"))
        settings:SetLabel(ns:L("settings"))
        hint:SetText(ns:L("panelHint"))
    end
    optionsPanel:SetScript("OnShow", optionsPanel.refreshText)
    -- fill the texts now: the settings window does not always fire OnShow
    optionsPanel.refreshText()

    if Settings and type(Settings.RegisterCanvasLayoutCategory) == "function" and type(Settings.RegisterAddOnCategory) == "function" then
        local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, optionsPanel, ns.TITLE)
        if ok and cat then pcall(Settings.RegisterAddOnCategory, cat) end
    elseif type(InterfaceOptions_AddCategory) == "function" then
        pcall(InterfaceOptions_AddCategory, optionsPanel)
    end
end

-----------------------------------------------------------------------------
-- Slash Commands (/ezgf, /파티찾기, /ezwowgroupfinder)
-----------------------------------------------------------------------------
SLASH_EZWOWGROUPFINDER1 = "/ezgf"
SLASH_EZWOWGROUPFINDER2 = "/파티찾기"
SLASH_EZWOWGROUPFINDER3 = "/ezwowgroupfinder"

SlashCmdList.EZWOWGROUPFINDER = function(msg)
    if not ns.db then
        ns.Print(ns:L("waiting"))
        return
    end
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "config" or msg == "options" or msg == "설정" then
        ns:ToggleOptions()
    elseif msg == "post" or msg == "모집" then
        ns.ToggleMainWindow("compose")
    elseif msg == "channels" or msg == "채널" then
        ns.PrintChannels()
    elseif msg == "clear" then
        ns.ClearPosts()
    elseif msg == "icon" or msg == "아이콘" then
        -- always brings the icon back (hiding it is done in the settings window)
        ns.db.frames.icon = nil
        ns.SetLauncherShown(true)
        ns.PlaceLauncherDefault(ns.CreateLauncher())
    elseif msg:match("^lang") then
        local arg = msg:match("^%S+%s+(%S+)")
        local norm = arg and ns.LANG_ALIASES[arg]
        if not norm then
            ns.Print("/ezgf lang auto | ko | en | de | fr | es | ru | cn | tw")
            return
        end
        ns.db.language = norm
        if configFrame and configFrame.updateLabels then configFrame.updateLabels() end
        ns.RefreshMainWindow()
        ns.Print(ns:L("language") .. ": " .. norm .. " (" .. ns:GetActiveLang() .. ")")
    elseif msg == "debug" then
        ns.debug = not ns.debug
        ns.Print("debug: " .. (ns.debug and "on" or "off"))
    else
        ns.ToggleMainWindow()
    end
end

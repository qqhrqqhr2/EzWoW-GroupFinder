--===========================================================================
-- EzWoW - Group Finder
-- UI/Launcher.lua : Draggable floating launcher icon with a post counter
--===========================================================================
local _, ns = ...

local button

local function showTooltip(self)
    if self.dragging then return end
    local S = ns.Style
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(ns.TITLE, S.accent[1], S.accent[2], S.accent[3])
    local counts = ns.CountByCategory()
    GameTooltip:AddLine(string.format(ns:L("iconCount"), counts.all, counts.mylevel), S.textBody[1], S.textBody[2], S.textBody[3])
    GameTooltip:AddLine(ns:L("iconLeft"), S.textMuted[1], S.textMuted[2], S.textMuted[3])
    GameTooltip:AddLine(ns:L("iconRight"), S.textMuted[1], S.textMuted[2], S.textMuted[3])
    GameTooltip:AddLine(ns:L("iconDrag"), S.textMuted[1], S.textMuted[2], S.textMuted[3])
    GameTooltip:Show()
end

-- Default spot: left of the minimap, clear of the quest tracker and chat.
function ns.PlaceLauncherDefault(btn)
    btn:ClearAllPoints()
    btn:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -215, -95)
end

function ns.CreateLauncher()
    if button then return button end
    button = CreateFrame("Button", "EzWoW_GroupFinderIcon", UIParent)
    button:SetSize(36, 36)
    button:SetFrameStrata("HIGH")
    button:SetClampedToScreen(true)
    button:SetMovable(true)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ns.MEDIA_PATH .. "Icon")
    icon:SetAllPoints()
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture(ns.MEDIA_PATH .. "Icon")
    highlight:SetAllPoints()
    highlight:SetBlendMode("ADD")
    highlight:SetAlpha(0.35)

    -- counter badge: posts for the player's level
    local badge = CreateFrame("Frame", nil, button, "BackdropTemplate")
    badge:SetSize(18, 16)
    badge:SetPoint("TOPRIGHT", button, "TOPRIGHT", 6, 4)
    ns.UIKit:ApplyBackdrop(badge)
    badge:SetBackdropColor(0.071, 0.094, 0.122, 0.95)
    badge:SetBackdropBorderColor(ns.Style.accent[1], ns.Style.accent[2], ns.Style.accent[3], 1)
    badge.text = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    badge.text:SetPoint("CENTER", 0, 0)
    badge.text:SetTextColor(ns.Style.accent[1], ns.Style.accent[2], ns.Style.accent[3])
    badge:Hide()
    button.badge = badge

    local pos = ns.db.frames.icon
    if type(pos) == "table" and pos[1] then
        button:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        ns.PlaceLauncherDefault(button)
    end

    local grabDX, grabDY = 0, 0
    button:SetScript("OnDragStart", function(self)
        self.dragging = true
        GameTooltip:Hide()
        local scale = self:GetEffectiveScale() or 1
        local cx, cy = GetCursorPosition()
        local bx, by = self:GetCenter()
        grabDX, grabDY = (bx or 0) - cx / scale, (by or 0) - cy / scale
        self:SetScript("OnUpdate", function(btn)
            local es = btn:GetEffectiveScale() or 1
            local x, y = GetCursorPosition()
            x, y = x / es + grabDX, y / es + grabDY
            local w, h = UIParent:GetWidth() or 1920, UIParent:GetHeight() or 1080
            x = math.max(18, math.min(w - 18, x))
            y = math.max(18, math.min(h - 18, y))
            btn:ClearAllPoints()
            btn:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        local cx, cy = self:GetCenter()
        if cx and cy then
            ns.db.frames.icon = { "CENTER", "BOTTOMLEFT", math.floor(cx + 0.5), math.floor(cy + 0.5) }
        end
        self.dragging = false
    end)
    button:SetScript("OnClick", function(self, mouse)
        if self.dragging then return end
        if mouse == "RightButton" then
            ns:ToggleOptions()
        else
            ns.ToggleMainWindow()
        end
    end)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetShown(ns.db.showIcon)
    ns.RefreshLauncher()
    return button
end

function ns.RefreshLauncher()
    if not button or not ns.db then return end
    local count = ns.CountByCategory().mylevel
    if count > 0 then
        button.badge.text:SetText(count > 99 and "99+" or tostring(count))
        button.badge:SetWidth(math.max(18, button.badge.text:GetStringWidth() + 8))
        button.badge:Show()
    else
        button.badge:Hide()
    end
end

function ns.SetLauncherShown(show)
    ns.db.showIcon = show and true or false
    ns.CreateLauncher():SetShown(ns.db.showIcon)
end

--===========================================================================
-- EzWoW - Group Finder
-- UI/MainWindow.lua : Finder window (browse tab + post tab)
--===========================================================================
local _, ns = ...
local type, pairs, ipairs, tonumber, tostring, pcall = type, pairs, ipairs, tonumber, tostring, pcall

local UIKit = ns.UIKit
local WIDTH, HEIGHT = 820, 540
local SIDEBAR_WIDTH = 206
local CONTENT_TOP = -100
local FOOTER_HEIGHT = 34

local window
local browse, compose = {}, {}

-- column starts in a post row (and its header)
local COL = { kind = 12, dungeon = 62, roles = 300, members = 392, level = 446 }

local function rgba(c) return c[1], c[2], c[3], c[4] or 1 end
local function S() return ns.Style end

local function hexColor(c)
    return string.format("%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

local function colorize(text, c)
    return "|cff" .. hexColor(c) .. text .. "|r"
end

local function rolesMarkup(roles)
    local out = {}
    if roles.tank then out[#out + 1] = colorize(ns:L("roleTank"), S().tank) end
    if roles.healer then out[#out + 1] = colorize(ns:L("roleHeal"), S().healer) end
    if roles.dps then out[#out + 1] = colorize(ns:L("roleDps"), S().dps) end
    return table.concat(out, " ")
end

local function ageText(seconds)
    local minutes = math.floor(seconds / 60)
    if minutes < 1 then return ns:L("agoNow") end
    return string.format(ns:L("agoMin"), minutes)
end

local function kindColor(post)
    if post.boost then return S().boost end
    if post.kind == "lfg" then return S().lfg end
    return S().accent
end

local function kindLabel(post)
    if post.boost then return ns:L("kindBoost") end
    return ns:L(post.kind == "lfg" and "kindLFG" or "kindLFM")
end

local function postTitle(post)
    local names = {}
    for _, key in ipairs(post.keys) do names[#names + 1] = ns:GetDungeonName(key) end
    return table.concat(names, " / ")
end

local function setWatchIcon(texture)
    local atlas = "PetJournal-FavoritesIcon"
    if C_Texture and type(C_Texture.GetAtlasInfo) == "function" and C_Texture.GetAtlasInfo(atlas) then
        texture:SetAtlas(atlas)
    else
        texture:SetTexture("Interface\\COMMON\\FavoritesIcon")
    end
end

-----------------------------------------------------------------------------
-- Sidebar categories
-----------------------------------------------------------------------------
local function categoryItems()
    local items = { { key = "all" }, { key = "mylevel" } }
    for _, dungeon in ipairs(ns.Dungeons) do
        items[#items + 1] = { key = dungeon.key, dungeon = dungeon }
    end
    items[#items + 1] = { key = "quest" }
    items[#items + 1] = { key = "other" }
    return items
end

local function categoryName(key)
    if key == "all" then return ns:L("catAll") end
    if key == "mylevel" then return ns:L("catMyLevel") end
    return ns:GetDungeonName(key)
end

local function createCategoryRow(list)
    local row = CreateFrame("Button", nil, list)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetPoint("TOPLEFT")
    row.bar:SetPoint("BOTTOMLEFT")
    row.bar:SetWidth(2)
    row.bar:SetColorTexture(rgba(S().accent))
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetJustifyH("LEFT")
    row.levels = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.levels:SetTextColor(rgba(S().textMuted))
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.count:SetPoint("RIGHT", -6, 0)
    row.star = row:CreateTexture(nil, "OVERLAY")
    row.star:SetSize(13, 13)
    setWatchIcon(row.star)

    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if ns.DungeonByKey[self.key] then
                ns.db.watch[self.key] = not ns.db.watch[self.key] or nil
                ns.RefreshMainWindow()
            end
            return
        end
        ns.db.selected = self.key
        browse.list.offset = 0
        ns.RefreshMainWindow()
    end)
    row:SetScript("OnEnter", function(self)
        self.hover = true
        browse.paintCategory(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(categoryName(self.key), rgba(S().accent))
        local dungeon = ns.DungeonByKey[self.key]
        if dungeon then
            GameTooltip:AddLine(string.format(ns:L("levelRange"), dungeon.min, dungeon.max), rgba(S().textBody))
            GameTooltip:AddLine(ns.db.watch[self.key] and ns:L("watchOn") or ns:L("watchTip"), rgba(S().textMuted))
        elseif self.key == "mylevel" then
            GameTooltip:AddLine(string.format(ns:L("myLevelTip"), ns.PlayerLevel()), rgba(S().textMuted))
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self.hover = false
        browse.paintCategory(self)
        GameTooltip:Hide()
    end)
    return row
end

function browse.paintCategory(row)
    local selected = ns.db.selected == row.key
    if selected then
        row.bg:SetColorTexture(rgba(S().bgAccent))
    elseif row.hover then
        row.bg:SetColorTexture(S().bgHover[1], S().bgHover[2], S().bgHover[3], 0.8)
    else
        row.bg:SetColorTexture(0, 0, 0, 0)
    end
    row.bar:SetShown(selected)
end

local function updateCategoryRow(row, item)
    row.key = item.key
    local dungeon = item.dungeon
    local indent = (dungeon and dungeon.parent) and 18 or 8
    local count = browse.counts and browse.counts[item.key] or 0
    row.count:SetText(count > 0 and tostring(count) or "")
    row.count:SetTextColor(rgba(count > 0 and S().accent or S().disabled))
    local watched = ns.db.watch[item.key] and true or false
    row.star:SetShown(watched)

    local fits = dungeon and ns:DungeonFitsLevel(item.key)
    local levels = dungeon and (dungeon.min .. "-" .. dungeon.max) or ""
    row.levels:SetText(levels)
    row.levels:ClearAllPoints()
    row.levels:SetPoint("RIGHT", row, "RIGHT", -30, 0)
    if fits then row.levels:SetTextColor(rgba(S().accent)) else row.levels:SetTextColor(rgba(S().textMuted)) end

    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row, "LEFT", indent + (watched and 15 or 0), 0)
    row.star:ClearAllPoints()
    row.star:SetPoint("LEFT", row, "LEFT", indent - 2, 0)
    local rowWidth = row:GetWidth() or 0
    if rowWidth < 50 then rowWidth = SIDEBAR_WIDTH - 14 end
    local nameWidth = rowWidth - indent - (watched and 15 or 0) - 34 - (levels ~= "" and 40 or 0)
    ns.FitText(row.name, categoryName(item.key), nameWidth, (dungeon and dungeon.parent) and 11 or 12, 8)
    if item.key == "all" or item.key == "mylevel" then
        row.name:SetTextColor(rgba(S().textBody))
    else
        row.name:SetTextColor(rgba(count > 0 and S().textBody or S().textMuted))
    end
    browse.paintCategory(row)
end

-----------------------------------------------------------------------------
-- Post rows
-----------------------------------------------------------------------------
local function showPostTooltip(row)
    local post = row.post
    if not post then return end
    GameTooltip:SetOwner(row, "ANCHOR_CURSOR_RIGHT")
    GameTooltip:SetText(postTitle(post), rgba(kindColor(post)))
    local r, g, b = ns.ClassColor(post.class)
    local kc, muted = kindColor(post), S().textMuted
    GameTooltip:AddDoubleLine(post.sender, kindLabel(post), r or 1, g or 1, b or 1, kc[1], kc[2], kc[3])
    GameTooltip:AddLine(post.display or post.text, 0.929, 0.957, 0.969, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(post.channel or "", ageText(GetTime() - post.time), muted[1], muted[2], muted[3], muted[1], muted[2], muted[3])
    if not post.mine then
        GameTooltip:AddLine(ns:L("tipClick"), rgba(S().textMuted))
        GameTooltip:AddLine(ns:L("tipAlt"), rgba(S().textMuted))
    end
    GameTooltip:Show()
end

local function createPostRow(list)
    local row = CreateFrame("Button", nil, list, "BackdropTemplate")
    UIKit:ApplyBackdrop(row)
    row:RegisterForClicks("LeftButtonUp")

    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetPoint("TOPLEFT", 1, -1)
    row.bar:SetPoint("BOTTOMLEFT", 1, 1)
    row.bar:SetWidth(3)

    -- top line: fixed columns (kind | dungeon | roles | members | level | age)
    row.kind = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.kind:SetPoint("TOPLEFT", COL.kind, -7)
    row.kind:SetWidth(COL.dungeon - COL.kind - 4)
    row.kind:SetJustifyH("LEFT")
    row.kind:SetWordWrap(false)
    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.title:SetPoint("LEFT", row, "TOPLEFT", COL.dungeon, -13)
    row.title:SetJustifyH("LEFT")
    row.roles = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.roles:SetPoint("LEFT", row, "TOPLEFT", COL.roles, -13)
    row.roles:SetJustifyH("LEFT")
    row.members = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.members:SetPoint("LEFT", row, "TOPLEFT", COL.members, -13)
    row.members:SetJustifyH("LEFT")
    row.level = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.level:SetPoint("LEFT", row, "TOPLEFT", COL.level, -13)
    row.level:SetJustifyH("LEFT")
    row.level:SetTextColor(rgba(S().textMuted))
    row.age = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.age:SetPoint("TOPRIGHT", -10, -7)
    row.age:SetTextColor(rgba(S().textMuted))

    row.body = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.body:SetPoint("BOTTOMLEFT", 12, 8)
    row.body:SetJustifyH("LEFT")

    row.invite = UIKit:CreateButton(row, 54, 20, "", false, "GameFontHighlightSmall")
    row.invite:SetPoint("BOTTOMRIGHT", -8, 5)
    row.whisper = UIKit:CreateButton(row, 54, 20, "", true, "GameFontHighlightSmall")
    row.whisper:SetPoint("RIGHT", row.invite, "LEFT", -4, 0)
    row.whisper:SetScript("OnClick", function() if row.post then ns.WhisperPlayer(row.post.sender) end end)
    row.invite:SetScript("OnClick", function() if row.post then ns.InvitePlayer(row.post.sender) end end)

    -- one-click join whispers (tank / healer / dps) on recruiting posts
    row.joinBtns = {}
    for _, role in ipairs({ "tank", "healer", "dps" }) do
        local b = UIKit:CreateButton(row, 34, 20, "", false, "GameFontHighlightSmall")
        b.role = role
        b:SetScript("OnClick", function(self)
            if not row.post then return end
            if ns.SendJoinWhisper(row.post, self.role) then
                ns.Print(string.format(ns:L("joinSent"), row.post.shortName or row.post.sender))
            end
        end)
        b:HookScript("OnEnter", function(self)
            if not row.post then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(ns:L("joinTip"), 1, 1, 1)
            GameTooltip:AddLine(ns.BuildJoinWhisper(row.post, self.role), rgba(S().textMuted))
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        row.joinBtns[role] = b
    end

    row:SetScript("OnClick", function(self)
        local post = self.post
        if not post or post.mine then return end
        if IsAltKeyDown() then
            ns.db.blocked[post.sender] = true
            ns.Print(string.format(ns:L("blockedMsg"), post.shortName))
            ns.RefreshMainWindow()
            return
        end
        ns.WhisperPlayer(post.sender)
    end)
    row:SetScript("OnEnter", function(self)
        self.hover = true
        browse.paintPost(self)
        showPostTooltip(self)
    end)
    row:SetScript("OnLeave", function(self)
        self.hover = false
        browse.paintPost(self)
        GameTooltip:Hide()
    end)
    return row
end

function browse.paintPost(row)
    local post = row.post
    if row.hover then
        row:SetBackdropColor(rgba(S().bgHover))
        row:SetBackdropBorderColor(rgba(post and kindColor(post) or S().accent))
    else
        row:SetBackdropColor(rgba(S().bgSecondary))
        row:SetBackdropBorderColor(rgba(S().border))
    end
end

local function updatePostRow(row, post)
    row.post = post
    local color = kindColor(post)
    row.bar:SetColorTexture(rgba(color))
    row.kind:SetText(kindLabel(post))
    row.kind:SetTextColor(rgba(color))

    local width = row:GetWidth() or 0
    if width < 100 then width = WIDTH - SIDEBAR_WIDTH - 52 end
    row.age:SetText(ageText(GetTime() - post.time))

    -- roles: needed (recruiting) or offered (looking for a group); "-" when not written
    local roles = rolesMarkup(post.roles or {})
    row.roles:SetText(roles ~= "" and roles or colorize("-", S().disabled))
    -- members: "3/5" when the post says how many it has, "+2" when it says how many it needs
    if post.have then
        row.members:SetText(colorize(post.have .. "/5", S().textBody))
    elseif post.need then
        row.members:SetText(colorize("+" .. post.need, S().textBody))
    else
        row.members:SetText(colorize("-", S().disabled))
    end
    row.level:SetText(post.level and ("Lv" .. post.level) or "")

    local titleMax = COL.roles - COL.dungeon - 8
    local title = postTitle(post)
    local dungeon = ns.DungeonByKey[post.key]
    if dungeon and #post.keys == 1 then
        title = title .. colorize("  " .. dungeon.min .. "-" .. dungeon.max, ns:DungeonFitsLevel(post.key) and S().accent or S().textMuted)
    end
    ns.FitText(row.title, title, math.max(60, titleMax), 13, 9)
    row.title:SetTextColor(rgba(S().textBody))

    local r, g, b = ns.ClassColor(post.class)
    local nameColor = r and { r, g, b } or S().textBody
    local name = colorize(post.shortName .. (post.mine and (" " .. ns:L("me")) or ""), nameColor)
    local showButtons = not post.mine
    row.whisper:SetShown(showButtons)
    row.invite:SetShown(showButtons and post.kind == "lfg")
    row.whisper:SetLabel(ns:L("whisper"))
    row.invite:SetLabel(ns:L("invite"))
    local buttonsWidth = showButtons and (post.kind == "lfg" and 124 or 66) or 0

    -- join buttons: recruiting posts, the roles this class can play that the post asks for
    local myRoles = ns.MyClassRoles()
    local asks = type(post.roles) == "table" and (post.roles.tank or post.roles.healer or post.roles.dps)
    local anchor = row.whisper
    local roleLabel = { tank = "roleTank", healer = "roleHeal", dps = "roleDps" }
    for _, role in ipairs({ "dps", "healer", "tank" }) do
        local b = row.joinBtns[role]
        local show = showButtons and post.kind == "lfm" and not post.boost and myRoles[role]
            and (not asks or post.roles[role]) and true or false
        b:SetShown(show)
        if show then
            b:SetLabel(ns:L(roleLabel[role]))
            local w = math.max(34, math.floor((b.label:GetStringWidth() or 20) + 14))
            b:SetWidth(w)
            b:ClearAllPoints()
            b:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
            anchor = b
            buttonsWidth = buttonsWidth + w + 4
        end
    end
    ns.FitText(row.body, name .. colorize(": " .. (post.display or post.text), S().textMuted), width - 24 - buttonsWidth, 11, 11)
    browse.paintPost(row)
end

-----------------------------------------------------------------------------
-- Browse tab
-----------------------------------------------------------------------------
local function buildBrowse(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, CONTENT_TOP)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, FOOTER_HEIGHT)
    browse.panel = panel

    local side = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    side:SetPoint("TOPLEFT", 12, 0)
    side:SetPoint("BOTTOMLEFT", 12, 0)
    side:SetWidth(SIDEBAR_WIDTH)
    UIKit:ApplyBackdrop(side)
    side:SetBackdropColor(S().bgInput[1], S().bgInput[2], S().bgInput[3], 0.7)
    side:SetBackdropBorderColor(rgba(S().border))
    browse.categories = UIKit:CreateScrollList(side, 22, 0, 3, createCategoryRow, updateCategoryRow)
    browse.categories:SetPoint("TOPLEFT", 4, -4)
    browse.categories:SetPoint("BOTTOMRIGHT", -2, 4)

    local left = 12 + SIDEBAR_WIDTH + 10
    local searchBox, searchEdit = UIKit:CreateEditBox(panel, 150, 26, function() return ns:L("search") end)
    searchBox:SetPoint("TOPLEFT", left, 0)
    searchEdit:SetScript("OnTextChanged", function()
        browse.list.offset = 0
        ns.RefreshMainWindow()
    end)
    searchEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    browse.search = searchEdit
    browse.searchBox = searchBox

    local function chip(key, width, anchor, x)
        local b = UIKit:CreateButton(panel, width, 26, "", false, "GameFontHighlightSmall")
        b:SetPoint("LEFT", anchor, "RIGHT", x, 0)
        b:SetScript("OnClick", function()
            ns.db[key] = not ns.db[key]
            browse.list.offset = 0
            ns.RefreshMainWindow()
        end)
        return b
    end
    browse.lfmChip = chip("showLFM", 62, searchBox, 8)
    browse.lfgChip = chip("showLFG", 62, browse.lfmChip, 4)
    browse.boostChip = chip("hideBoost", 104, browse.lfgChip, 4)
    browse.levelChip = chip("myLevelOnly", 104, browse.boostChip, 4)
    -- left click: on/off, right click: pick my role (tank -> healer -> dps)
    browse.roleChip = chip("myRoleOnly", 78, browse.levelChip, 4)
    browse.roleChip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    browse.roleChip:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            local nextRole = { tank = "healer", healer = "dps", dps = "tank" }
            ns.db.myRole = nextRole[ns.db.myRole or "dps"] or "dps"
            ns.db.myRoleOnly = true
        else
            ns.db.myRoleOnly = not ns.db.myRoleOnly
        end
        browse.list.offset = 0
        ns.RefreshMainWindow()
        if GameTooltip:IsOwned(self) then
            self:GetScript("OnEnter")(self)
        end
    end)
    browse.roleChip.tooltip = function() return ns:L("myRoleTip") end

    -- column titles above the list
    local header = CreateFrame("Frame", nil, panel)
    header:SetPoint("TOPLEFT", left, -32)
    header:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
    header:SetHeight(18)
    browse.header = {}
    for _, col in ipairs({ { "kind", "colKind" }, { "dungeon", "colDungeon" }, { "roles", "colRoles" },
        { "members", "colMembers" }, { "level", "colLevel" } }) do
        local fs = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", header, "LEFT", COL[col[1]], 0)
        fs:SetTextColor(rgba(S().textMuted))
        browse.header[col[2]] = fs
    end
    local ageHead = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ageHead:SetPoint("RIGHT", header, "RIGHT", -10, 0)
    ageHead:SetTextColor(rgba(S().textMuted))
    browse.header.colAge = ageHead

    browse.list = UIKit:CreateScrollList(panel, 50, 4, 1, createPostRow, updatePostRow)
    browse.list:SetPoint("TOPLEFT", left, -52)
    browse.list:SetPoint("BOTTOMRIGHT", -12, 0)

    browse.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    browse.empty:SetPoint("CENTER", browse.list, "CENTER", 0, 20)
    browse.empty:SetWidth(440)
    browse.empty:SetJustifyH("CENTER")
    browse.empty:SetTextColor(rgba(S().textMuted))
end

function browse.Refresh()
    local db = ns.db
    browse.counts = ns.CountByCategory()
    browse.categories:SetData(categoryItems(), true)
    for key, fs in pairs(browse.header) do fs:SetText(ns:L(key)) end

    browse.lfmChip:SetLabel(ns:L("kindLFM"))
    browse.lfmChip:SetActive(db.showLFM)
    browse.lfgChip:SetLabel(ns:L("kindLFG"))
    browse.lfgChip.activeColor = S().lfg
    browse.lfgChip:SetActive(db.showLFG)
    browse.boostChip:SetLabel(ns:L("hideBoost"))
    browse.boostChip:SetActive(db.hideBoost)
    browse.levelChip:SetLabel(ns:L("myLevelChip"))
    browse.levelChip:SetActive(db.myLevelOnly)
    local roleKey = ({ tank = "roleTank", healer = "roleHeal", dps = "roleDps" })[db.myRole or "dps"] or "roleDps"
    browse.roleChip:SetLabel(string.format(ns:L("myRoleChip"), ns:L(roleKey)))
    browse.roleChip:SetActive(db.myRoleOnly)
    browse.searchBox.UpdatePlaceholder()

    local posts = ns.GetFilteredPosts(db.selected, browse.search:GetText())
    browse.list:SetData(posts, true)
    if #posts == 0 then
        browse.empty:SetText(#ns.Posts == 0 and ns:L("emptyList") or ns:L("emptyFilter"))
        browse.empty:Show()
    else
        browse.empty:Hide()
    end
end

-----------------------------------------------------------------------------
-- Post (compose) tab
-----------------------------------------------------------------------------
local function composeState() return ns.db.compose end

local function regenerate(force)
    local c = composeState()
    if force or not compose.dirty then
        compose.dirty = false
        compose.messageEdit.programmatic = true
        compose.messageEdit:SetText(ns.BuildPostText(c))
        compose.messageEdit.programmatic = false
    end
end

local function dungeonMenuItems()
    local items = {}
    for _, dungeon in ipairs(ns.Dungeons) do
        items[#items + 1] = {
            value = dungeon.key,
            text = function() return ns:GetDungeonName(dungeon.key) end,
            sub = dungeon.min .. "-" .. dungeon.max,
            color = ns:DungeonFitsLevel(dungeon.key) and S().accent or nil,
        }
    end
    items[#items + 1] = { value = "quest", text = function() return ns:L("catQuest") end }
    items[#items + 1] = { value = "other", text = function() return ns:L("noDungeon") end }
    return items
end

local function buildCompose(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, CONTENT_TOP)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, FOOTER_HEIGHT)
    compose.panel = panel

    local x1, x2 = 24, 430
    local function onChange()
        compose.Refresh()
        regenerate(false)
    end

    -- post type
    compose.modeLabel = UIKit:CreateSectionLabel(panel, x1, -6)
    compose.lfmBtn = UIKit:CreateButton(panel, 180, 28, "")
    compose.lfmBtn:SetPoint("TOPLEFT", x1, -28)
    compose.lfmBtn:SetScript("OnClick", function() composeState().mode = "lfm"; onChange() end)
    compose.lfgBtn = UIKit:CreateButton(panel, 180, 28, "")
    compose.lfgBtn:SetPoint("LEFT", compose.lfmBtn, "RIGHT", 6, 0)
    compose.lfgBtn.activeColor = S().lfg
    compose.lfgBtn:SetScript("OnClick", function() composeState().mode = "lfg"; onChange() end)

    -- dungeon
    compose.dungeonLabel = UIKit:CreateSectionLabel(panel, x1, -72)
    compose.dungeonBtn = UIKit:CreateButton(panel, 366, 28, "")
    compose.dungeonBtn:SetPoint("TOPLEFT", x1, -94)
    compose.dungeonBtn:SetScript("OnClick", function(self)
        UIKit:ShowMenu(self, dungeonMenuItems(), {
            columns = 2, width = 220, current = composeState().dungeon,
            onSelect = function(value) composeState().dungeon = value; onChange() end,
        })
    end)
    compose.suggest = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    compose.suggest:SetPoint("TOPLEFT", compose.dungeonBtn, "BOTTOMLEFT", 2, -5)
    compose.suggest:SetTextColor(rgba(S().textMuted))

    -- roles
    compose.rolesLabel = UIKit:CreateSectionLabel(panel, x1, -158)
    compose.roleBtns = {}
    local prev
    for _, role in ipairs({ "tank", "healer", "dps" }) do
        local b = UIKit:CreateButton(panel, 118, 28, "")
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", x1, -180) end
        b.role = role
        b.activeColor = S()[role]
        b:SetScript("OnClick", function(self)
            local roles = composeState().roles
            roles[self.role] = not roles[self.role] or nil
            onChange()
        end)
        compose.roleBtns[role] = b
        prev = b
    end

    -- group size (recruiting only)
    compose.sizeLabel = UIKit:CreateSectionLabel(panel, x1, -224)
    compose.minus = UIKit:CreateButton(panel, 28, 28, "-")
    compose.minus:SetPoint("TOPLEFT", x1, -246)
    compose.sizeValue = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    compose.sizeValue:SetPoint("LEFT", compose.minus, "RIGHT", 10, 0)
    compose.sizeValue:SetWidth(44)
    compose.plus = UIKit:CreateButton(panel, 28, 28, "+")
    compose.plus:SetPoint("LEFT", compose.minus, "RIGHT", 64, 0)
    compose.minus:SetScript("OnClick", function()
        composeState().size = math.max(1, composeState().size - 1); onChange()
    end)
    compose.plus:SetScript("OnClick", function()
        composeState().size = math.min(4, composeState().size + 1); onChange()
    end)

    -- note
    compose.noteLabel = UIKit:CreateSectionLabel(panel, x1, -290)
    local noteBox, noteEdit = UIKit:CreateEditBox(panel, 366, 28, function() return ns:L("notePlaceholder") end)
    noteBox:SetPoint("TOPLEFT", x1, -312)
    noteEdit:SetMaxLetters(80)
    noteEdit:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            composeState().note = self:GetText()
            regenerate(false)
        end
    end)
    noteEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    compose.noteBox, compose.noteEdit = noteBox, noteEdit

    -- target channel
    compose.channelLabel = UIKit:CreateSectionLabel(panel, x2, -6)
    compose.channelBtn = UIKit:CreateButton(panel, 366, 28, "")
    compose.channelBtn:SetPoint("TOPLEFT", x2, -28)
    compose.channelBtn:SetScript("OnClick", function(self)
        UIKit:ShowMenu(self, ns.GetSendTargets(), {
            current = composeState().channel,
            onSelect = function(value) composeState().channel = value; compose.Refresh() end,
        })
    end)

    -- message
    compose.messageLabel = UIKit:CreateSectionLabel(panel, x2, -72)
    compose.rebuildBtn = UIKit:CreateButton(panel, 110, 22, "", false, "GameFontHighlightSmall")
    compose.rebuildBtn:SetPoint("TOPRIGHT", panel, "TOPLEFT", x2 + 366, -68)
    compose.rebuildBtn:SetScript("OnClick", function() regenerate(true) end)
    local msgBox, msgEdit = UIKit:CreateEditBox(panel, 366, 96, nil, true)
    msgBox:SetPoint("TOPLEFT", x2, -94)
    msgEdit:SetMaxBytes(255)
    msgEdit:SetScript("OnTextChanged", function(self, userInput)
        if userInput and not self.programmatic then compose.dirty = true end
        compose.UpdateByteCount()
    end)
    msgEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    compose.messageEdit = msgEdit
    compose.bytes = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    compose.bytes:SetPoint("TOPRIGHT", msgBox, "BOTTOMRIGHT", -2, -4)
    compose.bytes:SetTextColor(rgba(S().textMuted))

    compose.tip = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    compose.tip:SetPoint("TOPLEFT", msgBox, "BOTTOMLEFT", 2, -24)
    compose.tip:SetWidth(362)
    compose.tip:SetJustifyH("LEFT")
    compose.tip:SetTextColor(rgba(S().textMuted))

    -- repeat reminder interval (click: next choice)
    compose.repeatBtn = UIKit:CreateButton(panel, 366, 24, "", false, "GameFontHighlightSmall")
    compose.repeatBtn:SetPoint("TOPLEFT", x2, -270)
    compose.repeatBtn:SetScript("OnClick", function()
        local c = composeState()
        local list, cur = ns.REPEAT_CHOICES, tonumber(c.repeatEvery) or 0
        local nextValue = list[1]
        for i, v in ipairs(list) do
            if v == cur then nextValue = list[i % #list + 1] break end
        end
        c.repeatEvery = nextValue
        if nextValue == 0 then ns.StopRepeat(true) end
        compose.Refresh()
    end)
    compose.repeatBtn.tooltip = function() return ns:L("repeatTip") end

    -- send
    compose.sendBtn = UIKit:CreateButton(panel, 366, 36, "", true, "GameFontNormal")
    compose.sendBtn:SetPoint("TOPLEFT", x2, -312 + 8)
    compose.sendBtn:SetScript("OnClick", function()
        local c = composeState()
        c.channel = c.channel or ns.DefaultSendTarget()
        local text = compose.messageEdit:GetText()
        if ns.SendPost(text, c.channel) then
            compose.status = ns:L("sentMsg")
            ns.StartRepeat(text, c.channel, c.mode)
        end
        compose.Refresh()
    end)
    compose.statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    compose.statusText:SetPoint("TOP", compose.sendBtn, "BOTTOM", 0, -6)
    compose.statusText:SetTextColor(rgba(S().accent))

    panel:SetScript("OnUpdate", function(self, elapsed)
        self.tick = (self.tick or 0) + elapsed
        if self.tick < 0.5 then return end
        self.tick = 0
        compose.UpdateSendButton()
    end)
end

function compose.UpdateByteCount()
    local text = compose.messageEdit:GetText() or ""
    compose.bytes:SetText(#text .. " / 255")
end

function compose.UpdateSendButton()
    local left = ns.SendCooldownLeft()
    if left > 0 then
        compose.sendBtn:SetLabel(string.format(ns:L("sendWait"), left))
        compose.sendBtn:SetEnabledState(false)
    else
        compose.sendBtn:SetLabel(ns:L("send"))
        compose.sendBtn:SetEnabledState((compose.messageEdit:GetText() or "") ~= "")
        compose.status = nil
    end
    compose.statusText:SetText(compose.status or "")
end

function compose.Refresh()
    local c = composeState()
    if not c.dungeon then c.dungeon = ns:SuggestDungeon() end
    if not c.channel or not ns.SendTargetLabel(c.channel) then c.channel = ns.DefaultSendTarget() end
    local lfg = c.mode == "lfg"

    compose.modeLabel:SetText(ns:L("composeMode"))
    compose.lfmBtn:SetLabel(ns:L("modeLFM"))
    compose.lfmBtn:SetActive(not lfg)
    compose.lfgBtn:SetLabel(ns:L("modeLFG"))
    compose.lfgBtn:SetActive(lfg)

    compose.dungeonLabel:SetText(ns:L("dungeon"))
    local name = c.dungeon == "other" and ns:L("noDungeon") or ns:GetDungeonName(c.dungeon)
    local levels = ns:GetDungeonLevels(c.dungeon)
    compose.dungeonBtn:SetLabel(name .. (levels ~= "" and ("  (" .. levels .. ")") or "") .. "  ▼")
    local suggestKey = ns:SuggestDungeon()
    compose.suggest:SetText(string.format(ns:L("suggest"), ns.PlayerLevel(), ns:GetDungeonName(suggestKey)))

    compose.rolesLabel:SetText(ns:L(lfg and "rolesMine" or "rolesNeed"))
    for role, b in pairs(compose.roleBtns) do
        b:SetLabel(ns:L(role == "tank" and "roleTank" or role == "healer" and "roleHeal" or "roleDps"))
        b:SetActive(c.roles[role])
    end

    compose.sizeLabel:SetText(ns:L("members"))
    compose.sizeValue:SetText(c.size .. " / 5")
    for _, w in ipairs({ compose.sizeLabel, compose.minus, compose.plus, compose.sizeValue }) do w:SetShown(not lfg) end

    compose.noteLabel:SetText(ns:L("note"))
    if not compose.noteEdit:HasFocus() then compose.noteEdit:SetText(c.note or "") end
    compose.noteBox.UpdatePlaceholder()

    compose.channelLabel:SetText(ns:L("channel"))
    compose.channelBtn:SetLabel((ns.SendTargetLabel(c.channel) or ns:L("noChannel")) .. "  ▼")
    compose.messageLabel:SetText(ns:L("message"))
    compose.rebuildBtn:SetLabel(ns:L("rebuild"))
    compose.tip:SetText(ns:L("spamTip"))
    local every = tonumber(c.repeatEvery) or 0
    local everyText = every > 0 and string.format(ns:L("repeatEvery"), every % 60 == 0 and string.format(ns:L("repeatMin"), every / 60)
        or string.format(ns:L("repeatMinSec"), math.floor(every / 60), every % 60)) or ns:L("repeatOff")
    compose.repeatBtn:SetLabel(string.format(ns:L("repeatLabel"), everyText))
    compose.repeatBtn:SetActive(every > 0)
    compose.UpdateByteCount()
    compose.UpdateSendButton()
end

-----------------------------------------------------------------------------
-- Repeat reminder (shows even with the window closed)
-----------------------------------------------------------------------------
local reminder

local function buildReminder()
    local f = CreateFrame("Frame", "EzWoWGroupFinderRepost", UIParent, "BackdropTemplate")
    f:SetSize(300, 64)
    f:SetFrameStrata("DIALOG")
    UIKit:ApplyBackdrop(f)
    f:SetBackdropColor(rgba(S().bgSecondary))
    f:SetBackdropBorderColor(rgba(S().accent))
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint(1)
        ns.db.frames.repost = { point, relPoint, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5) }
    end)
    local pos = ns.db.frames and ns.db.frames.repost
    if type(pos) == "table" and pos[1] then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, -160)
    end
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 10, -8)
    f.title:SetPoint("TOPRIGHT", -10, -8)
    f.title:SetJustifyH("LEFT")
    f.post = UIKit:CreateButton(f, 186, 26, "", true, "GameFontHighlightSmall")
    f.post:SetPoint("BOTTOMLEFT", 10, 8)
    f.post:SetScript("OnClick", function() ns.RepostNow() end)
    f.stop = UIKit:CreateButton(f, 88, 26, "", false, "GameFontHighlightSmall")
    f.stop:SetPoint("BOTTOMRIGHT", -10, 8)
    f.stop:SetScript("OnClick", function() ns.StopRepeat() end)
    f:SetScript("OnUpdate", function(self, elapsed)
        self.tick = (self.tick or 0) + elapsed
        if self.tick < 0.5 then return end
        self.tick = 0
        local left = ns.SendCooldownLeft()
        self.post:SetLabel(left > 0 and string.format(ns:L("sendWait"), left) or ns:L("repostBtn"))
        self.post:SetEnabledState(left <= 0)
    end)
    f:Hide()
    return f
end

function ns.ShowRepostReminder(state)
    if not ns.db then return end
    reminder = reminder or buildReminder()
    reminder.title:SetText(string.format(ns:L("repostTitle"), state.count, ns.REPEAT_MAX))
    reminder.stop:SetLabel(ns:L("repostStop"))
    reminder.post:SetLabel(ns:L("repostBtn"))
    reminder:Show()
end

function ns.HideRepostReminder()
    if reminder then reminder:Hide() end
end

-----------------------------------------------------------------------------
-- Window
-----------------------------------------------------------------------------
local function savePosition(frame)
    local point, _, relPoint, x, y = frame:GetPoint(1)
    ns.db.frames.main = { point, relPoint, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5) }
end

local function setTab(tab)
    ns.db.tab = tab
    UIKit.HideMenu()
    ns.RefreshMainWindow()
end

local function buildWindow()
    window = CreateFrame("Frame", "EzWoWGroupFinderMain", UIParent, "BackdropTemplate")
    window:SetSize(WIDTH, HEIGHT)
    local pos = ns.db.frames.main
    if type(pos) == "table" and pos[1] then
        window:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        window:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
    window:SetFrameStrata("HIGH")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    UIKit:ApplyBackdrop(window, 1, 1)
    window:SetBackdropColor(rgba(S().bgPrimary))
    window:SetBackdropBorderColor(rgba(S().border))
    window.OnMoved = savePosition
    if UISpecialFrames then tinsert(UISpecialFrames, "EzWoWGroupFinderMain") end

    local top = UIKit:CreateHeader(window, ns.TITLE)
    window.subtitle = top.subtitle
    window.subtitle:SetWidth(520)

    local close = UIKit:CreateCloseButton(top, function() window:Hide() end)
    close:SetPoint("TOPRIGHT", top, "TOPRIGHT", -10, -10)
    local gear = UIKit:CreateButton(top, 64, 22, "", false, "GameFontHighlightSmall")
    gear:SetPoint("RIGHT", close, "LEFT", -6, 0)
    gear:SetFrameLevel(top:GetFrameLevel() + 3)
    gear:SetScript("OnClick", function() ns:ToggleOptions() end)
    window.gear = gear

    window.browseTab = UIKit:CreateButton(window, 150, 26, "")
    window.browseTab:SetPoint("TOPLEFT", 12, -66)
    window.browseTab:SetScript("OnClick", function() setTab("browse") end)
    window.composeTab = UIKit:CreateButton(window, 150, 26, "")
    window.composeTab:SetPoint("LEFT", window.browseTab, "RIGHT", 6, 0)
    window.composeTab:SetScript("OnClick", function() setTab("compose") end)

    buildBrowse(window)
    buildCompose(window)

    window.footer = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    window.footer:SetPoint("BOTTOMLEFT", 16, 12)
    window.footer:SetTextColor(rgba(S().textMuted))
    window.clearBtn = UIKit:CreateButton(window, 110, 22, "", false, "GameFontHighlightSmall")
    window.clearBtn:SetPoint("BOTTOMRIGHT", -12, 7)
    window.clearBtn:SetScript("OnClick", function() ns.ClearPosts() end)
    window.version = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    window.version:SetPoint("RIGHT", window.clearBtn, "LEFT", -12, 0)

    window:SetScript("OnShow", function() ns.RefreshMainWindow() end)
    window:SetScript("OnHide", function()
        UIKit.HideMenu()
        if ns.RefreshLauncher then ns.RefreshLauncher() end
    end)

    -- keep the "n minutes ago" labels fresh while open
    window.ticker = 0
    window:SetScript("OnUpdate", function(self, elapsed)
        self.ticker = self.ticker + elapsed
        if self.ticker >= 20 then
            self.ticker = 0
            if ns.db.tab ~= "compose" then browse.list:Refresh() end
        end
    end)
    -- start hidden: a new frame is shown, and the first toggle would hide it
    window:Hide()
end

function ns.RefreshMainWindow()
    if ns.RefreshLauncher then ns.RefreshLauncher() end
    if not window or not window:IsShown() then return end
    local db = ns.db
    local isCompose = db.tab == "compose"

    local total = #ns.Posts
    window.subtitle:SetText(string.format(ns:L("subtitle"), total))
    window.gear:SetLabel(ns:L("settings"))
    window.browseTab:SetLabel(ns:L("tabBrowse"))
    window.browseTab:SetActive(not isCompose)
    window.composeTab:SetLabel(ns:L("tabCompose"))
    window.composeTab:SetActive(isCompose)

    browse.panel:SetShown(not isCompose)
    compose.panel:SetShown(isCompose)
    window.clearBtn:SetShown(not isCompose)
    window.clearBtn:SetLabel(ns:L("clear"))
    window.footer:SetText(string.format(ns:L("footer"), total, db.expireMinutes))
    local ver = ns.GetVersion()
    window.version:SetText(ver ~= "" and ("v" .. ver .. "  ·  /ezgf") or "/ezgf")

    if isCompose then
        compose.Refresh()
        regenerate((compose.messageEdit:GetText() or "") == "")
    else
        browse.Refresh()
    end
end

function ns.MainWindowShown()
    return window and window:IsShown() or false
end

function ns.ToggleMainWindow(tab)
    if not ns.db then return end
    if not window then buildWindow() end
    if tab then ns.db.tab = tab end
    if window:IsShown() and not tab then
        window:Hide()
    else
        window:Show()
        window:Raise()
        ns.RefreshMainWindow()
    end
end

function ns.ResetMainWindowPosition()
    ns.db.frames.main = nil
    if window then
        window:ClearAllPoints()
        window:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
end

ns.OnPostsChanged(function() ns.RefreshMainWindow() end)

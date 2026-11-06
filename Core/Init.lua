--===========================================================================
-- EzWoW - Group Finder
-- Core/Init.lua : Namespace, EzWoW Style Palette, Safe Helpers & SavedVariables
--===========================================================================
local ADDON_NAME, ns = ...
local type, pairs, ipairs, tonumber, tostring, pcall = type, pairs, ipairs, tonumber, tostring, pcall

_G.EzWoW_GroupFinder = ns

ns.ADDON_NAME = ADDON_NAME or "EzWoW-GroupFinder"
ns.TITLE = "EzWoW - Group Finder"
ns.MEDIA_PATH = "Interface\\AddOns\\EzWoW-GroupFinder\\Media\\"
ns.DONATE_URL = "https://buymeacoffee.com/qqhrqqhr2"

-----------------------------------------------------------------------------
-- EzWoW Style v1.0 Palette (Brand Accent: Mint #7FD8B0)
-----------------------------------------------------------------------------
ns.Style = {
    bgPrimary   = { 0.071, 0.094, 0.122, 0.97 }, -- #12181F
    bgSecondary = { 0.114, 0.157, 0.192, 0.96 }, -- #1D2831
    bgInput     = { 0.047, 0.067, 0.086, 0.96 }, -- #0C1116
    bgHover     = { 0.160, 0.210, 0.260, 1.00 },
    bgAccent    = { 0.110, 0.200, 0.175, 0.96 },
    bgAccentHot = { 0.150, 0.270, 0.235, 1.00 },
    border      = { 0.204, 0.298, 0.357, 1.00 }, -- #344C5B
    textBody    = { 0.929, 0.957, 0.969, 1.00 }, -- #EDF4F7
    textMuted   = { 0.655, 0.725, 0.773, 1.00 }, -- #A7B9C5
    accent      = { 0.498, 0.847, 0.690, 1.00 }, -- #7FD8B0
    accentHex   = "7FD8B0",
    lfg         = { 0.490, 0.690, 0.960, 1.00 }, -- #7DB0F5 (looking for group)
    boost       = { 0.950, 0.760, 0.330, 1.00 }, -- gold
    warning     = { 0.906, 0.486, 0.439, 1.00 }, -- #E77C70
    disabled    = { 0.388, 0.447, 0.482, 1.00 }, -- #63727B
    tank        = { 0.420, 0.650, 1.000, 1.00 },
    healer      = { 0.400, 0.880, 0.450, 1.00 },
    dps         = { 1.000, 0.470, 0.420, 1.00 },
}

ns.DEFAULTS = {
    language       = "auto",
    collectChannel = true,
    collectSay     = true,
    collectGuild   = false,
    autoJoinLFG    = true,
    joinChannels   = "",
    expireMinutes  = 10,
    hideBoost      = false,
    myLevelOnly    = false,
    myRoleOnly     = false,
    myRole         = "dps",
    showLFM        = true,
    showLFG        = true,
    alertMyLevel   = false,
    alertSound     = true,
    showIcon       = true,
    selected       = "all",
    tab            = "browse",
    watch          = {},
    blocked        = {},
    frames         = {},
    compose        = {},
}

ns.COMPOSE_DEFAULTS = {
    mode    = "lfm",
    dungeon = nil,
    roles   = {},
    size    = 1,
    note    = "",
    channel = nil,
}

-----------------------------------------------------------------------------
-- Security & String Helpers (Interface 16001)
-----------------------------------------------------------------------------
function ns.IsSecret(value)
    if type(_G.issecretvalue) ~= "function" then return false end
    local ok, secret = pcall(_G.issecretvalue, value)
    return ok and secret and true or false
end

-- Returns the value only when it is a plain (non-secret) string.
function ns.SafeString(value)
    if value == nil or ns.IsSecret(value) or type(value) ~= "string" then return nil end
    return value
end

function ns.LowerText(str)
    local s = (str or ""):lower()
    -- Cyrillic capitals (UTF-8) to lower case
    s = s:gsub("\208([\144-\159])", function(c) return "\208" .. string.char(c:byte() + 32) end)
    s = s:gsub("\208([\160-\175])", function(c) return "\209" .. string.char(c:byte() - 32) end)
    s = s:gsub("\208\129", "\209\145")
    return s
end

-- Removes colour codes, textures and hyperlinks (keeps the link text).
function ns.StripCodes(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1")
    text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    text = text:gsub("{[^}]*}", " ")
    text = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

function ns.GetVersion()
    local getter = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    if type(getter) == "function" then
        local ok, ver = pcall(getter, ns.ADDON_NAME, "Version")
        if ok and type(ver) == "string" and ver ~= "" and not ver:find("^@") then
            return ver
        end
    end
    return ""
end

function ns.Print(msg)
    print("|cff" .. ns.Style.accentHex .. "EzWoW - Group Finder:|r " .. tostring(msg or ""))
end

function ns.PlayerLevel()
    local ok, level = pcall(UnitLevel, "player")
    level = ok and not ns.IsSecret(level) and tonumber(level) or nil
    return level or 1
end

-- WoW Forever names have a surname ("드라이브 쓰랄"); UnitName returns it as a second value.
function ns.PlayerName()
    if NameUtil and type(NameUtil.FormatUnitNameForDisplay) == "function" then
        local ok, full = pcall(NameUtil.FormatUnitNameForDisplay, "player")
        full = ok and ns.SafeString(full)
        if full and full ~= "" then return full end
    end
    local ok, first, second = pcall(UnitName, "player")
    first, second = ok and ns.SafeString(first) or "", ok and ns.SafeString(second) or nil
    if second and second ~= "" then
        local okRealm, realm = pcall(GetRealmName)
        realm = okRealm and ns.SafeString(realm) or nil
        if realm ~= second then return first .. ns.SurnameSeparator() .. second end
    end
    return first
end

-- Separator between first name and surname (the client's own constant when it has one).
function ns.SurnameSeparator()
    local consts = Constants and Constants.CharacterNameSeparatorConsts
    local sep = consts and consts.CHARACTERNAME_SURNAME_SEPARATOR
    if type(sep) == "string" and sep ~= "" and not ns.IsSecret(sep) then return sep end
    return " "
end

-- True when a chat sender is this character (GUID first, then the name with or without surname).
function ns.IsMe(guid, shortName)
    guid = ns.SafeString(guid)
    if guid and guid ~= "" then
        local ok, mine = pcall(UnitGUID, "player")
        if ok and ns.SafeString(mine) then return mine == guid end
    end
    if not shortName or shortName == "" then return false end
    if shortName == ns.PlayerName() then return true end
    local ok, first = pcall(UnitName, "player")
    return ok and ns.SafeString(first) == shortName
end

function ns.ShortName(fullName)
    if type(fullName) ~= "string" then return "" end
    if type(Ambiguate) == "function" then
        local ok, short = pcall(Ambiguate, fullName, "short")
        if ok and type(short) == "string" and short ~= "" then return short end
    end
    return (fullName:gsub("%-.*$", ""))
end

function ns.ClassColor(classFile)
    if type(classFile) ~= "string" then return nil end
    if C_ClassColor and type(C_ClassColor.GetClassColor) == "function" then
        local ok, color = pcall(C_ClassColor.GetClassColor, classFile)
        if ok and color and color.r then return color.r, color.g, color.b end
    end
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if color then return color.r, color.g, color.b end
    return nil
end

-- Fits a font string into maxWidth by shrinking, then trimming with "...".
function ns.FitText(fs, text, maxWidth, baseSize, minSize)
    if not fs then return end
    text = text or ""
    fs:SetWordWrap(false)
    if fs.SetTextScale then fs:SetTextScale(1) end
    local font, rawSize, flags = fs:GetFont()
    if not font then
        fs:SetText(text)
        return
    end
    local function applySize(size)
        if fs.SetTextScale and rawSize and rawSize > 0 then
            fs:SetTextScale(size / rawSize)
        else
            fs:SetFont(font, size, flags)
        end
    end
    applySize(baseSize)
    fs:SetText(text)
    local size = baseSize
    while fs:GetStringWidth() > maxWidth and size > minSize do
        size = size - 0.5
        applySize(size)
    end
    if fs:GetStringWidth() > maxWidth then
        local original = text
        while #text > 0 and fs:GetStringWidth() > maxWidth do
            -- drop the whole last character (all bytes of a Korean / Chinese letter)
            local cut = #text
            while cut > 1 and string.byte(text, cut) >= 128 and string.byte(text, cut) < 192 do
                cut = cut - 1
            end
            text = text:sub(1, cut - 1)
            fs:SetText(text .. "...")
            if text == original then break end
        end
    end
end

-----------------------------------------------------------------------------
-- SavedVariables
-----------------------------------------------------------------------------
local function fillDefaults(db, defaults)
    for key, value in pairs(defaults) do
        if db[key] == nil then
            if type(value) == "table" then db[key] = {} else db[key] = value end
        end
    end
end

function ns:InitDB()
    if type(_G.EzWoW_GroupFinderDB) ~= "table" then _G.EzWoW_GroupFinderDB = {} end
    local db = _G.EzWoW_GroupFinderDB
    fillDefaults(db, self.DEFAULTS)
    for _, key in ipairs({ "watch", "blocked", "frames", "compose" }) do
        if type(db[key]) ~= "table" then db[key] = {} end
    end
    fillDefaults(db.compose, self.COMPOSE_DEFAULTS)
    if type(db.compose.roles) ~= "table" then db.compose.roles = {} end
    db.expireMinutes = math.max(3, math.min(30, tonumber(db.expireMinutes) or 10))
    db.compose.size = math.max(1, math.min(4, tonumber(db.compose.size) or 1))
    self.db = db
end

-----------------------------------------------------------------------------
-- Bootstrap
-----------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(self, event, name)
    if name ~= ns.ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")
    ns:InitDB()
    if ns.StartCollector then ns.StartCollector() end
    if ns.CreateLauncher then ns.CreateLauncher() end
    if ns.RegisterBlizzardOptions then ns:RegisterBlizzardOptions() end
end)

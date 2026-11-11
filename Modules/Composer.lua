--===========================================================================
-- EzWoW - Group Finder
-- Modules/Composer.lua : Builds the recruitment message and sends it to chat
--===========================================================================
local _, ns = ...
local type, ipairs, tonumber, tostring, pcall = type, ipairs, tonumber, tostring, pcall

ns.SEND_COOLDOWN = 30
ns.lastSendTime = nil

local ROLE_ORDER = { "tank", "healer", "dps" }
local ROLE_TEXT = {
    ko = { tank = "탱", healer = "힐", dps = "딜" },
    en = { tank = "Tank", healer = "Healer", dps = "DPS" },
}

-- Chat posts go out in Korean for a Korean UI, English otherwise.
local function chatLang()
    return ns:GetActiveLang() == "koKR" and "ko" or "en"
end

local function chatDungeonName(key, lang)
    local dungeon = ns.DungeonByKey[key]
    if not dungeon then
        if key == "quest" then return lang == "ko" and "퀘스트" or "quest" end
        return ""
    end
    return lang == "ko" and dungeon.name.koKR or dungeon.name.enUS
end

local function rolesText(roles, lang)
    local out = {}
    for _, role in ipairs(ROLE_ORDER) do
        if roles[role] then out[#out + 1] = ROLE_TEXT[lang][role] end
    end
    return table.concat(out, ", ")
end

-- Trims to the 255-byte chat limit without splitting a multi-byte letter.
local function clampChat(text)
    if #text <= 255 then return text end
    local cut = 255
    while cut > 1 and string.byte(text, cut + 1) and string.byte(text, cut + 1) >= 128 and string.byte(text, cut + 1) < 192 do
        cut = cut - 1
    end
    return text:sub(1, cut)
end

function ns.BuildPostText(c)
    local lang = chatLang()
    local dungeon = chatDungeonName(c.dungeon, lang)
    local roles = rolesText(c.roles or {}, lang)
    local size = math.max(1, math.min(4, tonumber(c.size) or 1))
    local note = (c.note or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local level = ns.PlayerLevel()
    local text

    if c.mode == "lfg" then
        if lang == "ko" then
            text = (dungeon ~= "" and (dungeon .. " ") or "") .. "파티 구합니다 -"
                .. (roles ~= "" and (" " .. roles) or "") .. " " .. level .. "레벨"
        else
            text = "LFG" .. (dungeon ~= "" and (" " .. dungeon) or "") .. " -"
                .. (roles ~= "" and (" " .. roles) or "") .. " lvl " .. level
        end
    else
        if lang == "ko" then
            text = (dungeon ~= "" and (dungeon .. " ") or "")
                .. (roles ~= "" and roles or "파티원") .. " 구합니다 (" .. size .. "/5)"
        else
            text = "LF" .. (5 - size) .. "M" .. (dungeon ~= "" and (" " .. dungeon) or "")
                .. (roles ~= "" and (" - need " .. roles) or "")
        end
    end
    if note ~= "" then text = text .. " - " .. note end
    return clampChat(text)
end

-----------------------------------------------------------------------------
-- Send targets
-----------------------------------------------------------------------------
local function joinedChannels()
    local out = {}
    if type(GetChannelName) ~= "function" then return out end
    for index = 1, 20 do
        local ok, id, name = pcall(GetChannelName, index)
        if ok and type(id) == "number" and id > 0 and type(name) == "string" and not ns.IsSecret(name) and name ~= "" then
            out[#out + 1] = { id = id, name = name }
        end
    end
    return out
end

local function inGuild()
    if type(IsInGuild) ~= "function" then return false end
    local ok, value = pcall(IsInGuild)
    return ok and value == true
end

-- { value = "say" | "yell" | "guild" | "c:<channel name>", text = label }
function ns.GetSendTargets()
    local items = {}
    for _, channel in ipairs(joinedChannels()) do
        items[#items + 1] = { value = "c:" .. channel.name, text = channel.id .. ". " .. channel.name }
    end
    items[#items + 1] = { value = "say", text = function() return ns:L("chSay") end }
    items[#items + 1] = { value = "yell", text = function() return ns:L("chYell") end }
    if inGuild() then
        items[#items + 1] = { value = "guild", text = function() return ns:L("chGuild") end }
    end
    return items
end

local PREFERRED = { "파티찾기", "lookingforgroup", "lfg", "공개", "general" }

function ns.DefaultSendTarget()
    local channels = joinedChannels()
    -- the player's own group channels first, then the server's group-finding channel
    for _, custom in ipairs(ns.GetCustomChannelNames and ns.GetCustomChannelNames() or {}) do
        for _, channel in ipairs(channels) do
            if ns.LowerText(channel.name) == ns.LowerText(custom) then return "c:" .. channel.name end
        end
    end
    for _, channel in ipairs(channels) do
        if ns.IsLFGChannelName and ns.IsLFGChannelName(channel.name) then return "c:" .. channel.name end
    end
    for _, word in ipairs(PREFERRED) do
        for _, channel in ipairs(channels) do
            if ns.LowerText(channel.name):find(word, 1, true) then return "c:" .. channel.name end
        end
    end
    return "say"
end

function ns.SendTargetLabel(value)
    for _, item in ipairs(ns.GetSendTargets()) do
        if item.value == value then
            return type(item.text) == "function" and item.text() or item.text
        end
    end
    return nil
end

function ns.SendCooldownLeft()
    if not ns.lastSendTime then return 0 end
    return math.max(0, math.ceil(ns.SEND_COOLDOWN - (GetTime() - ns.lastSendTime)))
end

local function sendChat(text, chatType, target)
    if C_ChatInfo and type(C_ChatInfo.SendChatMessage) == "function" then
        return pcall(C_ChatInfo.SendChatMessage, text, chatType, nil, target)
    end
    if type(SendChatMessage) == "function" then
        return pcall(SendChatMessage, text, chatType, nil, target)
    end
    return false
end

-- Must run from a click (channel messages need a hardware event).
function ns.SendPost(text, targetValue)
    text = clampChat(((text or ""):gsub("[\r\n]+", " ")):gsub("^%s+", ""):gsub("%s+$", ""))
    if text == "" then return false end
    if ns.SendCooldownLeft() > 0 then return false end
    local ok
    if targetValue == "say" then
        ok = sendChat(text, "SAY")
    elseif targetValue == "yell" then
        ok = sendChat(text, "YELL")
    elseif targetValue == "guild" then
        ok = sendChat(text, "GUILD")
    elseif type(targetValue) == "string" and targetValue:sub(1, 2) == "c:" then
        local okId, id = pcall(GetChannelName, targetValue:sub(3))
        if not okId or type(id) ~= "number" or id <= 0 then
            ns.Print(ns:L("noChannel"))
            return false
        end
        ok = sendChat(text, "CHANNEL", id)
    end
    if ok then ns.lastSendTime = GetTime() end
    return ok and true or false
end

-----------------------------------------------------------------------------
-- Repeat reminder: chat posts can't be sent by a timer (the game wants a
-- click or a key press), so when the time comes a reminder with a "post
-- again" button shows up; one click (or the key binding) posts it again.
-----------------------------------------------------------------------------
ns.REPEAT_CHOICES = { 0, 60, 90, 120, 180 }
ns.REPEAT_MAX = 10

local repeatState   -- { text, target, mode, count, nextAt, due }

function ns.RepeatInterval()
    local every = ns.db and ns.db.compose and tonumber(ns.db.compose.repeatEvery) or 0
    return every or 0
end

function ns.RepeatInfo() return repeatState end

function ns.StopRepeat(silent)
    if repeatState and not silent then ns.Print(ns:L("repeatStopped")) end
    repeatState = nil
    if ns.HideRepostReminder then ns.HideRepostReminder() end
end

-- called after a post went out from the post tab
function ns.StartRepeat(text, target, mode)
    local every = ns.RepeatInterval()
    if every <= 0 then repeatState = nil return end
    repeatState = { text = text, target = target, mode = mode, count = 1, nextAt = GetTime() + every }
end

local function groupDone(state)
    if type(IsInGroup) ~= "function" or not IsInGroup() then return false end
    -- looking for a group: being in one is enough
    if state.mode == "lfg" then return true end
    local n = type(GetNumGroupMembers) == "function" and GetNumGroupMembers() or 0
    return n >= 5
end

-- Must run from a click or a key binding.
function ns.RepostNow()
    local state = repeatState
    if not state then return false end
    if ns.SendCooldownLeft() > 0 then return false end
    if not ns.SendPost(state.text, state.target) then return false end
    state.count = state.count + 1
    state.due = false
    if ns.HideRepostReminder then ns.HideRepostReminder() end
    if state.count >= ns.REPEAT_MAX then
        repeatState = nil
        ns.Print(ns:L("repeatDone"))
    else
        state.nextAt = GetTime() + math.max(ns.RepeatInterval(), ns.SEND_COOLDOWN)
    end
    return true
end

local function repeatTick()
    local state = repeatState
    if not state then return end
    if groupDone(state) then
        ns.StopRepeat(true)
        ns.Print(ns:L("repeatGroupFull"))
        return
    end
    if state.due or GetTime() < state.nextAt then return end
    state.due = true
    if ns.ShowRepostReminder then ns.ShowRepostReminder(state) end
    if PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then pcall(PlaySound, SOUNDKIT.READY_CHECK, "Master") end
end

if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, function() pcall(repeatTick) end) end

-- key binding (Key Bindings > AddOns): a key press can post to chat
_G.EzWoW_GroupFinderRepost = function() ns.RepostNow() end
do
    local ko = GetLocale and GetLocale() == "koKR"
    _G.BINDING_HEADER_EZWOWGF = "EzWoW - Group Finder"
    _G.BINDING_NAME_EZWOW_GF_REPOST = ko and "모집글 다시 올리기" or "Post the group message again"
end

-----------------------------------------------------------------------------
-- Whisper / invite
-----------------------------------------------------------------------------
function ns.WhisperPlayer(name)
    if type(name) ~= "string" or name == "" then return end
    -- names can contain a space (surname), so set the whisper target directly
    -- instead of typing "/w name", which would cut the name at the space
    local sendTell = (ChatFrameUtil and type(ChatFrameUtil.SendTell) == "function" and ChatFrameUtil.SendTell)
        or (type(ChatFrame_SendTell) == "function" and ChatFrame_SendTell)
    if sendTell and pcall(sendTell, name) then return end
    local line = "/w " .. name .. " "
    if ChatFrameUtil and type(ChatFrameUtil.OpenChat) == "function" then
        pcall(ChatFrameUtil.OpenChat, line)
    elseif type(ChatFrame_OpenChat) == "function" then
        pcall(ChatFrame_OpenChat, line)
    end
end

-----------------------------------------------------------------------------
-- One-click join whisper: "Healer for <dungeon>? Level 28 Druid."
-----------------------------------------------------------------------------
local CLASS_ROLES = {
    WARRIOR = { tank = true, dps = true },
    PALADIN = { tank = true, healer = true, dps = true },
    DRUID   = { tank = true, healer = true, dps = true },
    PRIEST  = { healer = true, dps = true },
    SHAMAN  = { healer = true, dps = true },
}

-- the roles this character's class can play
function ns.MyClassRoles()
    local _, class = UnitClass("player")
    return CLASS_ROLES[class] or { dps = true }
end

local JOIN_ROLE = {
    ko = { tank = "탱으로", healer = "힐로", dps = "딜로" },
    en = { tank = "tank", healer = "healer", dps = "DPS" },
}

function ns.BuildJoinWhisper(post, role)
    local lang = chatLang()
    local className = UnitClass("player") or ""
    local level = ns.PlayerLevel()
    local dungeon = ""
    if type(post) == "table" and type(post.keys) == "table" and #post.keys == 1 then
        dungeon = chatDungeonName(post.keys[1], lang)
    end
    if lang == "ko" then
        return clampChat((dungeon ~= "" and (dungeon .. " ") or "") .. JOIN_ROLE.ko[role]
            .. " 같이 가도 될까요? " .. level .. "레벨 " .. className .. "입니다.")
    end
    return clampChat("Hi! Can I join" .. (dungeon ~= "" and (" " .. dungeon) or "") .. " as "
        .. JOIN_ROLE.en[role] .. "? Level " .. level .. " " .. className .. ".")
end

local joinSentAt = {}

-- Sends the whisper at once; the same player is not whispered again for a few seconds
function ns.SendJoinWhisper(post, role)
    if type(post) ~= "table" or type(post.sender) ~= "string" or post.sender == "" then return false end
    if not JOIN_ROLE.en[role] then return false end
    local last = joinSentAt[post.sender]
    if last and GetTime() - last < 5 then return false end
    -- the sender exactly as the game gave it (a realm name added would fail)
    local ok = sendChat(ns.BuildJoinWhisper(post, role), "WHISPER", post.sender)
    if ok then joinSentAt[post.sender] = GetTime() end
    return ok and true or false
end

function ns.InvitePlayer(name)
    if type(name) ~= "string" or name == "" then return end
    if C_PartyInfo and type(C_PartyInfo.InviteUnit) == "function" then
        pcall(C_PartyInfo.InviteUnit, name)
    elseif type(InviteUnit) == "function" then
        pcall(InviteUnit, name)
    end
end

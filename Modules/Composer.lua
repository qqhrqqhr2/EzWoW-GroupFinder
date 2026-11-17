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

-- Where the item / quest links are: { {first byte, last byte}, ... } with
-- their colour code and "|r" (a link cut in two is not sent by the game).
local function linkSpans(text)
    local spans, pos = {}, 1
    while true do
        local s, e = text:find("|H.-|h.-|h", pos)
        if not s then break end
        local before = text:sub(1, s - 1)
        local colour = before:match("()|c%x%x%x%x%x%x%x%x$") or before:match("()|cn[^|:]*:$")
        if colour then s = colour end
        if text:sub(e + 1, e + 2) == "|r" then e = e + 2 end
        spans[#spans + 1] = { s, e }
        pos = e + 1
    end
    return spans
end

-- Trims to the 255-byte chat limit without splitting a multi-byte letter or a link.
local function clampChat(text, limit)
    limit = limit or 255
    if #text <= limit then return text end
    local cut = limit
    while cut > 1 and string.byte(text, cut + 1) and string.byte(text, cut + 1) >= 128 and string.byte(text, cut + 1) < 192 do
        cut = cut - 1
    end
    for _, span in ipairs(linkSpans(text)) do
        if span[1] <= cut and span[2] > cut then cut = span[1] - 1 break end
    end
    return (text:sub(1, cut):gsub("%s+$", ""))
end
ns.ClampChat = clampChat

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
-- Send targets: "say", "yell", "guild" or "c:<channel>". A zone channel is
-- kept without its zone ("공개 - 엘윈 숲" -> "c:공개") so it stays picked in
-- every zone. Several targets can be picked; one click posts to all of them.
-----------------------------------------------------------------------------
local function channelBase(name)
    return (name:match("^(.-) %- ") or name)
end

local function joinedChannels()
    local out = {}
    if type(GetChannelName) ~= "function" then return out end
    for index = 1, 30 do
        local ok, id, name = pcall(GetChannelName, index)
        if ok and type(id) == "number" and id > 0 and type(name) == "string" and not ns.IsSecret(name) and name ~= ""
            -- the hidden EzWoW data channels are not for chat
            and not ns.LowerText(name):find("^ezwow") then
            out[#out + 1] = { id = id, name = name, base = channelBase(name) }
        end
    end
    return out
end

-- "c:공개 - 가시덤불" (older saves) -> "c:공개"; nil for anything unknown
function ns.NormalizeTarget(value)
    if value == "say" or value == "yell" or value == "guild" then return value end
    if type(value) == "string" and value:sub(1, 2) == "c:" and #value > 2 then
        return "c:" .. channelBase(value:sub(3))
    end
    return nil
end

local function sameTarget(a, b)
    return a == b or (type(a) == "string" and type(b) == "string" and ns.LowerText(a) == ns.LowerText(b))
end

-- the joined channel for "c:<name>", or nil when not in it right now
local function findChannel(value)
    local base = value:sub(3)
    for _, channel in ipairs(joinedChannels()) do
        if sameTarget(channel.base, base) then return channel end
    end
    return nil
end

local function inGuild()
    if type(IsInGuild) ~= "function" then return false end
    local ok, value = pcall(IsInGuild)
    return ok and value == true
end

-- { value = "say" | "yell" | "guild" | "c:<channel name>", text = label, short = short label }
function ns.GetSendTargets()
    local items = {}
    for _, channel in ipairs(joinedChannels()) do
        items[#items + 1] = { value = "c:" .. channel.base, text = channel.id .. ". " .. channel.name,
            short = channel.id .. ". " .. channel.base }
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
            if ns.LowerText(channel.name) == ns.LowerText(custom) then return "c:" .. channel.base end
        end
    end
    for _, channel in ipairs(channels) do
        if ns.IsLFGChannelName and ns.IsLFGChannelName(channel.name) then return "c:" .. channel.base end
    end
    for _, word in ipairs(PREFERRED) do
        for _, channel in ipairs(channels) do
            if ns.LowerText(channel.name):find(word, 1, true) then return "c:" .. channel.base end
        end
    end
    return "say"
end

local function findItem(value)
    for _, item in ipairs(ns.GetSendTargets()) do
        if sameTarget(item.value, value) then return item end
    end
    return nil
end

local function itemText(item, short)
    local text = short and item.short or item.text
    if type(text) == "function" then text = text() end
    return text
end

function ns.SendTargetLabel(value)
    local item = findItem(value)
    return item and itemText(item) or nil
end

-- The picked targets of the post tab (compose state): cleaned, never empty.
-- Targets not available right now (a city channel outside the city) stay
-- picked; they are left out when sending.
function ns.ComposeTargets(c)
    local list = type(c.channels) == "table" and c.channels or {}
    if #list == 0 and type(c.channel) == "string" then list[1] = c.channel end
    c.channel = nil
    local out = {}
    for _, value in ipairs(list) do
        value = ns.NormalizeTarget(value)
        local dup = false
        for _, have in ipairs(out) do
            if sameTarget(have, value) then dup = true break end
        end
        if value and not dup then out[#out + 1] = value end
    end
    if #out == 0 then out[1] = ns.DefaultSendTarget() end
    c.channels = out
    return out
end

function ns.IsTargetPicked(c, value)
    for _, have in ipairs(ns.ComposeTargets(c)) do
        if sameTarget(have, value) then return true end
    end
    return false
end

-- Picks or unpicks one target; the last one stays picked.
function ns.ToggleTarget(c, value)
    local list = ns.ComposeTargets(c)
    for i, have in ipairs(list) do
        if sameTarget(have, value) then
            if #list > 1 then table.remove(list, i) end
            return
        end
    end
    value = ns.NormalizeTarget(value)
    if value then list[#list + 1] = value end
end

-- Menu rows: what can be picked now, then picked targets that are not available now.
function ns.TargetMenuItems(c)
    local items = ns.GetSendTargets()
    for _, value in ipairs(ns.ComposeTargets(c)) do
        if not findItem(value) then
            items[#items + 1] = { value = value, text = value:sub(1, 2) == "c:" and value:sub(3) or value,
                sub = ns:L("chGone"), color = ns.Style and ns.Style.textMuted }
        end
    end
    return items
end

-- Button text for the picked targets ("1. 공개, 2. 파티찾기").
function ns.TargetsLabel(c)
    local list = ns.ComposeTargets(c)
    local parts = {}
    for _, value in ipairs(list) do
        local item = findItem(value)
        if item then
            parts[#parts + 1] = itemText(item, #list > 1)
        else
            parts[#parts + 1] = "|cff7f7f7f" .. (value:sub(1, 2) == "c:" and value:sub(3) or value)
                .. " (" .. ns:L("chGone") .. ")|r"
        end
    end
    return table.concat(parts, ", ")
end

-- Picked targets in menu order (channels by number, then say / yell / guild).
local function orderedTargets(list)
    local out, used = {}, {}
    for _, item in ipairs(ns.GetSendTargets()) do
        for i, value in ipairs(list) do
            if not used[i] and sameTarget(item.value, value) then
                used[i] = true
                out[#out + 1] = value
            end
        end
    end
    for i, value in ipairs(list) do
        if not used[i] then out[#out + 1] = value end
    end
    return out
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

local function sendTo(text, value)
    if value == "say" then return sendChat(text, "SAY") end
    if value == "yell" then return sendChat(text, "YELL") end
    if value == "guild" then return inGuild() and sendChat(text, "GUILD") end
    if type(value) == "string" and value:sub(1, 2) == "c:" then
        local channel = findChannel(value)
        if channel then return sendChat(text, "CHANNEL", channel.id) end
    end
    return false
end

-- Must run from a click (channel messages need a hardware event); one click
-- posts to every picked target. targets: one value or a list.
-- Returns sent (true/false), how many got it, how many were picked.
function ns.SendPost(text, targets)
    text = ((text or ""):gsub("[\r\n]+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
    text = clampChat(text)
    if text == "" then return false end
    if ns.SendCooldownLeft() > 0 then return false end
    if type(targets) ~= "table" then targets = { targets } end
    local sent, tried = 0, 0
    for _, value in ipairs(orderedTargets(targets)) do
        tried = tried + 1
        if sendTo(text, value) then sent = sent + 1 end
    end
    if sent == 0 then
        ns.Print(ns:L("noChannel"))
        return false, 0, tried
    end
    ns.lastSendTime = GetTime()
    return true, sent, tried
end

-----------------------------------------------------------------------------
-- Quest links for the post
-----------------------------------------------------------------------------
-- quests in the log: { { questID, title, level }, ... } (headers and hidden ones left out)
function ns.LogQuests()
    local out = {}
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then return out end
    local ok, count = pcall(C_QuestLog.GetNumQuestLogEntries)
    count = ok and not ns.IsSecret(count) and tonumber(count) or 0
    for i = 1, count do
        local okInfo, info = pcall(C_QuestLog.GetInfo, i)
        if okInfo and type(info) == "table" and not info.isHeader and not info.isHidden then
            local id, title, level = info.questID, info.title, info.level
            if type(id) == "number" and not ns.IsSecret(id) and id > 0
                and type(title) == "string" and not ns.IsSecret(title) and title ~= "" then
                out[#out + 1] = { questID = id, title = title,
                    level = (type(level) == "number" and not ns.IsSecret(level)) and level or nil }
            end
        end
    end
    return out
end

-- the game's quest link, or the name in brackets when there is none
function ns.QuestLink(questID, title)
    local fns = {}
    if C_QuestLog and type(C_QuestLog.GetQuestLink) == "function" then fns[#fns + 1] = C_QuestLog.GetQuestLink end
    if type(GetQuestLink) == "function" then fns[#fns + 1] = GetQuestLink end
    for _, fn in ipairs(fns) do
        local ok, link = pcall(fn, questID)
        if ok and type(link) == "string" and not ns.IsSecret(link) and link:find("|H", 1, true) then return link end
    end
    if type(title) == "string" and title ~= "" then return "[" .. title .. "]" end
    return nil
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
    local targets = {}
    for _, value in ipairs(type(target) == "table" and target or { target }) do targets[#targets + 1] = value end
    repeatState = { text = text, target = targets, mode = mode, count = 1, nextAt = GetTime() + every }
end

-- a short sound for the reminder (the first one this client has)
local REMIND_SOUNDS = { "MAP_PING", "IG_PLAYER_INVITE", "TELL_MESSAGE", "READY_CHECK" }
local function playRemindSound()
    if type(PlaySound) ~= "function" or type(SOUNDKIT) ~= "table" then return end
    for _, key in ipairs(REMIND_SOUNDS) do
        local id = SOUNDKIT[key]
        if type(id) == "number" then
            pcall(PlaySound, id, "Master")
            return
        end
    end
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
    playRemindSound()
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
    -- with the gamepad UI on, the chat box opened from addon code breaks the game's
    -- gamepad navigation until the interface is reloaded (Libs/EzWoWGamePad): the name only
    if ns.GamePad and ns.GamePad.IsActive and ns.GamePad.IsActive() then
        ns.Print(ns:L("padWhisper"):format(name))
        return
    end
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

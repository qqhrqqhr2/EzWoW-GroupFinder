--===========================================================================
-- EzWoW - Group Finder
-- Modules/Channels.lua : Finds and joins the server's group-finding chat channel
--===========================================================================
local _, ns = ...
local type, ipairs, pcall, select = type, ipairs, pcall, select

-- Words that identify the group-finding channel in every client language
-- (compared in lower case with spaces removed).
local LFG_HINTS = {
    "파티찾기", "lookingforgroup", "suchenachgruppe", "recherchedegroupe",
    "buscargrupo", "поискспутников", "寻求组队", "尋求組隊",
}

local function compact(name)
    return (ns.LowerText(name or ""):gsub("%s+", ""))
end

function ns.IsLFGChannelName(name)
    if type(name) ~= "string" or ns.IsSecret(name) then return false end
    local key = compact(name)
    for _, hint in ipairs(LFG_HINTS) do
        if key:find(hint, 1, true) then return true end
    end
    return false
end

-- Names of the server's built-in channels (General, Trade, group finding, ...).
function ns.GetServerChannels()
    local out = {}
    if type(EnumerateServerChannels) ~= "function" then return out end
    local ok, list = pcall(function() return { EnumerateServerChannels() } end)
    if not ok or type(list) ~= "table" then return out end
    for _, name in ipairs(list) do
        if type(name) == "string" and not ns.IsSecret(name) and name ~= "" then out[#out + 1] = name end
    end
    return out
end

-- Channels the player is in: { { id, name }, ... }
function ns.GetJoinedChannels()
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

-- The joined group-finding channel, if any.
function ns.GetJoinedLFGChannel()
    for _, channel in ipairs(ns.GetJoinedChannels()) do
        if ns.IsLFGChannelName(channel.name) then return channel end
    end
    return nil
end

function ns.FindLFGServerChannel()
    for _, name in ipairs(ns.GetServerChannels()) do
        if ns.IsLFGChannelName(name) then return name end
    end
    return nil
end

-- The game's General channel in every client language ("공개 - 오그리마": the
-- part before " - ", compared in lower case with spaces removed).
local GENERAL_NAMES = {
    "공개", "general", "allgemein", "général", "geral", "generale", "общий", "综合", "綜合",
}

function ns.IsGeneralChannelName(name)
    if type(name) ~= "string" or ns.IsSecret(name) then return false end
    local key = compact(name:match("^(.-)%s+%-%s") or name)
    for _, word in ipairs(GENERAL_NAMES) do
        if key == word then return true end
    end
    return false
end

-- The joined General channel, if any.
function ns.GetJoinedGeneralChannel()
    for _, channel in ipairs(ns.GetJoinedChannels()) do
        if ns.IsGeneralChannelName(channel.name) then return channel end
    end
    return nil
end

-- Channel names the player typed in the settings ("파티, 던전팟" -> { "파티", "던전팟" }).
function ns.GetCustomChannelNames()
    local out = {}
    local text = ns.db and ns.db.joinChannels or ""
    for name in tostring(text):gmatch("[^,]+") do
        name = name:gsub("^%s+", ""):gsub("%s+$", "")
        if name ~= "" then out[#out + 1] = name end
    end
    return out
end

local function isJoined(name)
    local ok, id = pcall(GetChannelName, name)
    return ok and type(id) == "number" and id > 0
end

local function joinChannel(name)
    if isJoined(name) then return end
    local join = (C_ChatInfo and type(C_ChatInfo.JoinChannelByName) == "function" and C_ChatInfo.JoinChannelByName)
        or (type(JoinChannelByName) == "function" and JoinChannelByName)
        or (type(JoinTemporaryChannel) == "function" and JoinTemporaryChannel)
    if join then pcall(join, name) end
end

-- The group-finding channel is joined automatically only until the player has been in it
-- once this session; if the player leaves it, it stays left until the next login or until
-- the auto-join option is switched again.
local lfgJoinedOnce = false
local lfgLeftByPlayer = false
local lastLoadingTime = 0

-----------------------------------------------------------------------------
-- Channel numbers: a new channel gets the lowest free number, and the client
-- keeps the numbers for the next login. Joined before General, the
-- group-finding channel takes number 1 and General drops out of the list for
-- good (it is not joined again at the next login). Trade and the other game
-- channels often come in a few seconds before General, so they do not count:
-- other channels are joined only once General is there (or after a minute,
-- for a player who left General), and never sooner than JOIN_DELAY seconds
-- after a loading screen. A group-finding channel that already sits in front
-- of General is swapped behind it (once per character).
-----------------------------------------------------------------------------
local JOIN_DELAY = 15      -- seconds after a loading screen before joining
local GENERAL_WAIT = 60    -- seconds after login to wait for General
local CHECK_EVERY = 3
local ORDER_FIX = 2        -- ns.db.lfgOrderFixed value of this check (true: the old check, done again)

local function nowTime()
    return type(GetTime) == "function" and GetTime() or 0
end

local function inInstance()
    if type(IsInInstance) ~= "function" then return false end
    local ok, inside = pcall(IsInInstance)
    return ok and inside == true
end

local worldAt, firstWorldAt = nil, nil   -- the last / the first loading screen of this session

-- "ready": others may join now without taking General's number;
-- "wait": check again soon; "later": not here (an instance), the next loading screen checks again
local function channelState()
    if not worldAt then return "later" end
    local now = nowTime()
    if now - worldAt < JOIN_DELAY then return "wait" end
    if ns.GetJoinedGeneralChannel() then return "ready" end
    if now - (firstWorldAt or worldAt) < GENERAL_WAIT then return "wait" end
    -- General left on purpose, or not offered here
    if inInstance() then return "later" end
    return "ready"
end

local function characterKey()
    local guid = UnitGUID and UnitGUID("player")
    if type(guid) ~= "string" or ns.IsSecret(guid) then return nil end
    return guid
end

-- The player's leave of the group-finding channel, kept per character so it lasts
-- through /reload (cleared on a real login). value: true / false to set, nil to read.
local function savedLeft(value)
    local key = characterKey()
    if not (key and ns.db) then return false end
    if type(ns.db.lfgLeft) ~= "table" then ns.db.lfgLeft = {} end
    if value ~= nil then ns.db.lfgLeft[key] = value or nil end
    return ns.db.lfgLeft[key] == true
end

-- Puts General in front of a group-finding channel that took a lower number
-- (e.g. 1 when General came in late, or after /join 공개). Once per character,
-- so a player's own order afterwards stays.
-- true when nothing is left to do (done now, done before, or not needed)
local function fixLFGOrder()
    local key = characterKey()
    if not (key and ns.db) then return false end
    if type(ns.db.lfgOrderFixed) ~= "table" then ns.db.lfgOrderFixed = {} end
    if ns.db.lfgOrderFixed[key] == ORDER_FIX then return true end
    local lfg, general = ns.GetJoinedLFGChannel(), ns.GetJoinedGeneralChannel()
    if not (lfg and general) then return false end
    local swap = C_ChatInfo and type(C_ChatInfo.SwapChatChannelsByChannelIndex) == "function"
        and C_ChatInfo.SwapChatChannelsByChannelIndex
    if swap and lfg.id < general.id then
        if InCombatLockdown and InCombatLockdown() then return false end  -- retried after combat
        pcall(swap, lfg.id, general.id)
    end
    ns.db.lfgOrderFixed[key] = ORDER_FIX
    return true
end

local checkQueued = false
local function checkLater(seconds)
    if checkQueued or not (C_Timer and C_Timer.After) then return end
    checkQueued = true
    C_Timer.After(seconds, function()
        checkQueued = false
        ns.EnsureLFGChannel()
    end)
end

-- Joins the group-finding channel and the player's own channels in the background
-- (they are not added to any chat window; the addon still reads them).
-- fromOption: the auto-join option was just switched (clears a remembered leave).
function ns.EnsureLFGChannel(fromOption)
    if not ns.db then return end
    if fromOption == true then
        lfgLeftByPlayer = false
        lfgJoinedOnce = false
        savedLeft(false)
    end
    if savedLeft() then lfgLeftByPlayer = true end
    if ns.GetJoinedLFGChannel() then
        lfgJoinedOnce = true
        fixLFGOrder()
    end
    local state = channelState()
    if state == "wait" then
        local left = worldAt and (JOIN_DELAY - (nowTime() - worldAt)) or 0
        checkLater(left > 0 and left or CHECK_EVERY)
        return
    elseif state == "later" then
        return
    end
    for _, name in ipairs(ns.GetCustomChannelNames()) do joinChannel(name) end
    if not ns.GetJoinedLFGChannel() and ns.db.autoJoinLFG and not lfgJoinedOnce and not lfgLeftByPlayer then
        -- the same as typing /join 파티찾기 (or /join LookingForGroup)
        local locale = type(GetLocale) == "function" and GetLocale() or ""
        local name = ns.FindLFGServerChannel() or (locale == "koKR" and "파티찾기" or "LookingForGroup")
        joinChannel(name)
    end
    C_Timer.After(2, function() if ns.NotifyPostsChanged then ns.NotifyPostsChanged() end end)
end

-- Prints joined and server channels (/ezgf channels).
function ns.PrintChannels()
    local joined = {}
    for _, channel in ipairs(ns.GetJoinedChannels()) do
        joined[#joined + 1] = channel.id .. ". " .. channel.name .. (ns.IsLFGChannelName(channel.name) and " *" or "")
    end
    ns.Print(ns:L("channelsJoined") .. ": " .. (#joined > 0 and table.concat(joined, ", ") or "-"))
    local server = ns.GetServerChannels()
    ns.Print(ns:L("channelsServer") .. ": " .. (#server > 0 and table.concat(server, ", ") or "-"))
    local lfg = ns.FindLFGServerChannel()
    ns.Print(ns:L("channelsLFG") .. ": " .. (lfg or "-"))
end

local watcher = CreateFrame("Frame")
pcall(watcher.RegisterEvent, watcher, "PLAYER_ENTERING_WORLD")
pcall(watcher.RegisterEvent, watcher, "PLAYER_LEAVING_WORLD")
pcall(watcher.RegisterEvent, watcher, "CHANNEL_UI_UPDATE")
pcall(watcher.RegisterEvent, watcher, "CHAT_MSG_CHANNEL_NOTICE")
pcall(watcher.RegisterEvent, watcher, "PLAYER_REGEN_ENABLED")
watcher:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        lastLoadingTime = nowTime()
        worldAt = lastLoadingTime
        firstWorldAt = firstWorldAt or worldAt
        local isInitialLogin = ...
        if isInitialLogin == true then savedLeft(false) end
        -- the game's channels come in during the first seconds after a loading screen
        checkLater(JOIN_DELAY)
    elseif event == "PLAYER_LEAVING_WORLD" then
        lastLoadingTime = nowTime()
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- a channel swap skipped in combat
        fixLFGOrder()
    elseif event == "CHAT_MSG_CHANNEL_NOTICE" then
        local notice = ...
        local channelName = select(9, ...)
        local channelString = select(4, ...)
        if ns.IsSecret(notice) then return end
        local isLFG = ns.IsLFGChannelName(channelName) or ns.IsLFGChannelName(channelString)
        if isLFG and notice == "YOU_LEFT" then
            -- ignore leaves the client makes around a loading screen
            if nowTime() - lastLoadingTime > 5 then
                lfgLeftByPlayer = true
                savedLeft(true)
            end
        elseif isLFG and (notice == "YOU_JOINED" or notice == "YOU_CHANGED") then
            lfgJoinedOnce = true
            lfgLeftByPlayer = false
            savedLeft(false)
            C_Timer.After(1, fixLFGOrder)
        elseif (notice == "YOU_JOINED" or notice == "YOU_CHANGED")
            and (ns.IsGeneralChannelName(channelName) or ns.IsGeneralChannelName(channelString)) then
            -- General came back (/join 공개): put it in front of the group-finding channel
            C_Timer.After(1, fixLFGOrder)
        end
    elseif ns.NotifyPostsChanged then
        ns.NotifyPostsChanged()
    end
end)

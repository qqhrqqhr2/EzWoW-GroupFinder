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
-- keeps the numbers for the next login. Joined before the game's own channels
-- (General, Trade, ...), the group-finding channel would take number 1 and
-- push General down for good. So it is joined only once one of the game's
-- channels is there, and a group-finding channel that already sits in front
-- of them is swapped behind the first one (once per character).
-----------------------------------------------------------------------------
-- the game's own channel (not group finding) the player is in with the lowest number
local function firstGameChannel()
    local bases = {}
    for _, name in ipairs(ns.GetServerChannels()) do
        if not ns.IsLFGChannelName(name) then bases[#bases + 1] = name end
    end
    local best
    for _, channel in ipairs(ns.GetJoinedChannels()) do
        local name = channel.name
        if not ns.IsLFGChannelName(name) then
            -- "General - Elwynn Forest": zone channels carry the zone after " - "
            local isGame = name:find(" - ", 1, true) ~= nil
            for _, base in ipairs(bases) do
                if name == base or name:sub(1, #base + 3) == base .. " - " then isGame = true break end
            end
            if isGame and (not best or channel.id < best.id) then best = channel end
        end
    end
    return best
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

-- true when nothing is left to do (done now, done before, or not needed)
local function fixLFGOrder()
    local key = characterKey()
    if not (key and ns.db) then return false end
    if type(ns.db.lfgOrderFixed) ~= "table" then ns.db.lfgOrderFixed = {} end
    if ns.db.lfgOrderFixed[key] then return true end
    local lfg, first = ns.GetJoinedLFGChannel(), firstGameChannel()
    if not (lfg and first) then return false end
    local swap = C_ChatInfo and type(C_ChatInfo.SwapChatChannelsByChannelIndex) == "function"
        and C_ChatInfo.SwapChatChannelsByChannelIndex
    if swap and lfg.id < first.id then
        if InCombatLockdown and InCombatLockdown() then return false end  -- retried after combat
        pcall(swap, lfg.id, first.id)
    end
    ns.db.lfgOrderFixed[key] = true
    return true
end

local GAME_CHANNEL_WAIT = 30   -- seconds to wait for the game's channels after login
local waitedFor = 0

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
    local function retryLater()
        if waitedFor < GAME_CHANNEL_WAIT then
            waitedFor = waitedFor + 3
            C_Timer.After(3, function() ns.EnsureLFGChannel() end)
        end
    end
    -- the game's own channels are there (or we stopped waiting): others may join now
    -- without taking their numbers
    local gameReady = firstGameChannel() ~= nil or waitedFor >= GAME_CHANNEL_WAIT
    local customs = ns.GetCustomChannelNames()
    if gameReady then
        for _, name in ipairs(customs) do joinChannel(name) end
    end
    if ns.GetJoinedLFGChannel() then
        lfgJoinedOnce = true
        if not fixLFGOrder() or (not gameReady and #customs > 0) then retryLater() end
    elseif ns.db.autoJoinLFG and not lfgJoinedOnce and not lfgLeftByPlayer then
        -- the game's own channels are not there yet: wait so they keep their numbers
        if not gameReady then retryLater() return end
        -- the same as typing /join 파티찾기 (or /join LookingForGroup)
        local locale = type(GetLocale) == "function" and GetLocale() or ""
        local name = ns.FindLFGServerChannel() or (locale == "koKR" and "파티찾기" or "LookingForGroup")
        joinChannel(name)
    elseif not gameReady and #customs > 0 then
        retryLater()
        return
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

local function nowTime()
    return type(GetTime) == "function" and GetTime() or 0
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
        local isInitialLogin = ...
        if isInitialLogin == true then savedLeft(false) end
        -- the default channels are joined a few seconds after login
        C_Timer.After(6, function() ns.EnsureLFGChannel() end)
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
        end
    elseif ns.NotifyPostsChanged then
        ns.NotifyPostsChanged()
    end
end)

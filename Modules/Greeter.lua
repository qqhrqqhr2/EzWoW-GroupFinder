--===========================================================================
-- EzWoW - Group Finder
-- Modules/Greeter.lua : Hello lines when a party forms or someone joins it
--===========================================================================
-- greetSelf    : joining someone's party -> "Hello! Level 16 Restoration Druid."
-- greetWelcome : someone joins my party  -> "Welcome, nice to meet you!"
-- Parties only (no raids). Several people joining at once get one line. Lines
-- that can't be sent right now (chat locked in combat) wait a little.
local ADDON_NAME, ns = ...
local type, ipairs, pairs, pcall, tonumber = type, ipairs, pairs, pcall, tonumber

local Greeter = {}
ns.Greeter = Greeter

local function isSecret(value)
    return ns.IsSecret and ns.IsSecret(value) or false
end

local function opt(key)
    return ns.db and ns.db[key] == true
end

-----------------------------------------------------------------------------
-- Who am I: level, talent tree with the most points, class
-----------------------------------------------------------------------------
local function mainTalentTree()
    -- EzWoW - Tooltip reads the modern talent trees; use it when it is there
    local tooltipAddon = _G.EzWoW_Tooltip
    if type(tooltipAddon) == "table" and type(tooltipAddon.GetPlayerTalentTreeName) == "function" then
        local ok, name = pcall(tooltipAddon.GetPlayerTalentTreeName)
        if ok and type(name) == "string" and name ~= "" and not isSecret(name) then return name end
    end
    if not (GetNumTalentTabs and GetTalentTabInfo) then return nil end
    local ok, tabs = pcall(GetNumTalentTabs)
    if not ok or type(tabs) ~= "number" then return nil end
    local bestName, bestPoints = nil, 0
    for tab = 1, math.min(tabs, 3) do
        local okTab, a1, a2, a3, a4, a5 = pcall(GetTalentTabInfo, tab)
        if okTab and a1 ~= nil then
            -- older form: name, icon, points; newer form: id, name, description, icon, points
            local name, points
            if type(a1) == "number" then
                name, points = a2, tonumber(a5)
            else
                name, points = a1, tonumber(a3)
            end
            -- some clients report 0 spent points per tree: count the talents' ranks
            if (not points or points == 0) and GetNumTalents and GetTalentInfo then
                local okNum, num = pcall(GetNumTalents, tab)
                if okNum and type(num) == "number" then
                    local sum = 0
                    for index = 1, num do
                        local okInfo, r1, _, _, _, r5 = pcall(GetTalentInfo, tab, index)
                        if okInfo then
                            if type(r1) == "table" then
                                sum = sum + (tonumber(r1.rank) or 0)
                            else
                                sum = sum + (tonumber(r5) or 0)
                            end
                        end
                    end
                    points = sum
                end
            end
            if type(name) == "string" and points and points > bestPoints then
                bestName, bestPoints = name, points
            end
        end
    end
    return bestName
end

local function selfIntroduction()
    local level = UnitLevel and UnitLevel("player")
    if isSecret(level) or type(level) ~= "number" then level = nil end
    local className = UnitClass and UnitClass("player")
    if isSecret(className) or type(className) ~= "string" then className = nil end
    if not (level and className) then return nil end
    local tree = mainTalentTree()
    local who = tree and (tree .. " " .. className) or className
    return ns:L("greetSelfText"):format(level, who)
end

-----------------------------------------------------------------------------
-- Sending
-----------------------------------------------------------------------------
local function groupChannel()
    if IsInRaid and IsInRaid() then return nil end
    local instanceCat = LE_PARTY_CATEGORY_INSTANCE
    if instanceCat and IsInGroup and IsInGroup(instanceCat) then return "INSTANCE_CHAT" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return nil
end

local function chatLocked()
    if C_ChatInfo and type(C_ChatInfo.InChatMessagingLockdown) == "function" then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        if ok and not isSecret(locked) and locked then return true end
    end
    return false
end

-- tries for a while if chat is locked, then gives up (the moment has passed)
local function say(text, tries)
    if not text or text == "" then return end
    local channel = groupChannel()
    if not channel then return end
    if chatLocked() then
        tries = (tries or 0) + 1
        if tries <= 15 then C_Timer.After(2, function() say(text, tries) end) end
        return
    end
    local fn = (C_ChatInfo and C_ChatInfo.SendChatMessage) or _G.SendChatMessage
    if type(fn) == "function" then pcall(fn, text, channel) end
end

-----------------------------------------------------------------------------
-- Watching the party
-----------------------------------------------------------------------------
local inGroup = false
local members = {}        -- GUIDs of the others in the party
local welcomeQueued = false
local pendingWelcome = {} -- GUIDs of newcomers waiting for the welcome line

local function currentMembers()
    local list = {}
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then
            local guid = UnitGUID(unit)
            if guid and not isSecret(guid) then list[guid] = true end
        end
    end
    return list
end

-- name of the party member with this GUID, with the family name when there
-- is one ("Name Family"; a second value equal to a realm name is not added).
-- Names can arrive a moment after the member does, so this is read when the
-- line is sent.
local function memberName(guid)
    for i = 1, 4 do
        local unit = "party" .. i
        local unitGuid = UnitExists(unit) and UnitGUID(unit)
        if unitGuid and not isSecret(unitGuid) and unitGuid == guid then
            local name, second = UnitName(unit)
            if type(name) == "string" and name ~= "" and not isSecret(name)
                and name ~= (_G.UNKNOWNOBJECT or "") then
                if type(second) == "string" and second ~= "" and not isSecret(second) then
                    local realm = GetRealmName and GetRealmName() or ""
                    local normalized = GetNormalizedRealmName and GetNormalizedRealmName() or ""
                    if second ~= realm and second ~= normalized and second ~= realm:gsub("%s+", "") then
                        return name .. " " .. second
                    end
                end
                return name
            end
        end
    end
    return nil
end

local function welcomeLine(guids)
    local names, suffix = {}, ns:L("greetNameSuffix")
    if suffix == "greetNameSuffix" then suffix = "" end
    for _, guid in ipairs(guids) do
        local name = memberName(guid)
        if name then names[#names + 1] = name .. suffix end
    end
    if #names == 0 then return ns:L("greetWelcomeText") end
    return ns:L("greetWelcomeNamed"):format(table.concat(names, ", "))
end

local function queueWelcome(guid)
    if guid then pendingWelcome[#pendingWelcome + 1] = guid end
    if welcomeQueued then return end
    welcomeQueued = true
    -- a short wait: people joining together get one line, and the newcomer sees it
    C_Timer.After(2, function()
        welcomeQueued = false
        local guids = pendingWelcome
        pendingWelcome = {}
        if opt("greetWelcome") then say(welcomeLine(guids)) end
    end)
end

local function onRoster()
    local nowInGroup = (IsInGroup and IsInGroup()) and not (IsInRaid and IsInRaid()) or false
    if not nowInGroup then
        inGroup, members = false, {}
        return
    end
    local now = currentMembers()
    if not inGroup then
        inGroup = true
        local leader = UnitIsGroupLeader and UnitIsGroupLeader("player")
        if leader and not isSecret(leader) then
            -- my invite was accepted: the party just formed around me
            for guid in pairs(now) do queueWelcome(guid) end
            if not next(now) then queueWelcome() end
        else
            -- I joined someone's party
            C_Timer.After(2, function()
                if opt("greetSelf") then say(selfIntroduction()) end
            end)
        end
    else
        for guid in pairs(now) do
            if not members[guid] then queueWelcome(guid) end
        end
    end
    members = now
end

local events = CreateFrame("Frame")
pcall(events.RegisterEvent, events, "GROUP_ROSTER_UPDATE")
pcall(events.RegisterEvent, events, "PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        -- after a login or /reload the current party is not new
        inGroup = (IsInGroup and IsInGroup()) and not (IsInRaid and IsInRaid()) or false
        members = inGroup and currentMembers() or {}
        return
    end
    pcall(onRoster)
end)

--===========================================================================
-- EzWoW - Group Finder
-- Modules/Greeter.lua : Hello lines when a party forms or someone joins it
--===========================================================================
-- greetSelf    : joining someone's party -> "Hello! Level 16 Restoration Druid."
-- greetWelcome : someone joins my party  -> "Welcome, nice to meet you!"
-- Parties only (no raids). Several people joining at once get one line. Lines
-- that can't be sent right now (chat locked in combat) wait a little.
-- thankBuffs   : a player outside my group buffs me -> the /thank emote at them
--                (see "Thanks for buffs" below)
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

-----------------------------------------------------------------------------
-- Thanks for buffs
-----------------------------------------------------------------------------
-- A player outside my group puts a buff on me -> DoEmote("THANK") at them.
-- The caster is known only when the game has a unit for them (target,
-- mouseover, focus, a shown name plate): then the emote names them. A buff
-- from a player the game has no unit for is thanked without a name, and only
-- while I have no target (the emote would go to my target).
-- Out of combat and outside dungeons only, once per player every few
-- minutes, one emote every few seconds at most.
local THANK_AGAIN = 300   -- seconds before the same player is thanked again
local THANK_GAP = 3       -- seconds between two emotes
local THANK_QUEUE = 3     -- emotes waiting for their turn at most
local thankedAt = {}      -- player GUID (or "?") -> time
local thankQueue = {}
local lastThank, thankTimer, quietUntil = -100, false, 0

local function clock()
    return (GetTime and GetTime()) or 0
end

local function truthy(fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn, ...)
    return ok and not isSecret(value) and value and true or false
end

local function thankBlocked()
    if truthy(InCombatLockdown) or truthy(UnitAffectingCombat, "player") then return true end
    if truthy(IsInInstance) then return true end
    return chatLocked()
end

local function sendThanks()
    thankTimer = false
    if #thankQueue == 0 then return end
    local wait = THANK_GAP - (clock() - lastThank)
    if wait > 0 then
        thankTimer = true
        C_Timer.After(wait, sendThanks)
        return
    end
    local item = table.remove(thankQueue, 1)
    if opt("thankBuffs") and not thankBlocked() and type(DoEmote) == "function" then
        -- no name: only while nothing is targeted, or it would go to the target
        if item.name or not truthy(UnitExists, "target") then
            thankedAt[item.key] = clock()
            lastThank = clock()
            pcall(DoEmote, "THANK", item.name)
        end
    end
    if #thankQueue > 0 then
        thankTimer = true
        C_Timer.After(THANK_GAP, sendThanks)
    end
end

local function queueThanks(key, name)
    local at = thankedAt[key]
    if at and clock() - at < THANK_AGAIN then return end
    for _, item in ipairs(thankQueue) do
        if item.key == key then return end
    end
    if #thankQueue >= THANK_QUEUE then return end
    thankQueue[#thankQueue + 1] = { key = key, name = name }
    if not thankTimer then sendThanks() end
end

-- the name to thank for a unit that is another player outside my group
-- (nil: not such a player); the character name only, without a family name
local function strangerName(unit)
    if type(unit) ~= "string" or unit == "" or isSecret(unit) then return nil end
    if not truthy(UnitExists, unit) or not truthy(UnitIsPlayer, unit) then return nil end
    if truthy(UnitIsUnit, unit, "player") or truthy(UnitInParty, unit) or truthy(UnitInRaid, unit) then return nil end
    local ok, name = pcall(UnitName, unit)
    if not ok or type(name) ~= "string" or name == "" or isSecret(name) or name == (_G.UNKNOWNOBJECT or "") then return nil end
    return name
end

local function field(aura, key)
    local ok, value = pcall(function() return aura[key] end)
    if not ok or isSecret(value) then return nil end
    return value
end

local function onPlayerAura(info)
    if not opt("thankBuffs") or clock() < quietUntil then return end
    if type(info) ~= "table" or info.isFullUpdate or type(info.addedAuras) ~= "table" then return end
    if thankBlocked() then return end
    for _, aura in ipairs(info.addedAuras) do
        if type(aura) == "table" and field(aura, "isHelpful") == true and field(aura, "isFromPlayerOrPlayerPet") == true then
            local unit = field(aura, "sourceUnit")
            if type(unit) == "string" and unit ~= "" then
                local name = strangerName(unit)
                if name then
                    local okGuid, guid = pcall(UnitGUID, unit)
                    local key = (okGuid and type(guid) == "string" and not isSecret(guid)) and guid or name
                    queueThanks(key, name)
                end
            elseif unit == nil then
                -- cast by a player the game has no unit for (not me, my pet or my group: those have units)
                queueThanks("?", nil)
            end
        end
    end
end

local auraEvents = CreateFrame("Frame")
pcall(auraEvents.RegisterUnitEvent, auraEvents, "UNIT_AURA", "player")
pcall(auraEvents.RegisterEvent, auraEvents, "PLAYER_ENTERING_WORLD")
auraEvents:SetScript("OnEvent", function(_, event, _, info)
    if event == "PLAYER_ENTERING_WORLD" then
        -- auras coming back after a login, /reload or zone change are not new
        quietUntil = clock() + 5
        return
    end
    pcall(onPlayerAura, info)
end)

--===========================================================================
-- EzWoW - Group Finder
-- Modules/Collector.lua : Reads group posts from chat, keeps & filters them
--===========================================================================
local _, ns = ...
local type, pairs, ipairs, tonumber, tostring, pcall = type, pairs, ipairs, tonumber, tostring, pcall
local tinsert, tremove, wipe = table.insert, table.remove, wipe

ns.Posts = {}            -- newest first
local postBySender = {}  -- full sender name -> post
local listeners = {}
local nextId = 0

-----------------------------------------------------------------------------
-- Keyword tables
-----------------------------------------------------------------------------
-- Latin words are matched as whole words, anything else as a substring of the
-- message with all spaces removed (players write "통곡의동굴" and "통곡의 동굴").
local LFG_WORDS = {
    "lfg", "lf group", "lf grp", "looking for group", "lf party",
    "파티구", "팟구", "파티찾", "팟찾", "껴주", "끼워", "데려가", "구직",
}
local LFM_WORDS = {
    "lfm", "lf1m", "lf2m", "lf3m", "lf4m", "lf",
    "구함", "구해", "구합", "구하는", "구인", "모집", "오실분", "모십", "모셔", "갈분", "가실분", "갈사람", "급구", "자리남", "남은자리",
}
local BOOST_WORDS = { "boost", "boosting", "carry", "버스", "쩔" }
local TRADE_WORDS = { "wts", "wtb", "wtt", "selling", "buying", "팝니다", "삽니다", "판매", "구매", "시세", "경매장", "싸게", "가격", "골드" }
local GUILD_WORDS = { "길드", "guild" }
local GUILD_AD_WORDS = { "모집", "영입", "가입", "모십", "모셔", "구합", "구해", "환영", "recruit", "recruiting" }
-- "길드원" alone is always a guild advert
local GUILD_MEMBER_WORDS = { "길드원", "길원" }
-- without a dungeon name, a post needs one of these to count as a group post
local GROUP_WORDS = { "파티", "팟", "파원", "인원", "group", "grp", "party" }
local QUEST_WORDS = { "퀘", "quest", "엘리트", "정예", "elite" }
local ROLE_WORDS = {
    tank   = { "tank", "tanks", "탱" },
    healer = { "heal", "heals", "healer", "healers", "힐" },
    dps    = { "dps", "dd", "rdps", "mdps", "딜" },
}
-- Words that contain a role syllable but mean something else.
local ROLE_NOISE = { "힐즈", "힐스", "탱탱" }
-- a role written before one of these is wanted / already in the group
local NEED_MARKERS = { "구합", "구해", "구함", "구하", "모십", "모셔", "오세요", "오실", "급구", "구인", "need", "lf", "lfm" }
local HAVE_MARKERS = { "대기", "있음", "있어", "있습", "확정", "보유", "출발" }
local HAVE_PREFIX = { have = true, got = true }

local function isLatin(word)
    return not word:find("[\128-\255]")
end

local function escapePattern(word)
    return (word:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

-- Pre-compiles a word list into matchers.
local function compile(words)
    local out = {}
    for _, word in ipairs(words) do
        word = ns.LowerText(word)
        if isLatin(word) then
            out[#out + 1] = { latin = true, pattern = "%f[%w]" .. escapePattern(word) .. "%f[^%w]" }
        else
            out[#out + 1] = { latin = false, plain = (word:gsub("%s+", "")) }
        end
    end
    return out
end

local function hasAny(matchers, msg)
    for _, m in ipairs(matchers) do
        if m.latin then
            if msg.spaced:find(m.pattern) then return true end
        elseif msg.compact:find(m.plain, 1, true) then
            return true
        end
    end
    return false
end

local M = {
    lfg = compile(LFG_WORDS), lfm = compile(LFM_WORDS), boost = compile(BOOST_WORDS),
    trade = compile(TRADE_WORDS), guild = compile(GUILD_WORDS), guildAd = compile(GUILD_AD_WORDS),
    quest = compile(QUEST_WORDS), guildMember = compile(GUILD_MEMBER_WORDS), group = compile(GROUP_WORDS),
    tank = compile(ROLE_WORDS.tank), healer = compile(ROLE_WORDS.healer), dps = compile(ROLE_WORDS.dps),
}

-- Dungeon matchers: short forms + every localized name.
local dungeonMatchers = {}
for _, dungeon in ipairs(ns.Dungeons) do
    local words = {}
    for _, word in ipairs(dungeon.keys or {}) do words[#words + 1] = word end
    for _, name in pairs(dungeon.name or {}) do words[#words + 1] = name end
    dungeonMatchers[#dungeonMatchers + 1] = { dungeon = dungeon, matchers = compile(words) }
end

-----------------------------------------------------------------------------
-- Parser
-----------------------------------------------------------------------------
local function normalize(text)
    local lower = ns.LowerText(text)
    for _, noise in ipairs(ROLE_NOISE) do lower = lower:gsub(noise, " ") end
    local spaced = " " .. lower:gsub("%p", " "):gsub("%s+", " ") .. " "
    spaced = spaced:gsub("%f[%w]dm me%f[^%w]", " ")   -- "dm me" = direct message
    return { lower = lower, spaced = spaced, compact = lower:gsub("%s+", "") }
end

-----------------------------------------------------------------------------
-- Roles: only the ones the post asks for ("전딜,힐러 모십니다 / 야탱,도적 대기중"
-- -> dps + healer; the tank is already there)
-----------------------------------------------------------------------------
local function rolesIn(piece)
    local found = {}
    local probe = { lower = piece, spaced = " " .. piece:gsub("%p", " ") .. " ", compact = piece:gsub("%s+", "") }
    if hasAny(M.tank, probe) then found.tank = true end
    if hasAny(M.healer, probe) then found.healer = true end
    if hasAny(M.dps, probe) then found.dps = true end
    return found
end

local function hasMarker(token, list)
    for _, word in ipairs(list) do
        if isLatin(word) then
            if token:find("%f[%w]" .. word .. "%f[^%w]") then return true end
        elseif token:find(word, 1, true) then
            return true
        end
    end
    return false
end

function ns.ParseRoles(lower)
    local need, have, pending = {}, {}, {}
    local haveMode = false
    local function flush(into)
        for role in pairs(pending) do into[role] = true end
        pending = {}
    end
    for token in lower:gmatch("%S+") do
        local bare = token:gsub("%p", "")
        if HAVE_PREFIX[bare] then
            flush(need)
            haveMode = true
        else
            for piece in token:gmatch("[^,/%.]+") do
                for role in pairs(rolesIn(piece)) do
                    if haveMode then have[role] = true else pending[role] = true end
                end
            end
            if hasMarker(token, HAVE_MARKERS) then
                flush(have)
            elseif hasMarker(token, NEED_MARKERS) then
                flush(need)
                haveMode = false
            end
        end
    end
    flush(need)
    return { tank = need.tank, healer = need.healer, dps = need.dps }
end

-- Returns a post table (without sender info) or nil when the text is not a group post.
function ns.ParseMessage(text)
    local clean = ns.StripCodes(text)
    if clean == "" then return nil end
    local msg = normalize(clean)

    local isGuildAd = hasAny(M.guildMember, msg) or (hasAny(M.guild, msg) and hasAny(M.guildAd, msg))
    if isGuildAd then return nil end

    local keys, seen = {}, {}
    for _, entry in ipairs(dungeonMatchers) do
        if hasAny(entry.matchers, msg) then
            keys[#keys + 1] = entry.dungeon.key
            seen[entry.dungeon.key] = true
        end
    end
    -- a wing beats its parent ("수도원 도서관" is the Library, not every wing)
    for i = #keys, 1, -1 do
        local key = keys[i]
        if key == "sm" and (seen.smgy or seen.smlib or seen.smarm or seen.smcath) then tremove(keys, i) end
    end

    local roles = ns.ParseRoles(msg.lower)
    local hasRole = roles.tank or roles.healer or roles.dps

    local kind
    if hasAny(M.lfg, msg) then
        kind = "lfg"
    elseif hasAny(M.lfm, msg) then
        kind = "lfm"
    end
    local boost = hasAny(M.boost, msg)

    if #keys == 0 then
        if not kind then return nil end
        if hasAny(M.trade, msg) and not boost then return nil end
        -- "구해요" alone is too vague (trade, chatter): it needs a group word, a role or a quest
        local explicit = msg.spaced:find("%f[%w]lf[mg1-4]") or hasAny(M.group, msg) or hasRole or hasAny(M.quest, msg)
        if not explicit then return nil end
        keys[1] = hasAny(M.quest, msg) and "quest" or "other"
    elseif not kind then
        -- "통곡 탱 힐" : a dungeon plus roles is a recruitment post
        if not hasRole and not boost then return nil end
        kind = "lfm"
    end

    local need = tonumber(msg.spaced:match("lf(%d)m")) or tonumber(msg.compact:match("%f[%d](%d)명"))
    local have = tonumber(msg.compact:match("(%d)/5"))
    local level = tonumber(msg.compact:match("(%d%d?)렙")) or tonumber(msg.compact:match("(%d%d?)레벨"))
        or tonumber(msg.spaced:match("lvl ?(%d%d?)")) or tonumber(msg.spaced:match("level (%d%d?)"))

    return {
        text = clean,
        kind = kind,
        keys = keys,
        key = keys[1],
        roles = roles,
        boost = boost or nil,
        need = need,
        have = have,
        level = level,
    }
end

-----------------------------------------------------------------------------
-- Store
-----------------------------------------------------------------------------
function ns.OnPostsChanged(fn)
    listeners[#listeners + 1] = fn
end

local notifyPending = false
local function notify()
    if notifyPending then return end
    notifyPending = true
    C_Timer.After(0.4, function()
        notifyPending = false
        for _, fn in ipairs(listeners) do pcall(fn) end
    end)
end
ns.NotifyPostsChanged = notify

local function removePost(post)
    for i, p in ipairs(ns.Posts) do
        if p == post then tremove(ns.Posts, i) break end
    end
    if postBySender[post.sender] == post then postBySender[post.sender] = nil end
end

function ns.PrunePosts()
    local db = ns.db
    if not db then return end
    local limit = (db.expireMinutes or 10) * 60
    local now = GetTime()
    local changed = false
    for i = #ns.Posts, 1, -1 do
        local post = ns.Posts[i]
        if now - post.time > limit then
            postBySender[post.sender] = nil
            tremove(ns.Posts, i)
            changed = true
        end
    end
    while #ns.Posts > 300 do
        local post = tremove(ns.Posts)
        postBySender[post.sender] = nil
        changed = true
    end
    if changed then notify() end
end

function ns.ClearPosts()
    wipe(ns.Posts)
    wipe(postBySender)
    notify()
end

function ns.RemovePlayerPosts(sender)
    local post = postBySender[sender]
    if post then removePost(post) end
    notify()
end

-- True when the post passes the type / boost / blocked / level filters (not the category).
function ns.PostVisible(post)
    local db = ns.db
    if db.blocked[post.sender] then return false end
    if post.kind == "lfm" and not db.showLFM then return false end
    if post.kind == "lfg" and not db.showLFG then return false end
    if post.boost and db.hideBoost then return false end
    -- "needs my role": recruitment posts that name roles must include mine
    -- (posts without any parsed role still show)
    if db.myRoleOnly and post.kind == "lfm" and type(post.roles) == "table" then
        local roles = post.roles
        if (roles.tank or roles.healer or roles.dps) and not roles[db.myRole or "dps"] then return false end
    end
    if db.myLevelOnly and ns.DungeonByKey[post.key] then
        local fits = false
        for _, key in ipairs(post.keys) do
            if ns:DungeonFitsLevel(key) then fits = true break end
        end
        if not fits then return false end
    end
    return true
end

local function postInCategory(post, category)
    if category == "all" then return true end
    if category == "mylevel" then
        for _, key in ipairs(post.keys) do
            if ns:DungeonFitsLevel(key) then return true end
        end
        return false
    end
    for _, key in ipairs(post.keys) do
        if key == category then return true end
        local dungeon = ns.DungeonByKey[key]
        if dungeon and dungeon.parent == category then return true end
    end
    return false
end

function ns.GetFilteredPosts(category, search)
    local out = {}
    search = search and search ~= "" and ns.LowerText(search) or nil
    for _, post in ipairs(ns.Posts) do
        if ns.PostVisible(post) and postInCategory(post, category or "all") then
            if not search or post.searchText:find(search, 1, true) then
                out[#out + 1] = post
            end
        end
    end
    return out
end

function ns.CountByCategory()
    local counts = { all = 0, mylevel = 0 }
    for _, post in ipairs(ns.Posts) do
        if ns.PostVisible(post) then
            counts.all = counts.all + 1
            local fits, counted = false, {}
            for _, key in ipairs(post.keys) do
                if not counted[key] then
                    counted[key] = true
                    counts[key] = (counts[key] or 0) + 1
                end
                local dungeon = ns.DungeonByKey[key]
                if dungeon and dungeon.parent and not counted[dungeon.parent] then
                    counted[dungeon.parent] = true
                    counts[dungeon.parent] = (counts[dungeon.parent] or 0) + 1
                end
                if ns:DungeonFitsLevel(key) then fits = true end
            end
            if fits then counts.mylevel = counts.mylevel + 1 end
        end
    end
    return counts
end

-----------------------------------------------------------------------------
-- Alerts
-----------------------------------------------------------------------------
local function shouldAlert(post, previous)
    local db = ns.db
    if post.mine or not ns.PostVisible(post) then return false end
    if previous and previous.key == post.key and post.time - previous.firstTime < 300 then return false end
    for _, key in ipairs(post.keys) do
        local dungeon = ns.DungeonByKey[key]
        if db.watch[key] or (dungeon and dungeon.parent and db.watch[dungeon.parent]) then return true end
    end
    if db.alertMyLevel and post.kind == "lfm" then
        for _, key in ipairs(post.keys) do
            if ns:DungeonFitsLevel(key) then return true end
        end
    end
    return false
end

local function alert(post)
    if ns.MainWindowShown and ns.MainWindowShown() then return end
    local names = {}
    for _, key in ipairs(post.keys) do names[#names + 1] = ns:GetDungeonName(key) end
    local link = "|Hplayer:" .. post.sender .. "|h[" .. post.shortName .. "]|h"
    ns.Print(string.format(ns:L("alertMsg"), table.concat(names, " / ")) .. " " .. link .. ": " .. post.text)
    if ns.db.alertSound then
        local sound = SOUNDKIT and (SOUNDKIT.TELL_MESSAGE or SOUNDKIT.IG_PLAYER_INVITE)
        if sound then pcall(PlaySound, sound, "Master") end
    end
end

-----------------------------------------------------------------------------
-- Chat events
-----------------------------------------------------------------------------
local SOURCE_BY_EVENT = {
    CHAT_MSG_CHANNEL = "channel",
    CHAT_MSG_SAY = "say",
    CHAT_MSG_YELL = "say",
    CHAT_MSG_GUILD = "guild",
}

local function sourceEnabled(source)
    local db = ns.db
    if source == "channel" then return db.collectChannel end
    if source == "say" then return db.collectSay end
    if source == "guild" then return db.collectGuild end
    return false
end

local function channelLabel(event, channelName, channelBaseName)
    if event == "CHAT_MSG_SAY" then return ns:L("chSay") end
    if event == "CHAT_MSG_YELL" then return ns:L("chYell") end
    if event == "CHAT_MSG_GUILD" then return ns:L("chGuild") end
    local label = ns.SafeString(channelBaseName)
    if not label or label == "" then
        label = ns.SafeString(channelName) or ""
        label = label:gsub("^%d+%.%s*", "")
    end
    return label
end

local function senderClass(guid)
    guid = ns.SafeString(guid)
    if not guid or guid == "" or type(GetPlayerInfoByGUID) ~= "function" then return nil end
    local ok, _, classFile = pcall(GetPlayerInfoByGUID, guid)
    if ok and type(classFile) == "string" and not ns.IsSecret(classFile) then return classFile end
    return nil
end

local function onChat(event, text, sender, _, channelName, _, _, _, _, channelBaseName, _, _, guid)
    local source = SOURCE_BY_EVENT[event]
    if not source or not ns.db or not sourceEnabled(source) then return end
    text, sender = ns.SafeString(text), ns.SafeString(sender)
    if not text or not sender or sender == "" then return end

    local post = ns.ParseMessage(text)
    if not post then return end

    -- keep the sender exactly as the game gave it: whispers to "name-realm" fail for
    -- players on this realm (the realm's internal name is not what players type)

    local now = GetTime()
    local previous = postBySender[sender]
    nextId = nextId + 1
    post.id = nextId
    post.sender = sender
    post.shortName = ns.ShortName(sender)
    post.class = senderClass(guid) or (previous and previous.class)
    post.channel = channelLabel(event, channelName, channelBaseName)
    post.time = now
    post.firstTime = (previous and previous.key == post.key) and previous.firstTime or now
    post.mine = ns.IsMe(guid, post.shortName)
    post.searchText = ns.LowerText(post.text .. " " .. post.shortName)

    if previous then removePost(previous) end
    tinsert(ns.Posts, 1, post)
    postBySender[sender] = post

    if shouldAlert(post, previous) then alert(post) end
    notify()
end

function ns.StartCollector()
    local frame = CreateFrame("Frame")
    for event in pairs(SOURCE_BY_EVENT) do
        pcall(frame.RegisterEvent, frame, event)
    end
    pcall(frame.RegisterEvent, frame, "PLAYER_LEVEL_UP")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_LEVEL_UP" then
            notify()
            return
        end
        local ok, err = pcall(onChat, event, ...)
        if not ok and ns.debug then ns.Print(err) end
    end)
    C_Timer.NewTicker(15, ns.PrunePosts)
end

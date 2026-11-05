--===========================================================================
-- EzWoW - Group Finder
-- Data/Dungeons.lua : Dungeons, level ranges, localized names & chat keywords
--===========================================================================
-- keys: words matched as a whole word (Latin letters) or as a substring (other scripts).
-- The localized names are matched too, so only short forms players type are listed here.
-- `parent` marks a wing: a post naming the wing wins over its parent ("sm").
local _, ns = ...

ns.Dungeons = {
    { key = "rfc", min = 13, max = 18,
      name = { koKR = "성난불길 협곡", enUS = "Ragefire Chasm", deDE = "Ragefireabgrund", frFR = "Gouffre de Ragefeu", esES = "Sima Ígnea", ruRU = "Огненная пропасть", zhCN = "怒焰裂谷", zhTW = "怒焰裂谷" },
      keys = { "성난불길", "성불", "rfc", "ragefire" } },
    { key = "thanes", min = 13, max = 18,
      name = { koKR = "영주의 전당", enUS = "The Hall of Thanes", deDE = "Die Halle der Thanen", frFR = "La salle des Thanes", esES = "El Salón de los Feudales", ruRU = "Чертоги танов", zhCN = "领主大厅", zhTW = "族長之廳" },
      keys = { "영주의전당", "영주전당", "영전", "thanes", "hall of thanes" } },
    { key = "wc", min = 15, max = 24,
      name = { koKR = "통곡의 동굴", enUS = "Wailing Caverns", deDE = "Höhlen des Wehklagens", frFR = "Cavernes des Lamentations", esES = "Cuevas de los Lamentos", ruRU = "Пещеры Стенаний", zhCN = "哀嚎洞穴", zhTW = "哀嚎洞穴" },
      keys = { "통곡", "통동", "wc", "wailing" } },
    { key = "rol", min = 15, max = 20,
      name = { koKR = "로데론의 폐허", enUS = "Ruins of Lordaeron", deDE = "Ruinen von Lordaeron", frFR = "Ruines de Lordaeron", esES = "Ruinas de Lordaeron", ruRU = "Руины Лордерона", zhCN = "洛丹伦废墟", zhTW = "羅德隆廢墟" },
      keys = { "로데론의폐허", "로데론폐허", "로폐", "rol", "ruins of lordaeron" } },
    { key = "dm", min = 17, max = 26,
      name = { koKR = "죽음의 폐광", enUS = "The Deadmines", deDE = "Todesminen", frFR = "Mortemines", esES = "Minas de la Muerte", ruRU = "Мертвые копи", zhCN = "死亡矿井", zhTW = "死亡礦坑" },
      keys = { "죽음의폐광", "죽폐", "폐광", "dm", "vc", "deadmines", "deadmine" } },
    { key = "sfk", min = 20, max = 30,
      name = { koKR = "그림자송곳니 성채", enUS = "Shadowfang Keep", deDE = "Burg Shadowfang", frFR = "Donjon d'Ombrecroc", esES = "Castillo de Colmillo Oscuro", ruRU = "Крепость Темного Клыка", zhCN = "影牙城堡", zhTW = "影牙城堡" },
      keys = { "그림자송곳니", "송곳니", "그송", "성채", "sfk", "shadowfang" } },
    { key = "bfd", min = 24, max = 32,
      name = { koKR = "검은심연의 나락", enUS = "Blackfathom Deeps", deDE = "Blackfathom-Tiefe", frFR = "Profondeurs de Brassenoire", esES = "Cavernas de Brazanegra", ruRU = "Непроглядная Пучина", zhCN = "黑暗深渊", zhTW = "黑澗深淵" },
      keys = { "검은심연", "검심", "심연", "bfd", "blackfathom" } },
    { key = "stocks", min = 24, max = 32,
      name = { koKR = "스톰윈드 지하감옥", enUS = "The Stockade", deDE = "Verlies von Stormwind", frFR = "Prison de Stormwind", esES = "Mazmorras de Ventormenta", ruRU = "Тюрьма Штормграда", zhCN = "暴风城监狱", zhTW = "暴風城監獄" },
      keys = { "지하감옥", "스톰감옥", "감옥", "stocks", "stockade", "stock" } },
    { key = "excav", min = 26, max = 31,
      name = { koKR = "발굴 현장: 저습지", enUS = "Excavation Site: Wetlands", deDE = "Ausgrabungsstätte: Sumpfland", frFR = "Excavations : les Paluns", esES = "Excavación: Los Humedales", ruRU = "Раскопки: Болотина", zhCN = "挖掘场：湿地", zhTW = "挖掘場：濕地" },
      keys = { "발굴현장", "발굴", "excavation", "excav" } },
    { key = "dala", min = 28, max = 33,
      name = { koKR = "달라란", enUS = "City of Dalaran", deDE = "Dalaran", frFR = "Cité de Dalaran", esES = "Ciudad de Dalaran", ruRU = "Даларан", zhCN = "达拉然城", zhTW = "達拉然城" },
      keys = { "달라란", "dalaran", "dala" } },
    { key = "gnomer", min = 29, max = 38,
      name = { koKR = "놈리건", enUS = "Gnomeregan", deDE = "Gnomeregan", frFR = "Gnomeregan", esES = "Gnomeregan", ruRU = "Гномреган", zhCN = "诺莫瑞根", zhTW = "諾姆瑞根" },
      keys = { "놈리건", "놈리", "gnomer", "gnomeregan" } },
    { key = "rfk", min = 29, max = 38,
      name = { koKR = "가시덩굴 우리", enUS = "Razorfen Kraul", deDE = "Kral von Razorfen", frFR = "Kraal de Tranchebauge", esES = "Horado Rajacieno", ruRU = "Лабиринты Иглошкурых", zhCN = "剃刀沼泽", zhTW = "剃刀沼澤" },
      keys = { "가시덩굴우리", "가시우리", "가덩우리", "rfk", "kraul" } },
    { key = "sm", min = 30, max = 46,
      name = { koKR = "붉은십자군 수도원", enUS = "Scarlet Monastery", deDE = "Scharlachrotes Kloster", frFR = "Monastère écarlate", esES = "Monasterio Escarlata", ruRU = "Монастырь Алого ордена", zhCN = "血色修道院", zhTW = "血色修道院" },
      keys = { "붉은십자군", "수도원", "붉십", "sm", "scarlet", "monastery" } },
    { key = "smgy", parent = "sm", min = 30, max = 38,
      name = { koKR = "수도원 묘지", enUS = "SM Graveyard", deDE = "Kloster: Friedhof", frFR = "Monastère : Cimetière", esES = "Monasterio: Cementerio", ruRU = "Монастырь: Кладбище", zhCN = "血色墓地", zhTW = "血色墓地" },
      keys = { "묘지", "smgy", "sm gy", "gy", "graveyard" } },
    { key = "smlib", parent = "sm", min = 33, max = 41,
      name = { koKR = "수도원 도서관", enUS = "SM Library", deDE = "Kloster: Bibliothek", frFR = "Monastère : Bibliothèque", esES = "Monasterio: Biblioteca", ruRU = "Монастырь: Библиотека", zhCN = "血色图书馆", zhTW = "血色圖書館" },
      keys = { "도서관", "smlib", "sm lib", "lib", "library" } },
    { key = "smarm", parent = "sm", min = 36, max = 44,
      name = { koKR = "수도원 무기고", enUS = "SM Armory", deDE = "Kloster: Waffenkammer", frFR = "Monastère : Armurerie", esES = "Monasterio: Armería", ruRU = "Монастырь: Оружейная", zhCN = "血色军械库", zhTW = "血色軍械庫" },
      keys = { "무기고", "smarm", "sm arm", "arm", "armory", "armoury" } },
    { key = "smcath", parent = "sm", min = 38, max = 46,
      name = { koKR = "수도원 대성당", enUS = "SM Cathedral", deDE = "Kloster: Kathedrale", frFR = "Monastère : Cathédrale", esES = "Monasterio: Catedral", ruRU = "Монастырь: Собор", zhCN = "血色大教堂", zhTW = "血色大教堂" },
      keys = { "대성당", "성당", "smcath", "sm cath", "cath", "cathedral" } },
    { key = "rfd", min = 37, max = 46,
      name = { koKR = "가시덩굴 구릉", enUS = "Razorfen Downs", deDE = "Hügel von Razorfen", frFR = "Souilles de Tranchebauge", esES = "Zahúrda Rajacieno", ruRU = "Курганы Иглошкурых", zhCN = "剃刀高地", zhTW = "剃刀高地" },
      keys = { "가시덩굴구릉", "가시구릉", "구릉", "rfd", "downs" } },
    { key = "ulda", min = 41, max = 51,
      name = { koKR = "울다만", enUS = "Uldaman", deDE = "Uldaman", frFR = "Uldaman", esES = "Uldaman", ruRU = "Ульдаман", zhCN = "奥达曼", zhTW = "奧達曼" },
      keys = { "울다만", "울다", "ulda", "uldaman", "uld" } },
}

ns.DungeonByKey = {}
for index, dungeon in ipairs(ns.Dungeons) do
    dungeon.order = index
    ns.DungeonByKey[dungeon.key] = dungeon
end

-- Pseudo categories that are not dungeons.
ns.EXTRA_CATEGORIES = { "quest", "other" }

function ns:GetDungeonName(key)
    local dungeon = self.DungeonByKey[key]
    if not dungeon then
        if key == "quest" then return self:L("catQuest") end
        if key == "other" then return self:L("catOther") end
        return tostring(key or "")
    end
    local lang = self:GetActiveLang()
    return dungeon.name[lang] or dungeon.name.enUS or key
end

function ns:GetDungeonLevels(key)
    local dungeon = self.DungeonByKey[key]
    if not dungeon then return "" end
    return dungeon.min .. "-" .. dungeon.max
end

-- True when the player's level suits the dungeon (one level of slack either way).
function ns:DungeonFitsLevel(key, level)
    local dungeon = self.DungeonByKey[key]
    if not dungeon then return false end
    level = level or self.PlayerLevel()
    return level >= dungeon.min - 1 and level <= dungeon.max + 1
end

-- The best dungeon for a level: the one whose range centre is closest, else the next one up.
function ns:SuggestDungeon(level)
    level = level or self.PlayerLevel()
    local best, bestDist, upcoming
    for _, dungeon in ipairs(self.Dungeons) do
        if dungeon.key ~= "sm" then
            if level >= dungeon.min and level <= dungeon.max then
                local dist = math.abs(level - (dungeon.min + dungeon.max) / 2)
                if not bestDist or dist < bestDist then best, bestDist = dungeon, dist end
            elseif level < dungeon.min and not upcoming then
                upcoming = dungeon
            end
        end
    end
    local pick = best or upcoming or self.Dungeons[#self.Dungeons]
    return pick.key
end

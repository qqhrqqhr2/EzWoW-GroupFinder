#!/usr/bin/env python3
"""Draws the README mock-ups of EzWoW - Group Finder (docs/images/ui_*.png, settings_*.png).

The windows are rebuilt from the sizes, positions, colours and texts in UI/MainWindow.lua,
UI/OptionsWindow.lua, Core/UIKit.lua, Core/Init.lua (ns.Style) and Core/Locales.lua
(game pixels x SCALE). Character names and posts are made-up examples.

usage: python scripts/make_readme_images.py .
Renders with headless Chrome (set CHROME to its path if it is not in the default place).
Standard library only.
"""
import base64
import html
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from string import Template

SCALE = 1.36
PAGE_W = 1600
PLAYER_LEVEL = 24
VERSION = "1.0.2"

# ns.Style (Core/Init.lua)
C = {
    "bgPrimary": "rgba(18,24,31,.97)", "bgSecondary": "rgba(29,40,49,.96)", "bgInput": "rgba(12,17,22,.96)",
    "bgHover": "rgb(41,54,66)", "bgAccent": "rgba(28,51,45,.96)", "border": "#344c5b",
    "textBody": "#edf4f7", "textMuted": "#a7b9c5", "accent": "#7fd8b0", "lfg": "#7db0f5",
    "boost": "#f2c254", "disabled": "#63727b", "tank": "#6ba6ff", "healer": "#66e073", "dps": "#ff786b",
    "fontDisable": "#808080",
}
CALL = C["accent"]
CLASS = {"WARRIOR": "#c69b6d", "MAGE": "#3fc7eb", "PALADIN": "#f48cba", "HUNTER": "#aad372",
         "PRIEST": "#ffffff", "DRUID": "#ff7c0a", "ROGUE": "#fff468", "WARLOCK": "#8788ee", "SHAMAN": "#0070dd"}

# Data/Dungeons.lua (order, levels, wing parent, names)
DUNGEONS = [
    ("rfc", 13, 18, None, "성난불길 협곡", "Ragefire Chasm"),
    ("thanes", 13, 18, None, "영주의 전당", "The Hall of Thanes"),
    ("wc", 15, 24, None, "통곡의 동굴", "Wailing Caverns"),
    ("rol", 15, 20, None, "로데론의 폐허", "Ruins of Lordaeron"),
    ("dm", 17, 26, None, "죽음의 폐광", "The Deadmines"),
    ("sfk", 20, 30, None, "그림자송곳니 성채", "Shadowfang Keep"),
    ("bfd", 24, 32, None, "검은심연의 나락", "Blackfathom Deeps"),
    ("stocks", 24, 32, None, "스톰윈드 지하감옥", "The Stockade"),
    ("excav", 26, 31, None, "발굴 현장: 저습지", "Excavation Site: Wetlands"),
    ("dala", 28, 33, None, "달라란", "City of Dalaran"),
    ("gnomer", 29, 38, None, "놈리건", "Gnomeregan"),
    ("rfk", 29, 38, None, "가시덩굴 우리", "Razorfen Kraul"),
    ("sm", 30, 46, None, "붉은십자군 수도원", "Scarlet Monastery"),
    ("smgy", 30, 38, "sm", "수도원 묘지", "SM Graveyard"),
    ("smlib", 33, 41, "sm", "수도원 도서관", "SM Library"),
    ("smarm", 36, 44, "sm", "수도원 무기고", "SM Armory"),
    ("smcath", 38, 46, "sm", "수도원 대성당", "SM Cathedral"),
    ("rfd", 37, 46, None, "가시덩굴 구릉", "Razorfen Downs"),
    ("ulda", 41, 51, None, "울다만", "Uldaman"),
]
DUNGEON = {d[0]: d for d in DUNGEONS}
WATCHED = {"dm"}

# Core/Locales.lua (koKR / enUS) - only the strings these windows show
L = {
    "ko": {
        "subtitle": "채팅에서 모은 파티 모집 글 %d개", "settingsSub": "설정 · 제목을 끌어 이동", "settings": "설정",
        "tabBrowse": "파티 찾기", "tabCompose": "모집 글 쓰기", "catAll": "전체", "catMyLevel": "내 레벨 추천",
        "catQuest": "퀘스트", "catOther": "기타", "search": "검색 (던전·이름·내용)",
        "kindLFM": "구인", "kindLFG": "구직", "kindBoost": "버스", "hideBoost": "버스 숨기기", "myLevelChip": "내 레벨만",
        "myRoleChip": "%s 구함", "roleTank": "탱", "roleHeal": "힐", "roleDps": "딜",
        "agoNow": "방금", "agoMin": "%d분 전", "whisper": "귓말", "invite": "초대",
        "tipClick": "클릭: 귓속말 보내기", "tipAlt": "Alt+클릭: 이 사람 글 숨기기",
        "footer": "글 %d개 · %d분이 지나면 사라집니다", "clear": "모두 지우기",
        "secCollect": "글 모으기", "optChannels": "채팅 채널 (공개·파티찾기·거래 등)", "optSay": "일반 대화·외치기",
        "optGuild": "길드 대화", "optExpire": "글 유지 시간", "minutes": "%d분", "secView": "표시",
        "optMyLevel": "내 레벨에 맞는 던전 글만 보기", "optHideBoost": "버스(돈 받고 돌아 주는) 글 숨기기",
        "optIcon": "실행 아이콘 표시", "secAlert": "알림", "optAlertMyLevel": "내 레벨 던전에 새 구인 글이 오면 알림",
        "optSound": "알림 소리",
        "secGreet": "인사", "optGreetSelf": "파티에 들어가면 자기소개 하기", "optGreetWelcome": "새 파티원에게 환영 인사 하기",
        "watchHint": "목록에서 던전을 오른쪽 클릭하면 그 던전의 새 글만 따로 알림을 받을 수 있습니다.",
        "language": "언어", "unblock": "숨긴 사람 되돌리기 (%d)", "resetPos": "창·아이콘 위치 초기화",
        "donate": "후원 · 링크 복사", "optAutoJoin": "서버 파티찾기 채널에 자동 참여",
        "optJoinChannels": "모집 글이 올라오는 채널 이름 (쉼표로 구분)", "joinPlaceholder": "예: 파티, 던전",
        "joinHint": "적어 둔 채널에 자동으로 들어가 글을 모으고, 모집 글도 기본으로 이 채널에 보냅니다. "
                    "채팅창에는 표시되지 않습니다. 참여 중인 채널은 /ezgf 채널 로 볼 수 있습니다.",
    },
    "en": {
        "subtitle": "%d group posts collected from chat", "settingsSub": "Settings · Drag the title to move",
        "settings": "Settings", "tabBrowse": "Find Group", "tabCompose": "Write Post", "catAll": "All",
        "catMyLevel": "For My Level", "catQuest": "Quests", "catOther": "Other", "search": "Search (dungeon, name, text)",
        "kindLFM": "LFM", "kindLFG": "LFG", "kindBoost": "Boost", "hideBoost": "Hide boosts", "myLevelChip": "My level",
        "myRoleChip": "Need %s", "roleTank": "Tank", "roleHeal": "Heal", "roleDps": "DPS",
        "agoNow": "now", "agoMin": "%dm ago", "whisper": "Whisper", "invite": "Invite",
        "tipClick": "Click: whisper", "tipAlt": "Alt+Click: hide this player's posts",
        "footer": "%d posts · removed after %d min", "clear": "Clear all",
        "secCollect": "Collect", "optChannels": "Chat channels (General, LFG, Trade, ...)", "optSay": "Say & Yell",
        "optGuild": "Guild chat", "optExpire": "Keep posts for", "minutes": "%d min", "secView": "Display",
        "optMyLevel": "Only show dungeons for my level", "optHideBoost": "Hide boost (paid run) posts",
        "optIcon": "Show launcher icon", "secAlert": "Alerts", "optAlertMyLevel": "Alert on new LFM posts for my level",
        "optSound": "Alert sound",
        "secGreet": "Greetings", "optGreetSelf": "Introduce myself when I join a party",
        "optGreetWelcome": "Welcome new party members",
        "watchHint": "Right-click a dungeon in the list to get alerts for that dungeon only.",
        "language": "Language", "unblock": "Unhide players (%d)", "resetPos": "Reset window & icon",
        "donate": "Donate · Copy link", "optAutoJoin": "Auto-join the server's LFG channel",
        "optJoinChannels": "Channels where groups are posted (comma-separated)", "joinPlaceholder": "e.g. lfgworld, dungeons",
        "joinHint": "The addon joins these channels to collect posts and sends your posts there by default. "
                    "They are not shown in your chat windows. Type /ezgf channels to list your channels.",
    },
}

# page texts (title, lead, callout notes)
T = {
    "ko": {
        "head": "채팅의 파티 모집 글을 던전별로 모아 보기 · 역할·레벨 필터 · 귓말·초대 · 새 글 알림",
        "sBadge": "설정창", "sHead": "/ezgf 설정 · 글 모으기, 채널, 표시, 알림, 파티 인사, 언어",
        "chLFG": "파티찾기", "chGeneral": "공개", "chTrade": "거래",
        "notes": [
            ("탭", "파티 찾기(모인 글 보기)와 모집 글 쓰기(방식·던전·역할·인원·메모로 글을 만들어 채팅에 보내기, 30초에 한 번)."),
            ("설정", "설정창을 엽니다. 실행 아이콘 오른쪽 클릭이나 /ezgf 설정으로도 열 수 있습니다."),
            ("던전 목록", "전체 · 내 레벨 추천 · 던전별 글 수. 내 레벨에 맞는 던전은 레벨 범위가 민트색. 오른쪽 클릭하면 그 던전 새 글 알림(별 표시)."),
            ("검색", "던전 · 이름 · 글 내용으로 찾습니다."),
            ("필터", "구인 · 구직 켜고 끄기, 버스 숨기기, 내 레벨만."),
            ("내 역할", "왼쪽 클릭: 켜기/끄기. 오른쪽 클릭: 탱 → 힐 → 딜 바꾸기. 켜면 내 역할을 구하는 모집 글만 보입니다(역할이 없는 글은 그대로)."),
            ("모집 글", "구인·구직·버스, 던전과 레벨 범위, 필요한 역할·인원·레벨, 올린 시간. 클릭하면 귓말, 구직 글에는 초대 버튼, Alt+클릭으로 그 사람 글 숨기기."),
            ("툴팁", "글 전체, 올라온 채널, 올린 시간."),
            ("아래 줄", "모인 글 수와 유지 시간(기본 10분), 모두 지우기."),
        ],
        "sNotes": [
            ("글 모으기", "채팅 채널(공개·파티찾기·거래 등), 일반 대화·외치기, 길드 대화에서 모읍니다."),
            ("자동 참여", "서버 파티찾기 채널에 접속할 때마다 한 번 자동으로 들어갑니다. 직접 나가면 다음 접속까지 다시 들어가지 않습니다."),
            ("채널 이름 · 유지 시간", "적어 둔 채널에 보이지 않게 들어가 글을 모으고 모집 글의 기본 보낼 곳으로 씁니다(채팅창에는 안 보임). 글 유지 3~30분."),
            ("표시", "내 레벨 던전 글만, 버스 글 숨기기, 실행 아이콘 표시."),
            ("알림", "내 레벨 던전의 새 구인 글 알림과 알림 소리. 던전별 알림은 목록에서 오른쪽 클릭. 전투 중에 온 알림은 전투가 끝난 뒤 채팅에 표시됩니다."),
            ("인사", "파티에 들어가면 자기소개(예: \"안녕하세요! 16렙 야성 드루이드입니다.\"), 내 파티에 새 사람이 오면 이름과 성을 불러 \"바람결 은빛숲님 어서 오세요, 반갑습니다!\"(여러 명이면 한 줄로). 특성 이름은 EzWoW - Tooltip이 있을 때만 붙습니다. 공격대에서는 보내지 않습니다."),
            ("언어 · 숨긴 사람", "언어(자동 + 8개 언어). Alt+클릭으로 숨긴 사람을 모두 되돌립니다."),
            ("위치 · 후원", "창과 실행 아이콘 위치 초기화, 후원 링크 복사."),
        ],
        "note": "애드온 코드의 창 크기·좌표·색상·문구로 재현한 예시 화면입니다. 캐릭터 이름과 글은 예시입니다.",
    },
    "en": {
        "head": "Group posts from chat sorted by dungeon · role and level filters · whisper and invite · new-post alerts",
        "sBadge": "Settings", "sHead": "/ezgf config · collecting, channels, display, alerts, party greetings, language",
        "chLFG": "LookingForGroup", "chGeneral": "General", "chTrade": "Trade",
        "notes": [
            ("Tabs", "Find Group (browse the posts) and Write Post (build a message from type, dungeon, roles, size and a note; send once every 30 s)."),
            ("Settings", "Opens the settings. Also right-click the launcher icon or type /ezgf config."),
            ("Dungeon list", "All · For My Level · post count per dungeon. Level ranges that suit you are mint. Right-click a dungeon for new-post alerts (star)."),
            ("Search", "Find by dungeon, player name or text."),
            ("Filters", "Show LFM · LFG, hide boosts, my level only."),
            ("My role", "Left-click: on/off. Right-click: cycle Tank → Heal → DPS. When on, only groups that need your role show (posts naming no role stay)."),
            ("Posts", "LFM · LFG · Boost, dungeon and level range, roles, group size, level and age. Click to whisper, Invite on LFG posts, Alt+Click hides the player."),
            ("Tooltip", "Full message, channel and age."),
            ("Footer", "Post count, how long posts are kept (10 min by default), Clear all."),
        ],
        "sNotes": [
            ("Collect", "From chat channels (General, LFG, Trade, ...), Say & Yell and guild chat."),
            ("Auto-join", "Joins the server's LFG channel once per login. If you leave it, it stays left until your next login."),
            ("Channels · keep time", "Joins the channels you list in the background to collect posts and uses them as the default send target (hidden from your chat). Keep posts 3–30 min."),
            ("Display", "Only my level, hide boost posts, launcher icon."),
            ("Alerts", "New LFM posts for your level, with sound. Per-dungeon alerts: right-click a dungeon in the list. Alerts that arrive in combat are printed after the fight."),
            ("Greetings", "Introduce yourself when you join a party (e.g. \"Hello! Level 16 Feral Combat Druid here.\") and greet newcomers by full name: \"Welcome, Windrift Ashvale! Nice to meet you!\" (one line when several join). The talent tree is added when EzWoW - Tooltip is installed. Never in a raid."),
            ("Language · hidden players", "Language (auto + 8 languages). Unhide everyone you hid with Alt+Click."),
            ("Position · donate", "Reset the window and launcher icon positions, copy the donate link."),
        ],
        "note": "Mock-ups rebuilt from the window sizes, coordinates, colours and strings in the addon code. Character names and posts are made up.",
    },
}

# Sample posts, newest first (ns.Posts order). Names are invented.
# (keys, kind, boost, roles, have, need, level, age s, (ko name, en name), class, channel, (ko text, en text))
POSTS = [
    (["dm"], "lfm", False, ("tank", "healer"), 3, None, None, 20, ("바람결", "Windrift"), "WARRIOR", "chLFG",
     ("죽폐 탱 힐 구합니다 (3/5)", "LF2M Deadmines need tank heal (3/5)")),
    (["sfk"], "lfg", False, ("dps",), None, None, 24, 75, ("별빛노래", "Starsong"), "MAGE", "chLFG",
     ("그송 파티 구합니다 - 딜 24레벨", "LFG Shadowfang Keep - DPS lvl 24")),
    (["bfd"], "lfm", False, ("healer",), None, 2, None, 140, ("은빛방패", "Silvershield"), "PALADIN", "chGeneral",
     ("검심 힐 포함 2명 구해요 퀘 공유", "LF2M BFD need healer, quests shared")),
    (["smgy"], "lfm", True, (), None, None, None, 250, ("달그림자", "Moonshade"), "MAGE", "chTrade",
     ("묘지 버스 갑니다 1인 5골", "SM GY boost runs 5g each")),
    (["wc", "dm"], "lfm", False, ("dps",), None, None, None, 330, ("잿빛늑대", "Ashwolf"), "HUNTER", "chLFG",
     ("통곡이나 죽폐 딜 한 분 오세요", "LFM WC or DM need dps")),
    (["stocks"], "lfm", False, ("tank",), 4, None, None, 430, ("새벽이슬", "Dawndew"), "PRIEST", "chLFG",
     ("지하감옥 탱 구합니다 (4/5) 바로 출발", "Stockade LF tank (4/5) leaving now")),
    (["rfc"], "lfg", False, ("healer",), None, None, 17, 470, ("들꽃향기", "Wildbloom"), "DRUID", "chLFG", ("", "")),
    (["wc"], "lfm", False, ("tank",), 2, None, None, 500, ("강철주먹", "Ironfist"), "WARRIOR", "chGeneral", ("", "")),
    (["dm"], "lfg", False, ("tank",), None, None, 21, 520, ("푸른바다", "Bluetide"), "SHAMAN", "chLFG", ("", "")),
    (["smlib"], "lfm", False, ("healer",), 3, None, None, 540, ("밤까마귀", "Nightcrow"), "WARLOCK", "chLFG", ("", "")),
    (["bfd"], "lfm", False, ("dps",), 4, None, None, 560, ("돌망치", "Stonehammer"), "PALADIN", "chLFG", ("", "")),
    (["gnomer"], "lfm", False, (), 3, None, None, 570, ("작은톱니", "Cogwhistle"), "ROGUE", "chLFG", ("", "")),
    (["quest"], "lfm", False, (), None, None, None, 580, ("숲지기", "Woodwarden"), "DRUID", "chGeneral", ("", "")),
    (["sfk"], "lfg", False, ("healer",), None, None, 25, 590, ("은방울", "Silverbell"), "PRIEST", "chLFG", ("", "")),
]

# defaults (ns.DEFAULTS) + one watched dungeon
DB = {"showLFM": True, "showLFG": True, "hideBoost": False, "myLevelOnly": False, "myRoleOnly": False,
      "myRole": "dps", "expireMinutes": 10, "selected": "all"}


def px(v):
    return f"{v * SCALE:.1f}px"


def at(x, y, w=None, h=None):
    s = f"left:{px(x)};top:{px(y)};"
    if w is not None:
        s += f"width:{px(w)};"
    if h is not None:
        s += f"height:{px(h)};"
    return s


def esc(s):
    return html.escape(s, quote=False)


def fit(inner, base, minimum, max_w=None, style=""):
    """ns.FitText: shrinks from base to minimum font size (game px), then cuts with an ellipsis."""
    mw = f"max-width:{px(max_w)};" if max_w else ""
    return (f'<span class="fit" data-min="{minimum * SCALE:.2f}" data-step="{0.5 * SCALE:.2f}" '
            f'style="font-size:{px(base)};{mw}{style}">{inner}</span>')


def fits_level(key):
    d = DUNGEON.get(key)
    return bool(d) and d[1] - 1 <= PLAYER_LEVEL <= d[2] + 1


def dname(key, lang):
    if key == "quest":
        return L[lang]["catQuest"]
    if key == "other":
        return L[lang]["catOther"]
    return DUNGEON[key][4 if lang == "ko" else 5]


def button(x, y, w, h, label, size=12, active=False, accent=False, active_color=None, enabled=True, extra=""):
    """UIKit:CreateButton + paintButton."""
    if not enabled:
        bg, bd, fg = C["bgSecondary"], C["border"], C["disabled"]
    elif active or accent:
        bg, bd, fg = C["bgAccent"], C["accent"], active_color or C["accent"]
    else:
        bg, bd, fg = C["bgSecondary"], C["border"], C["textBody"]
    return (f'<div class="btn" style="{at(x, y, w, h)}background:{bg};border-color:{bd};color:{fg};{extra}">'
            f'{fit(esc(label), size, 8, w - 10)}</div>')


def header(width, subtitle, sub_w, icon_uri, gear_label=None):
    """UIKit:CreateHeader (58 px bar, icon, title, subtitle, 2 px accent line) + close (+ gear)."""
    p = [f'<div class="abs" style="{at(1, 1, width - 2, 58)}background:rgba(29,40,49,.98)"></div>',
         f'<div class="abs" style="{at(1, 57, width - 2, 2)}background:{C["accent"]}"></div>',
         f'<img class="abs" src="{icon_uri}" style="{at(15, 15, 28, 28)}">',
         f'<div class="lbl" style="{at(49, 10)}font-size:{px(16)};color:{C["accent"]}">EzWoW - Group Finder</div>',
         f'<div class="lbl" style="{at(49, 31, sub_w)}overflow:hidden">{fit(esc(subtitle), 10, 8, sub_w, "color:" + C["textMuted"])}</div>']
    close_x = width - 1 - 10 - 22
    p.append(button(close_x, 11, 22, 22, "X"))
    if gear_label:
        p.append(button(close_x - 6 - 64, 11, 64, 22, gear_label, size=11))
    return p


def age_text(sec, lang):
    m = sec // 60
    return L[lang]["agoNow"] if m < 1 else L[lang]["agoMin"] % m


def kind_of(post, lang):
    keys, kind, boost = post[0], post[1], post[2]
    if boost:
        return L[lang]["kindBoost"], C["boost"]
    if kind == "lfg":
        return L[lang]["kindLFG"], C["lfg"]
    return L[lang]["kindLFM"], C["accent"]


def counts():
    out = {"all": 0, "mylevel": 0}
    for post in POSTS:
        out["all"] += 1
        counted, ok = set(), False
        for key in post[0]:
            if key not in counted:
                counted.add(key)
                out[key] = out.get(key, 0) + 1
            d = DUNGEON.get(key)
            if d and d[3] and d[3] not in counted:
                counted.add(d[3])
                out[d[3]] = out.get(d[3], 0) + 1
            ok = ok or fits_level(key)
        if ok:
            out["mylevel"] += 1
    return out


CSS = Template("""
* { box-sizing: border-box; margin: 0; padding: 0; }
html { background: #0b1014; }
body { width: ${PAGE_W}px; background: radial-gradient(ellipse at 30% 0%, #1b2b2c 0%, #10171d 60%, #0b1014 100%);
  font-family: 'Noto Sans KR', 'Malgun Gothic', sans-serif; color: ${textBody}; overflow: hidden; min-height: 100vh; }
.page { position: relative; padding: 34px 50px 0; }
h1 { color: ${accent}; font-size: 40px; font-weight: 700; letter-spacing: .3px; display: flex; align-items: center; gap: 14px; }
h1 .badge { font-size: 15px; background: ${accent}; color: #0d2219; padding: 2px 9px; border-radius: 5px; }
.lead { color: #d5dde2; font-size: 19px; margin-top: 6px; }
.abs { position: absolute; }
.win { position: absolute; background: ${bgPrimary}; border: 1px solid ${border}; }
.lbl { position: absolute; white-space: nowrap; line-height: 1.2; }
.btn { position: absolute; border: 1px solid; display: flex; align-items: center; justify-content: center; overflow: hidden; }
.fit { display: inline-block; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; vertical-align: middle; line-height: 1.25; }
.edit { position: absolute; background: ${bgInput}; border: 1px solid ${border}; display: flex; align-items: center; }
.row { position: absolute; border: 1px solid; }
.check { position: absolute; width: ${chk}; height: ${chk}; border: 1px solid #6d6a5d; background: #191919; border-radius: 2px; }
.check::after { content: '\\2714'; position: absolute; left: ${chkL}; top: ${chkT}; font-size: ${chkF}; color: #ffd200; text-shadow: 0 0 1px #000; line-height: 1; }
.check.off::after { content: ''; }
.call { position: absolute; width: 30px; height: 30px; border-radius: 50%; background: ${CALL}; color: #0d2219; font-weight: 700;
  font-size: 16px; display: flex; align-items: center; justify-content: center; border: 2px solid #0d2219; box-shadow: 0 0 0 2px ${CALL}55; z-index: 5; }
.note { display: flex; gap: 12px; margin-bottom: 11px; font-size: 16.5px; line-height: 1.5; color: #dfe6ea; }
.note .n { flex: none; width: 28px; height: 28px; border-radius: 50%; background: ${CALL}; color: #0d2219; font-weight: 700;
  font-size: 15px; display: flex; align-items: center; justify-content: center; margin-top: 1px; }
.note b { color: #fff; }
.foot { color: #7d8d98; font-size: 13.5px; margin-top: 18px; }
.tip { position: absolute; background: rgba(4,8,14,.95); border: 2px solid #5d6d7a; border-radius: 4px; padding: 10px 12px;
  font-size: 14px; line-height: 1.5; }
.tip .dl { display: flex; justify-content: space-between; gap: 22px; }
.star { position: absolute; color: #ffd100; line-height: 1; text-shadow: 0 0 2px #000; }
""").substitute(PAGE_W=PAGE_W, CALL=CALL, chk=px(18), chkL=px(1), chkT=px(-2), chkF=px(17), **C)

# ns.FitText in the browser, then the page height for the screenshot
JS = """
document.querySelectorAll('.fit').forEach(function (el) {
  var s = parseFloat(el.style.fontSize), m = parseFloat(el.dataset.min), st = parseFloat(el.dataset.step);
  while (el.scrollWidth > el.clientWidth + 0.5 && s - st >= m - 0.01) { s -= st; el.style.fontSize = s + 'px'; }
});
var b = 0;
document.querySelectorAll('body *').forEach(function (el) { b = Math.max(b, el.getBoundingClientRect().bottom); });
document.body.setAttribute('data-h', String(Math.ceil(b + 34)));
"""


def notes_html(items, start=1):
    return "".join(f'<div class="note"><span class="n">{start + i}</span><div><b>{esc(a)}</b> — {esc(b)}</div></div>'
                   for i, (a, b) in enumerate(items))


# ---------------------------------------------------------------------------
# Main window (UI/MainWindow.lua): 820 x 540, sidebar 206, content top 100, footer 34
# ---------------------------------------------------------------------------
def ui_page(lang, icon_uri):
    s, t = L[lang], T[lang]
    W, H = 820, 540
    SIDE_W, TOP, FOOT = 206, 100, 34
    ox, oy = 72, 160
    cnt = counts()
    total = len(POSTS)
    p = header(W, s["subtitle"] % total, 520, icon_uri, s["settings"])

    # tabs 150 x 26 at (12, -66)
    p.append(button(12, 66, 150, 26, s["tabBrowse"], active=True))
    p.append(button(168, 66, 150, 26, s["tabCompose"]))

    # sidebar: TOPLEFT 12 / content top, width 206, to the footer
    side_h = H - FOOT - TOP
    p.append(f'<div class="abs" style="{at(12, TOP, SIDE_W, side_h)}background:rgba(12,17,22,.7);border:1px solid {C["border"]}"></div>')
    # category scroll list at (4, -4) .. (-2, 4): rows 22, gap 0, row width = list - 8
    lx, ly, lw, lh = 16, TOP + 4, SIDE_W - 6, side_h - 8
    rw = lw - 8
    items = ["all", "mylevel"] + [d[0] for d in DUNGEONS] + ["quest", "other"]
    visible = max(1, int(lh // 22))
    for i, key in enumerate(items[:visible]):
        y = ly + i * 22
        d = DUNGEON.get(key)
        indent = 18 if (d and d[3]) else 8
        n = cnt.get(key, 0)
        watched = key in WATCHED
        sel = DB["selected"] == key
        if sel:
            p.append(f'<div class="abs" style="{at(lx, y, rw, 22)}background:{C["bgAccent"]}"></div>')
            p.append(f'<div class="abs" style="{at(lx, y, 2, 22)}background:{C["accent"]}"></div>')
        levels = f"{d[1]}-{d[2]}" if d else ""
        name = s["catAll"] if key == "all" else s["catMyLevel"] if key == "mylevel" else dname(key, lang)
        name_w = rw - indent - (15 if watched else 0) - 34 - (40 if levels else 0)
        if key in ("all", "mylevel"):
            ncol = C["textBody"]
        else:
            ncol = C["textBody"] if n > 0 else C["textMuted"]
        size = 11 if (d and d[3]) else 12
        p.append(f'<div class="lbl" style="left:{px(lx + indent + (15 if watched else 0))};top:{px(y)};height:{px(22)};'
                 f'display:flex;align-items:center;color:{ncol}">{fit(esc(name), size, 8, name_w)}</div>')
        if watched:
            p.append(f'<div class="star" style="{at(lx + indent - 2, y + 4)}font-size:{px(13)}">★</div>')
        if levels:
            lcol = C["accent"] if fits_level(key) else C["textMuted"]
            p.append(f'<div class="lbl" style="right:auto;left:{px(lx + rw - 30 - 40)};width:{px(40)};top:{px(y)};height:{px(22)};'
                     f'display:flex;align-items:center;justify-content:flex-end;font-size:{px(10)};color:{lcol}">{levels}</div>')
        if n > 0:
            p.append(f'<div class="lbl" style="left:{px(lx + rw - 6 - 24)};width:{px(24)};top:{px(y)};height:{px(22)};'
                     f'display:flex;align-items:center;justify-content:flex-end;font-size:{px(10)};color:{C["accent"]}">{n}</div>')
    if len(items) > visible:   # thin scroll bar (track + thumb)
        p.append(f'<div class="abs" style="{at(lx + lw - 4, ly, 4, lh)}background:rgba(52,76,91,.35)"></div>')
        p.append(f'<div class="abs" style="{at(lx + lw - 4, ly, 4, max(20, lh * visible / len(items)))}background:rgba(127,216,176,.75)"></div>')

    # search 150 x 26 at left = 12 + 206 + 10
    left = 12 + SIDE_W + 10
    p.append(f'<div class="edit" style="{at(left, TOP, 150, 26)}padding-left:{px(9)}">'
             f'{fit(esc(s["search"]), 12, 12, 132, "color:" + C["fontDisable"])}</div>')
    # chips: LFM 62, LFG 62, boost 104, level 104, role 78 (gaps 8, 4, 4, 4, 4)
    role_label = s["myRoleChip"] % s[{"tank": "roleTank", "healer": "roleHeal", "dps": "roleDps"}[DB["myRole"]]]
    chips = [(s["kindLFM"], 62, DB["showLFM"], None), (s["kindLFG"], 62, DB["showLFG"], C["lfg"]),
             (s["hideBoost"], 104, DB["hideBoost"], None), (s["myLevelChip"], 104, DB["myLevelOnly"], None),
             (role_label, 78, DB["myRoleOnly"], None)]
    x = left + 150 + 8
    chip_x = []
    for label, w, on, colr in chips:
        p.append(button(x, TOP, w, 26, label, size=11, active=on, active_color=colr))
        chip_x.append((x, w))
        x += w + 4

    # post list: (left, -34) .. (-12, footer); rows 50, gap 4
    list_y = TOP + 34
    list_w = W - 12 - left
    list_h = H - FOOT - list_y
    row_w = list_w - 8
    vis = int((list_h + 4) // 54)
    hover_index = 1
    for i, post in enumerate(POSTS[:vis]):
        keys, kind, boost, roles, have, need, level, age, names, cls, chan, texts = post
        y = list_y + i * 54
        klabel, kcol = kind_of(post, lang)
        hover = i == hover_index
        bg = C["bgHover"] if hover else C["bgSecondary"]
        bd = kcol if hover else C["border"]
        p.append(f'<div class="row" style="{at(left, y, row_w, 50)}background:{bg};border-color:{bd}">')
        p.append(f'<div class="abs" style="left:0;top:0;bottom:0;width:{px(3)};background:{kcol}"></div>')
        # first line: kind, title (+ levels), roles / size / level ... age
        title = " / ".join(esc(dname(k, lang)) for k in keys)
        if len(keys) == 1 and keys[0] in DUNGEON:
            d = DUNGEON[keys[0]]
            title += f'<span style="color:{C["accent"] if fits_level(keys[0]) else C["textMuted"]}">&nbsp;&nbsp;{d[1]}-{d[2]}</span>'
        extra = []
        role_key = {"tank": "roleTank", "healer": "roleHeal", "dps": "roleDps"}
        for r in ("tank", "healer", "dps"):
            if r in roles:
                extra.append(f'<span style="color:{C[r]}">{s[role_key[r]]}</span>')
        tail = []
        if have:
            tail.append(f"{have}/5")
        elif need:
            tail.append(f"+{need}")
        if level:
            tail.append(f"Lv{level}")
        extra_html = " ".join(extra)
        for tx in tail:
            extra_html += ("&nbsp;&nbsp;" if extra_html else "") + f'<span style="color:{C["textMuted"]}">{tx}</span>'
        p.append(f'<div class="abs" style="left:{px(11)};right:{px(9)};top:{px(3)};height:{px(18)};display:flex;align-items:center">'
                 f'<span style="flex:none;font-size:{px(10)};color:{kcol}">{esc(klabel)}</span>'
                 f'<span class="fit" data-min="{9 * SCALE:.2f}" data-step="{0.5 * SCALE:.2f}" style="flex:0 1 auto;min-width:0;'
                 f'margin-left:{px(8)};font-size:{px(13)};color:{C["textBody"]}">{title}</span>'
                 f'<span style="flex:none;margin-left:{px(8)};font-size:{px(10)}">{extra_html}</span>'
                 f'<span style="flex:1 0 {px(20)}"></span>'
                 f'<span style="flex:none;font-size:{px(10)};color:{C["textMuted"]}">{age_text(age, lang)}</span></div>')
        # body + buttons (invite only on LFG posts; whisper stays left of the invite slot)
        name = names[0 if lang == "ko" else 1]
        text = texts[0 if lang == "ko" else 1]
        btn_w = 124 if kind == "lfg" else 66
        body = (f'<span style="color:{CLASS[cls]}">{esc(name)}</span>'
                f'<span style="color:{C["textMuted"]}">: {esc(text)}</span>')
        p.append(f'<div class="abs" style="left:{px(11)};bottom:{px(7)};height:{px(14)};display:flex;align-items:center">'
                 f'{fit(body, 11, 11, row_w - 24 - btn_w)}</div>')
        p.append(f'<div class="abs" style="left:0;top:0;width:{px(row_w)};height:{px(50)}">')
        if kind == "lfg":
            p.append(button(row_w - 1 - 8 - 54, 50 - 1 - 5 - 20, 54, 20, s["invite"], size=11))
        p.append(button(row_w - 1 - 8 - 54 - 4 - 54, 50 - 1 - 5 - 20, 54, 20, s["whisper"], size=11, accent=True))
        p.append('</div></div>')
    if len(POSTS) > vis:
        p.append(f'<div class="abs" style="{at(left + list_w - 4, list_y, 4, list_h)}background:rgba(52,76,91,.35)"></div>')
        p.append(f'<div class="abs" style="{at(left + list_w - 4, list_y, 4, max(20, list_h * vis / len(POSTS)))}background:rgba(127,216,176,.75)"></div>')

    # footer: text (16, 12), clear 110 x 22 (-12, 7), version left of it
    p.append(f'<div class="lbl" style="left:{px(16)};bottom:{px(10)};font-size:{px(10)};color:{C["textMuted"]}">'
             f'{esc(s["footer"] % (total, DB["expireMinutes"]))}</div>')
    p.append(button(W - 12 - 110, H - 7 - 22, 110, 22, s["clear"], size=11))
    p.append(f'<div class="lbl" style="right:{px(12 + 110 + 12)};bottom:{px(12)};font-size:{px(10)};color:{C["fontDisable"]}">'
             f'v{VERSION}&nbsp;&nbsp;·&nbsp;&nbsp;/ezgf</div>')

    win = (f'<div class="win" style="left:{ox}px;top:{oy}px;width:{px(W)};height:{px(H)}">' + "".join(p) + '</div>')

    # tooltip of the hovered post (showPostTooltip)
    post = POSTS[hover_index]
    klabel, kcol = kind_of(post, lang)
    tx, ty = ox + W * SCALE + 30, oy + (list_y + hover_index * 54 + 30) * SCALE
    tip_w = PAGE_W - tx - 22
    tip = (f'<div class="tip" style="left:{tx:.0f}px;top:{ty:.0f}px;width:{tip_w:.0f}px">'
           f'<div style="color:{kcol};font-size:16px">{esc(" / ".join(dname(k, lang) for k in post[0]))}</div>'
           f'<div class="dl"><span style="color:{CLASS[post[9]]}">{esc(post[8][0 if lang == "ko" else 1])}</span>'
           f'<span style="color:{kcol}">{esc(klabel)}</span></div>'
           f'<div style="color:{C["textBody"]}">{esc(post[11][0 if lang == "ko" else 1])}</div><div>&nbsp;</div>'
           f'<div class="dl" style="color:{C["textMuted"]}"><span>{esc(t[post[10]])}</span><span>{age_text(post[7], lang)}</span></div>'
           f'<div style="color:{C["textMuted"]}">{esc(s["tipClick"])}</div>'
           f'<div style="color:{C["textMuted"]}">{esc(s["tipAlt"])}</div></div>')

    def cx(v): return ox + v * SCALE
    def cy(v): return oy + v * SCALE
    calls = [(cx(-14), cy(79)),                                   # 1 tabs
             (cx(W + 16), cy(22)),                                # 2 settings
             (cx(-14), cy(260)),                                  # 3 dungeon list
             (cx(left + 136), cy(84)),                            # 4 search
             (cx(chip_x[2][0] + 20), cy(84)),                     # 5 filter chips
             (cx(chip_x[4][0] + 39), cy(84)),                     # 6 my role chip
             (cx(W + 16), cy(list_y + 25)),                       # 7 post rows
             (tx - 2, ty - 2),                                    # 8 tooltip
             (cx(-14), cy(H - 17))]                               # 9 footer
    calls_html = "".join(f'<div class="call" style="left:{x - 15:.0f}px;top:{y - 15:.0f}px">{i}</div>'
                         for i, (x, y) in enumerate(calls, 1))

    notes_top = oy + H * SCALE + 36
    left_n, right_n = t["notes"][:5], t["notes"][5:]
    notes = (f'<div class="abs" style="left:50px;top:{notes_top:.0f}px;width:{PAGE_W - 100}px">'
             f'<div style="display:flex;gap:50px"><div style="flex:1">{notes_html(left_n)}</div>'
             f'<div style="flex:1">{notes_html(right_n, 6)}</div></div>'
             f'<div class="foot">{esc(t["note"])}</div></div>')
    head = f'<div class="page"><h1>EzWoW - Group Finder</h1><div class="lead">{esc(t["head"])}</div></div>'
    return head + win + tip + calls_html + notes


# ---------------------------------------------------------------------------
# Settings window (UI/OptionsWindow.lua): 420 x 780
# ---------------------------------------------------------------------------
def settings_page(lang, icon_uri):
    s, t = L[lang], T[lang]
    W, H = 420, 780
    ox, oy = 72, 160
    p = header(W, s["settingsSub"], 320, icon_uri)

    def section(key, y):
        p.append(f'<div class="lbl" style="{at(20, y)}color:{C["accent"]}">{fit(esc(s[key]), 13, 10, 375)}</div>')
        p.append(f'<div class="abs" style="{at(20, y + 20, W - 40, 1)}background:rgba(52,76,91,.85)"></div>')

    def option(key, y, on):
        p.append(f'<div class="check{"" if on else " off"}" style="{at(23, y + 3)}"></div>')
        p.append(f'<div class="lbl" style="{at(48, y, None, 24)}display:flex;align-items:center;color:{C["textBody"]}">'
                 f'{fit(esc(s[key]), 12, 9, 345)}</div>')

    def small_text(key, y):
        p.append(f'<div class="abs" style="{at(24, y, 372)}font-size:{px(10)};line-height:1.12;color:{C["textMuted"]}">{esc(s[key])}</div>')

    section("secCollect", 70)
    option("optChannels", 94, True)
    option("optSay", 120, True)
    option("optGuild", 146, False)
    option("optAutoJoin", 172, True)
    p.append(f'<div class="lbl" style="{at(24, 206)}color:{C["textBody"]}">{fit(esc(s["optJoinChannels"]), 12, 9, 372)}</div>')
    p.append(f'<div class="edit" style="{at(22, 226, 376, 26)}padding-left:{px(9)}">'
             f'{fit(esc(s["joinPlaceholder"]), 12, 12, 360, "color:" + C["fontDisable"])}</div>')
    small_text("joinHint", 258)
    p.append(f'<div class="lbl" style="{at(24, 296)}color:{C["textBody"]}">{fit(esc(s["optExpire"]), 12, 9, 220)}</div>')
    p.append(button(250, 289, 27, 27, "-"))
    p.append(f'<div class="lbl" style="{at(281, 289, 50, 27)}display:flex;align-items:center;justify-content:center;'
             f'font-size:{px(12)};color:{C["textBody"]}">{esc(s["minutes"] % DB["expireMinutes"])}</div>')
    p.append(button(335, 289, 27, 27, "+"))

    section("secView", 330)
    option("optMyLevel", 354, False)
    option("optHideBoost", 380, False)
    option("optIcon", 406, True)

    section("secAlert", 446)
    option("optAlertMyLevel", 470, False)
    option("optSound", 496, True)
    small_text("watchHint", 526)

    section("secGreet", 566)
    option("optGreetSelf", 590, True)
    option("optGreetWelcome", 616, True)

    p.append(button(20, 652, 187, 28, f'{s["language"]}: Auto ▼'))
    p.append(button(213, 652, 187, 28, s["unblock"] % 1))
    p.append(button(20, H - 36 - 33, 185, 33, s["resetPos"]))
    p.append(button(W - 20 - 185, H - 36 - 33, 185, 33, s["donate"], accent=True))
    p.append(f'<div class="lbl" style="left:0;right:0;bottom:{px(10)};text-align:center;font-size:{px(10)};color:{C["fontDisable"]}">'
             f'EzWoW - Group Finder {VERSION}&nbsp;&nbsp;·&nbsp;&nbsp;/ezgf</div>')

    win = f'<div class="win" style="left:{ox}px;top:{oy}px;width:{px(W)};height:{px(H)}">' + "".join(p) + '</div>'
    # callouts on the right edge, one per block
    spans = [(70, 160), (160, 200), (200, 320), (330, 436), (446, 556), (566, 642), (652, 680), (H - 69, H - 36)]
    calls = "".join(f'<div class="call" style="left:{ox + W * SCALE + 18:.0f}px;top:{oy + (a + b) / 2 * SCALE - 15:.0f}px">{i}</div>'
                    for i, (a, b) in enumerate(spans, 1))
    nx = ox + W * SCALE + 80
    notes = (f'<div class="abs" style="left:{nx:.0f}px;top:{oy + 10}px;width:{PAGE_W - nx - 50:.0f}px">'
             f'{notes_html(t["sNotes"])}</div>')
    foot = f'<div class="abs foot" style="left:50px;top:{oy + H * SCALE + 30:.0f}px">{esc(t["note"])}</div>'
    head = (f'<div class="page"><h1>EzWoW - Group Finder <span class="badge">{esc(t["sBadge"])}</span></h1>'
            f'<div class="lead">{esc(t["sHead"])}</div></div>')
    return head + win + calls + notes + foot


# ---------------------------------------------------------------------------
# Rendering (headless Chrome: one pass to measure the height, one to capture)
# ---------------------------------------------------------------------------
def chrome_path():
    env = os.environ.get("CHROME")
    if env:
        return env
    for cand in (r"C:\Program Files\Google\Chrome\Application\chrome.exe",
                 r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
                 "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                 shutil.which("google-chrome") or "", shutil.which("chromium") or ""):
        if cand and Path(cand).exists():
            return cand
    sys.exit("Chrome not found; set CHROME to its path")


def render(chrome, profile, html_file, png, height=None):
    args = [chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars", f"--user-data-dir={profile}",
            "--force-device-scale-factor=1"]
    if height is None:
        res = subprocess.run(args + ["--window-size=1600,2000", "--dump-dom", html_file.as_uri()],
                             capture_output=True, timeout=120)
        m = re.search(rb'data-h="(\d+)"', res.stdout)
        if not m:
            sys.exit("could not measure " + str(html_file))
        return int(m.group(1))
    subprocess.run(args + [f"--window-size={PAGE_W},{height}", f"--screenshot={png}", html_file.as_uri()],
                   capture_output=True, timeout=120, check=True)
    return height


def main(root: Path):
    root = root.resolve()
    out = root / "docs" / "images"
    out.mkdir(parents=True, exist_ok=True)
    icon_uri = "data:image/png;base64," + base64.b64encode((root / "Media" / "Icon.png").read_bytes()).decode()
    chrome = chrome_path()
    work = Path(tempfile.mkdtemp(prefix="ezgf_readme_"))
    profile = work / "chrome_profile"
    try:
        for lang in ("ko", "en"):
            for name, fn in (("ui", ui_page), ("settings", settings_page)):
                body = fn(lang, icon_uri)
                page = (f'<!doctype html><html lang="{lang}"><head><meta charset="utf-8"><style>{CSS}</style></head>'
                        f'<body>{body}<script>{JS}</script></body></html>')
                html_file = work / f"{name}_{lang}.html"
                html_file.write_text(page, encoding="utf-8")
                png = out / f"{name}_{lang}.png"
                h = render(chrome, profile, html_file, png)
                render(chrome, profile, html_file, png, h)
                print("wrote", png, h)
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else "."))

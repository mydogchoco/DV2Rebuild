# -*- coding: utf-8 -*-
"""마을 NPC 이름/대사를 원작 stringsData_KR.xml 에서 추출 → data/npc_lines.json.

근거: TownNpcManager::showNpcText 가 NPC 마다 `NPC_<name>`(이름) + `<Name>Talk`(대사) 키 쌍을
조회한다(예 NPC_nuri / NooriTalk). 대사는 유실이 아니라 원작 문자열에 그대로 있다.
사용: python scripts/tools/build_npc_lines.py
"""
import json, os, re

XML = "DV2/string/stringsData_KR.xml"
OUT = "data/npc_lines.json"

# showNpcText 에서 축자 확인한 쌍 + 스파인 이름(sd_*) 대응.
# spine  : DV2/480/scene/town/elpis/sd_<spine>.spine_json
# name_key/talk_key : stringsData_KR.xml
NPC = [
    ("nuri",     "NPC_nuri",     "NooriTalk"),
    ("zumon",    "NPC_jimon",    "ZumunTalk"),
    ("popo",     "NPC_popo",     "PopoTalk"),
    ("romini",   "NPC_romini",   "RuminiTalk"),
    ("kanggalo", "NPC_kanggalo", "KangaloTalk"),
    ("randolph", "NPC_randolph", "RandolfTalk"),
    ("pino",     "NPC_pino",     "PinoTalk"),
    ("baruseu",  "NPC_baruseu",  "BarosTalk"),
    ("yuria",    "NPC_yulia",    "UriaTalk"),
    ("dilis",    "NPC_dilis",    "DelisTalk"),
    ("raon",     "NPC_raon",     "RaonTalk"),
    ("annie",    "NPC_annie",    "AnnieTalk"),
    # 아래 4종은 showNpcText 에 이름/대사 쌍이 안 보인다(배회 전용 행인으로 추정).
    ("aria",     "NPC_aida",     None),
    ("guy",      None,           None),
    ("grandma",  None,           None),
    ("nelson",   None,           None),
]


# ── 상점 대사 ────────────────────────────────────────────────────────────
# 원작 ShopScene 은 판매원 대사를 두 갈래로 고른다(ShopScene.c:4655 setSeller).
#   · 입장/탭 전환(+0x281) → idx = rand()%3 + 1 → `ShopWelcome<npc>_<idx>`
#   · 구매·판매 직후(+0x280) → idx = rand()%2 + 1 → `ShopBuy<npc>_<idx>` / `ShopSellromini_<idx>`
#   그리고 이 idx 가 **표정 index 로도 그대로** NpcManager 에 넘어간다
#   (`setSellerShow(…, 1, idx, …)` @:4767) — 대사와 표정이 짝이다.
# 예외: ETC(바루스)는 idx 를 1 로 고정(:4720), HOT 탭은 NPC 대사 대신 `ShopWelcomeHot` 고정(:4938).
SHOP_NPC = ["pino", "randolph", "popo", "baruseu", "romini", "raon"]
# 탭 공통 문구 — 우리 탭 id ↔ 원작 키. 세일 문구(ShopWelcomeSale*)는 세일 시스템이 없어 제외.
SHOP_TAB = {"hot": "ShopWelcomeHot", "food": "ShopWelcomeFood", "item": "ShopWelcomeItem",
            "egg": "ShopWelcomeEgg", "etc": "ShopWelcomeEtc", "sell": "ShopWelcomeSell"}


def collect_shop(S):
    """`<Prefix><npc>_<n>` 을 1번부터 끊길 때까지 모은다."""
    def series(prefix, npc):
        out, i = [], 1
        while "%s%s_%d" % (prefix, npc, i) in S:
            out.append(S["%s%s_%d" % (prefix, npc, i)])
            i += 1
        return out

    welcome, buy, sell = {}, {}, {}
    for npc in SHOP_NPC:
        for store, prefix in ((welcome, "ShopWelcome"), (buy, "ShopBuy"), (sell, "ShopSell")):
            lines = series(prefix, npc)
            if lines:
                store[npc] = lines
    tab = {k: S[v] for k, v in SHOP_TAB.items() if v in S}
    for npc in SHOP_NPC:
        print("  shop %-9s 환영 %d · 구매 %d · 판매 %d"
              % (npc, len(welcome.get(npc, [])), len(buy.get(npc, [])), len(sell.get(npc, []))))
    return {
        "_re_basis": "ShopScene::setSeller @docs/ref/orig_code/decomp/ShopScene.c:4655 "
                     "(입장 rand%3+1 / 구매·판매 rand%2+1, 그 idx = 표정 index)",
        "_note": "ETC(baruseu)는 idx 1 고정(:4720) · HOT 탭은 tab.hot 고정 문구(:4938). "
                 "randolph/popo 의 구매 대사는 원작이 특정 아이템 id(219·220·4000 / 카테고리 1)일 때만 "
                 "idx+2(_3/_4)를 쓰는데(:146~202) 우리 탭 구성엔 그 분류가 없어 _1/_2 만 쓴다.",
        "welcome": welcome, "buy": buy, "sell": sell, "tab": tab,
    }


# XML 미리 정의 엔티티. 수치 참조(`&#10;` = 줄바꿈)는 아래에서 따로 푼다.
XML_ENT = {"&lt;": "<", "&gt;": ">", "&quot;": '"', "&apos;": "'", "&amp;": "&"}


def unescape(s):
    """⚠️ 원작 문자열은 줄바꿈을 `&#10;` 로 넣어 둔다 — 안 풀면 대사에 그대로 찍힌다."""
    s = re.sub(r"&#(\d+);", lambda m: chr(int(m.group(1))), s)
    s = re.sub(r"&#x([0-9a-fA-F]+);", lambda m: chr(int(m.group(1), 16)), s)
    for ent, ch in XML_ENT.items():      # &amp; 는 마지막 — 먼저 풀면 이중 복원된다
        s = s.replace(ent, ch)
    return s


def load_strings(path):
    raw = open(path, encoding="utf-8", errors="replace").read()
    out = {}
    # ⚠️ 내용에 `<` 를 허용하면(re.S + .*?) **루트 태그가 문서 전체를 삼켜** 매치가 1개만 나온다.
    #    `[^<]*` 로 막아야 9,625개가 정상 추출된다.
    for k, v in re.findall(r"<([A-Za-z_][A-Za-z0-9_]*)>([^<]*)</\1>", raw):
        out.setdefault(k, unescape(v).strip())
    return out


def main():
    if not os.path.exists(XML):
        print("[skip] 원본 문자열 없음:", XML)
        return
    S = load_strings(XML)
    npcs = {}
    for spine, name_key, talk_key in NPC:
        name = S.get(name_key, "") if name_key else ""
        lines = []
        if talk_key:
            # <XxxTalk>, <XxxTalk1>, <XxxTalk2> … 순서대로
            if talk_key in S:
                lines.append(S[talk_key])
            i = 1
            while "%s%d" % (talk_key, i) in S:
                lines.append(S["%s%d" % (talk_key, i)])
                i += 1
        npcs[spine] = {"name": name, "name_key": name_key, "talk_key": talk_key, "lines": lines}
        print("%-9s %-8s 대사 %d줄" % (spine, name or "(이름없음)", len(lines)))
    doc = {
        "_source": "DV2/string/stringsData_KR.xml (원작 문자열, 유실 아님)",
        "_re_basis": "TownNpcManager::showNpcText 가 NPC_<name> + <Name>Talk 쌍을 조회한다",
        "_note": "aria/guy/grandma/nelson 은 showNpcText 에 쌍이 없다 — 배회 전용 행인으로 추정",
        "npcs": npcs,
        "shop": collect_shop(S),
    }
    os.makedirs("data", exist_ok=True)
    json.dump(doc, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("->", OUT, "총", sum(len(v["lines"]) for v in npcs.values()), "줄")


if __name__ == "__main__":
    main()

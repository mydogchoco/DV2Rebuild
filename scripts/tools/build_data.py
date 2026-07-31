"""Build master data JSON from user-restored sources.

  docs/input/dragons/dragons.csv  + docs/input/DragonStat.xlsx  ->  data/dragons.json + data/stat_table.json

- normalizes element 'water' -> 'aqua' (asset/spec key)
- stat_table[type][tier] = {base:{hp,att,def}, growth:{hp,att,def}}  (tier: 2/3/4/5/6a/6b)
"""
import csv, json, os, re, zipfile
import xml.etree.ElementTree as ET

NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
ELEMENT_FIX = {"water": "aqua"}
TYPE_ROWS = ["atk", "hp", "def", "ha", "ad", "hd"]          # sheet rows 2..7 order
TIER_COLS = ["2", "3", "4", "5", "6a", "6b", "custom"]       # sheet cols B..H order


def read_xlsx(path):
    z = zipfile.ZipFile(path)
    shared = []
    if "xl/sharedStrings.xml" in z.namelist():
        root = ET.fromstring(z.read("xl/sharedStrings.xml"))
        for si in root:
            shared.append("".join(t.text or "" for t in si.iter(NS + "t")))
    sheets = {}
    wb = ET.fromstring(z.read("xl/workbook.xml"))
    rels = ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))
    rid_to_target = {r.get("Id"): r.get("Target")
                     for r in rels if r.tag.endswith("Relationship")}
    order = []
    for s in wb.iter(NS + "sheet"):
        rid = s.get("{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id")
        order.append((s.get("name"), rid_to_target[rid]))
    for name, target in order:
        path_in = "xl/" + target.lstrip("/")
        root = ET.fromstring(z.read(path_in))
        grid = {}
        for c in root.iter(NS + "c"):
            ref = c.get("r"); t = c.get("t")
            v = c.find(NS + "v")
            if v is None:
                continue
            val = shared[int(v.text)] if t == "s" else v.text
            col = re.match(r"[A-Z]+", ref).group()
            row = int(re.match(r"[A-Z]+(\d+)", ref).group(1))
            grid[(row, col)] = val
        sheets[name] = grid
    return sheets


def parse_triplet(s):
    h, a, d = (int(x) for x in s.split("/"))
    return {"hp": h, "att": a, "def": d}


def build_stat_table(xlsx_path):
    sheets = read_xlsx(xlsx_path)
    names = list(sheets)
    base_grid = sheets[names[0]]    # "1레벨 최대 능력치"
    grow_grid = sheets[names[1]]    # "레벨업 최대 상승폭"
    cols = ["B", "C", "D", "E", "F", "G", "H"]
    table = {}
    for ri, typ in enumerate(TYPE_ROWS):
        row = ri + 2
        table[typ] = {}
        for ci, tier in enumerate(TIER_COLS):
            col = cols[ci]
            b = base_grid.get((row, col)); g = grow_grid.get((row, col))
            if not b or not g:
                continue
            table[typ][tier] = {"base": parse_triplet(b), "growth": parse_triplet(g)}
    return table


def tier_for(star, generation):
    """개체 스탯 곡선 열(DragonStat.xlsx 의 B~H). 성급 + 세대로 고른다.

    🔴 2026-07-29 수정: **자작(커스텀) 드래곤이 `custom` 열을 못 쓰고 있었다.**
    `generation` 이 "커스텀" 이면 숫자가 없어 `float(...)` 이 터지고 except 로 빠져 `6a` 가
    됐다. 그 결과 루시퍼·라 솔라·샛별·한울이 전부 6a 곡선(base hp 229 / att 27)으로 굴러
    사용자가 DragonStat.xlsx 의 `custom` 열에 적어 둔 값(base hp 640~650 / att 121~315)의
    3분의 1 수준이었다. 세대 표기가 '커스텀' 이면 무조건 custom 열을 쓴다.
    """
    gen = str(generation).strip()
    if gen in ("커스텀", "custom", "자작"):
        return "custom"
    s = str(star).strip()
    if s == "6":
        # split by generation: 4세대+ -> 6b, else 6a
        try:
            return "6b" if float(re.findall(r"[\d.]+", gen)[0]) >= 4 else "6a"
        except Exception:
            return "6a"
    return s if s in ("2", "3", "4", "5") else "4"


# 자작 드래곤이 다른 드래곤의 아트를 빌려 쓴다고 적는 관용구.
#   dragons.csv `notes` 예: `"루시퍼"와 동일한 이미지 사용`
# 원본 에셋에 그 id 의 스파인이 없을 때만 본다(원본이 있으면 당연히 원본이 우선).
ART_ALIAS_RE = re.compile(r'[“"\'](?P<name>[^“”"\']+)[”"\']\s*와?\s*동일한\s*이미지')


def build_dragons(csv_path):
    SRC = "DV2/480/dragon"
    rows = [r for r in csv.DictReader(open(csv_path, encoding="utf-8-sig"))
            if r["name"].strip()]   # 이름 칸이 아예 빈 행 = 미기입 → 건너뛴다
                                    # (낱말 `null` 은 '정해지지 않음' 이라 아래에서 따로 다룬다)
    by_name = {r["name"].strip(): r["id"].strip() for r in rows}
    # 각성스킬 열 이름은 안내문이 괄호로 붙어 있다("각성스킬id(skill_awaken.csv의 id 숫자)")
    # → 접두사로 찾는다. 시트에서 열 이름을 다듬어도 안 깨지게.
    awaken_col = next((k for k in (rows[0] if rows else {}) if k.startswith("각성스킬id")), None)

    out = []
    for r in rows:
        did = r["id"].strip()
        el = r["element"].strip().lower()
        el = ELEMENT_FIX.get(el, el)

        # 아트 출처 id — 기본은 자기 자신. 자기 스파인이 없고 notes 가 다른 드래곤을 가리키면
        # 그쪽 id 를 쓴다. 스파인·초상·알·크리티컬 아트 경로가 전부 이 id 로 조립된다.
        art = did
        note = (r.get("notes") or "").strip()
        if not os.path.exists(f"{SRC}/dragon_{did}_adult_spine.spine_json"):
            m = ART_ALIAS_RE.search(note)
            if m:
                src_name = m.group("name").strip()
                if src_name in by_name:
                    art = by_name[src_name]
                else:
                    raise SystemExit(
                        "dragons.csv id=%s notes 가 '%s' 를 가리키는데 그런 드래곤이 없다"
                        % (did, src_name))

        stages = {}
        for st in ("baby", "child", "adult"):
            p = f"{SRC}/dragon_{art}_{st}_spine.spine_json"
            if os.path.exists(p):
                stages[st] = f"dragon_{art}_{st}_spine"
        # 사용자가 "아직/영영 정해지지 않음" 을 CSV 에 낱말 `null` 로 적는다
        # (600·700 = '선택권으로 지정한 드래곤의 디자인·속성·별명을 따름').
        name = r["name"].strip()
        by_player = name.lower() == "null"
        if by_player:
            name = ""
        if el == "null":
            el = ""
        e = {
            "id": int(did),
            "name": name,
            "element": el or None,
            "type": r["type"].strip() or None,
            "star": int(r["star"]) if r["star"].strip().isdigit() else None,
            "generation": r["generation"].strip() or None,
            "stat_tier": tier_for(r["star"], r["generation"]) if r["star"].strip().isdigit() else None,
            "stages": stages,
        }
        # 도감 설명(사용자 기입). 원작 도감 텍스트는 서버 소유라 유실됐고, 자작 드래곤은
        # 애초에 사용자만 쓸 수 있다 → CSV 열을 그대로 싣는다.
        # 엑셀/웹에서 붙여 넣은 텍스트에 U+00A0(비분리 공백)이 82군데 섞여 있다. 도감 설명은
        # 원작 비트맵 폰트(font_common)로 그리는데 그 글리프가 없어 두부로 뜬다 → 보통 공백으로.
        desc = (r.get("도감 설명") or "").replace(" ", " ").strip()
        if desc:
            e["desc"] = desc
        # 각성 스킬 배정(사용자 기입). 값 = docs/input/sheets/skill_awaken.csv 의 id.
        # 이 열이 **드래곤별 배정의 정본**이다 — skill_awaken.csv 의 `비고`(드래곤 이름들)는
        # 같은 사실을 스킬 쪽에서 적은 것이라 `build_skill_awaken.py` 가 둘을 대조한다.
        aw = (r.get(awaken_col) or "").strip() if awaken_col else ""
        if aw.isdigit():
            e["awaken_skill"] = int(aw)
        if by_player:
            # 이름·속성·디자인이 **플레이어 선택권**으로 정해지는 드래곤(600·700).
            # 사용자 확정(2026-07-30): **기본적으로 도감에서 제외**하고 특수 트리거로만 보인다.
            #   · `dex_hidden` = 목록·집계·입수처(알 뽑기·부화·조합 랜덤 풀)에서 빠진다.
            #   · 트리거 = 그 종을 실제로 얻은 이력(`UserDB.dex_step > 0`) — 선택권으로
            #     받았을 때만 도감에 나타난다. 판정은 `cave.gd::_dex_ids`.
            e["name_from_player"] = True
            e["dex_hidden"] = True
            e["_dex_hidden_basis"] = ("이름 미정(CSV `null`) = 미구현 더미. 사용자 확정 2026-07-30: "
                                      "기본 제외 · 특수 트리거(보유 이력)로만 도감 노출.")
            e["_player_basis"] = note
        if (r["generation"].strip() or "") == "커스텀":
            # **커스텀 세대(600·700·666·777)는 무작위 입수 경로에서 통째로 빠진다.**
            # 사용자 확정(2026-07-30): 지정된 방법으로만 얻는다 —
            #   · 600(수비형)·700(공격형) = 점술집 '드래곤 소환'(`scripts/systems/summon.gd`)
            #   · 666 샛별 · 777 한울    = 점술집 '카드 코드'(`magicshop.gd::_grant_card_reward`)
            # `dex_hidden`(600·700)과는 다른 축이다 — 666·777 은 도감에 정상 등재되지만
            # 뽑기·부화·조합 같은 **랜덤 풀에는 절대 들어가지 않는다**.
            # 이 플래그를 보는 곳: `Data.dragon_ids_random()` · `EggGacha.candidates()`.
            e["acquire_locked"] = True
            e["_acquire_basis"] = ("커스텀 세대 = 지정 획득처 전용(사용자 확정 2026-07-30). "
                                   "600·700=드래곤 소환 / 666·777=카드 코드. "
                                   "가챠·부화·조합·탐험 등 무작위 풀에서 제외.")
        if art != did:
            # render 층은 `Data.art_id(id)` 로 이 값을 읽어 아트 경로를 만든다.
            e["art_id"] = int(art)
            e["_art_basis"] = "dragons.csv notes: %s" % note
        out.append(e)
    return out


if __name__ == "__main__":
    os.makedirs("data", exist_ok=True)
    table = build_stat_table("docs/input/DragonStat.xlsx")
    json.dump(table, open("data/stat_table.json", "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    dragons = build_dragons("docs/input/dragons/dragons.csv")
    json.dump(dragons, open("data/dragons.json", "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print(f"data/stat_table.json: types={list(table)} tiers(atk)={list(table['atk'])}")
    print(f"data/dragons.json: {len(dragons)} dragons")
    # quick validation
    from collections import Counter
    bad_el = sorted(set(d["element"] for d in dragons if d["element"] not in
                    {"aqua","earth","fire","wind","light","dark","holy","chaos","shadow",None}))
    bad_ty = sorted(set(d["type"] for d in dragons if d["type"] not in
                    {"atk","hp","def","ha","ad","hd",None}))
    print("  unexpected elements:", bad_el or "none")
    print("  unexpected types:", bad_ty or "none")
    print("  example:", json.dumps(dragons[0], ensure_ascii=False))

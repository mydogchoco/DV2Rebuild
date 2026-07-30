"""장비 아이콘 몽타주 + 검수 CSV — "장비로 매핑한 것이 진짜 장비인가" 확인용.

배경: `data/equipment.json` 의 카탈로그 111종을 `data/icon_map.json` 으로 원본 아틀라스
`item_accessory`(127프레임)에 붙여 뒀는데, **프레임 이름만 보고 붙인 것**이라 종류·등급이
어긋났을 수 있다. 실제로 한 번 어긋난 적이 있다(최고등급 이름이 종류와 달라
"아만타의 금우"=깃털을 못 찾던 건 — `Icons.equip_texture` 주석).

원작 근거로 확정된 것(=사용자가 다시 볼 필요 없는 것):
  · 장비 6종의 코드 이름 = `stringsData_KR.xml` :98~103
      claw 발톱 / feather 깃털 / charm 부적 / platinum 백금석 / catseye 묘안석 / obsidian 흑요석
  · 장비의 주 능력 종류 = `Item::getTypeDetail()` 문자열 13종(`Equip::getGradeImage`)
      CRITICAL 크리확률 / FEE 회피 / STUN 행동불능치유 / CRIPOWER 크리파워 / PUREDMG 관통 /
      ULTIMATE 각성게이지 / PUREDEDMG 관통감소 / ACCURACY 명중 / PRIVATE 전용장비 /
      BOOST·REQHP·BNR·DEDMG·INRATE·DERATE = 아티팩트 6종
    (짝은 libgame.so 문자열 테이블 0x2061c00 부근에서 `CaveItemEquipComentN` 과 1:1로 붙어 있다)

따라서 이 시트에서 봐 주실 것은 **"등급 순서와 그림이 맞나"** 뿐이다:
  - feather1..7 이 정말 허름한→아만타 순인가 (역순/뒤섞임 아닌가)
  - talisman 은 6등급인데 깃털·발톱은 7등급 — 맞나
  - catseye/obsidian/platinum 의 등급 이름(작은/깨진/…)이 맞나
  - `gooddeco` `olddeco` `artifact1~6_bg` 처럼 우리가 안 쓰는 프레임이 무엇인가

출력:
  docs/input/sheets/equipment_icons_NN.png   아이콘 격자(번호·우리 이름·주능력·프레임명)
  docs/input/sheets/equipment_check.csv      같은 번호를 키로 갖는 검수 CSV(UTF-8 BOM)

usage:  python scripts/tools/build_equip_sheet.py
"""
import csv, json, os, re, sys
from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CONV = os.path.join(ROOT, "assets", "converted")
OUT = os.path.join(ROOT, "docs", "input", "sheets")
ATLAS = "item_accessory"

FONT_CANDIDATES = [r"C:\Windows\Fonts\malgun.ttf", r"C:\Windows\Fonts\malgunbd.ttf"]

CELL_W, CELL_H = 176, 158
ICON_BOX = 76
COLS = 8
MARGIN = 24
HDR_H = 36
PAGE_ROWS = 7

BG = (250, 248, 244)
GRID = (222, 216, 206)
HDR_BG = (232, 224, 210)
TXT = (40, 36, 30)
SUB = (128, 120, 108)
WARN = (178, 96, 40)

# 스탯키 → 한글(equipment.json stat_keys 와 같은 뜻, 라벨은 짧게)
STAT_KR = {
    "hp": "생명력", "att": "공격력", "def": "방어력", "blk": "방어율", "evd": "회피율",
    "cri": "크리확률", "cri_pow": "크리파워", "pure": "관통", "depure": "관통감소",
    "accuracy": "명중", "cure": "행동불능치유", "awaken_rate": "각성게이지",
    "gold": "골드", "exp": "경험치",
}

# 원작 typeDetail(= Item::getTypeDetail) ↔ 주능력. 위 docstring 의 근거표.
TYPEDETAIL = {
    "cri": "CRITICAL", "evd": "FEE", "cure": "STUN", "cri_pow": "CRIPOWER",
    "pure": "PUREDMG", "awaken_rate": "ULTIMATE", "depure": "PUREDEDMG",
    "accuracy": "ACCURACY",
}
ARTIFACT_TYPEDETAIL = {
    "이그니스": "BOOST", "마리스": "REQHP", "테라": "BNR",
    "벤투스": "DEDMG", "루멘": "INRATE", "옵스큐럼": "DERATE",
}

# 그룹 순서(몽타주 · CSV 공통)
BG_GROUP = "희귀도 실루엣(_bg, 우리 미사용)"
GROUP_ORDER = ["기본 장비", "아티팩트", "이벤트 장비", BG_GROUP, "정체 미상"]

# `_bg` 프레임의 정체 — 흰 실루엣이다. 원작은 아이콘 **뒤에** 이걸 깔고 희귀도 색을 입힌다:
#   Equip::getGradeImageSmallSprite() → getGradeImageSmall()(= "<이름>_bg.png") 로 스프라이트를
#   만든 뒤 rarity(1~6)에 따라 setColor. 1(일반)은 아예 안 그린다.
BG_NOTE = "아이콘 뒤 희귀도 색 실루엣(Equip::getGradeImageSmallSprite — 매직=E6E6E6/레어=7AF04C/유니크=FFF600/에픽=FF3924/초월=00FFEA)"


def font(sz, bold=False):
    for p in (FONT_CANDIDATES[::-1] if bold else FONT_CANDIDATES):
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()


def load_frames(dirname):
    """<dir>/*.tres 의 region 을 읽어 {키: (png경로, Rect)}."""
    d = os.path.join(CONV, dirname)
    out = {}
    for fn in sorted(os.listdir(d)):
        if not fn.endswith(".tres"):
            continue
        txt = open(os.path.join(d, fn), encoding="utf-8").read()
        m_png = re.search(r'path="res://assets/converted/[^"]*/([^"/]+\.png)"', txt)
        m_rc = re.search(r"region = Rect2\(([-\d.]+), ([-\d.]+), ([-\d.]+), ([-\d.]+)\)", txt)
        if not (m_png and m_rc):
            continue
        out[fn[:-5]] = (os.path.join(d, m_png.group(1)),
                        tuple(int(float(g)) for g in m_rc.groups()))
    return out


_sheets = {}


def crop_icon(png, rect):
    """PMA 합성(out = rgb + bg*(1-a)) 후 셀에 맞춰 축소. 확대는 하지 않는다."""
    if png not in _sheets:
        _sheets[png] = Image.open(png).convert("RGBA")
    x, y, w, h = rect
    src = _sheets[png].crop((x, y, x + w, y + h))
    inv = src.getchannel("A").point(lambda v: 255 - v)
    bg = Image.new("RGB", src.size, BG)
    bg = ImageChops.multiply(bg, Image.merge("RGB", (inv, inv, inv)))
    out = ImageChops.add(src.convert("RGB"), bg)
    s = min(ICON_BOX / out.width, ICON_BOX / out.height, 1.0)
    if s < 1.0:
        out = out.resize((max(1, int(out.width * s)), max(1, int(out.height * s))), Image.LANCZOS)
    return out


def ellipsize(draw, text, fnt, max_w):
    if draw.textlength(text, font=fnt) <= max_w:
        return text
    while text and draw.textlength(text + "…", font=fnt) > max_w:
        text = text[:-1]
    return text + "…"


def wrap(draw, text, fnt, max_w, max_lines=2):
    lines, cur = [], ""
    for ch in text:
        if draw.textlength(cur + ch, font=fnt) <= max_w:
            cur += ch
            continue
        lines.append(cur)
        cur = ch
        if len(lines) == max_lines:
            break
    if len(lines) < max_lines:
        lines.append(cur)
    elif cur:
        lines[-1] = ellipsize(draw, lines[-1] + cur, fnt, max_w)
    return [l for l in lines if l]


def stat_label(main):
    """{'cri': 13} → '크리확률 +13'"""
    return " · ".join("%s +%s" % (STAT_KR.get(k, k), v) for k, v in main.items())


def build_rows(equip, icon_map, frames):
    """프레임 127개 ← 우리 매핑 역인덱스. 미매핑 프레임도 행으로 남긴다."""
    # 역인덱스: 프레임명 → (섹션, 논리키)
    rev = {}
    for section in ("equipment_basic", "artifact", "event"):
        for key, e in (icon_map.get(section, {}) or {}).items():
            if isinstance(e, dict) and e.get("dir") == ATLAS:
                rev[e["frame"]] = (section, key)

    basic = equip.get("basic", {})
    arts = equip.get("artifacts", {})
    art_grades = arts.get("grades", [])
    ev_by_name = {e["name"]: e for e in equip.get("event", [])}

    rows = []
    for frame in sorted(frames):
        sec_key = rev.get(frame)
        r = {"frame": frame, "group": None, "name": "", "main": "", "typedetail": "",
             "note": "", "catalog_key": ""}
        if sec_key is None:
            if frame.endswith("_bg"):
                r["group"] = BG_GROUP
                r["note"] = BG_NOTE
            else:
                r["group"] = "정체 미상"
                r["note"] = "우리 매핑 없음 — 무엇인지 알려주세요"
            rows.append(r)
            continue
        section, key = sec_key
        if section == "equipment_basic":
            kind, gi = key.split(":")
            spec = basic.get(kind, {})
            grades = spec.get("grades", [])
            g = grades[int(gi)] if int(gi) < len(grades) else {}
            r["group"] = "기본 장비"
            r["name"] = g.get("name", "")
            r["main"] = "%s +%s" % (STAT_KR.get(spec.get("stat", ""), spec.get("stat", "")),
                                    g.get("value", "?"))
            r["typedetail"] = TYPEDETAIL.get(spec.get("stat", ""), "")
            r["catalog_key"] = "basic:%s:%s" % (kind, gi)
            r["note"] = "%s %d등급(0=최하)" % (kind, int(gi))
        elif section == "artifact":
            kind, gi = key.split(":")
            gname = art_grades[int(gi)] if int(gi) < len(art_grades) else ""
            eff = ""
            for t in arts.get("types", []):
                if t.get("name") == kind:
                    eff = t.get("effect", "")
            r["group"] = "아티팩트"
            r["name"] = "%s %s" % (gname, kind)
            r["main"] = eff
            r["typedetail"] = ARTIFACT_TYPEDETAIL.get(kind, "")
            r["catalog_key"] = "artifact:%s:%s" % (kind, gi)
            r["note"] = "%s %d등급(0=파손된)" % (kind, int(gi))
        else:
            e = ev_by_name.get(key, {})
            r["group"] = "이벤트 장비"
            r["name"] = key
            r["main"] = stat_label(e.get("main", {}))
            r["typedetail"] = TYPEDETAIL.get(next(iter(e.get("main", {})), ""), "")
            r["catalog_key"] = "event:%s" % key
            r["note"] = e.get("event", "")
        rows.append(r)

    # 아이콘이 없는 장비(이벤트 19 · 특수 12) — 몽타주에는 못 올리고 CSV 에만 둔다.
    noicon = []
    mapped_ev = {k for k in (icon_map.get("event", {}) or {})}
    for e in equip.get("event", []):
        if e["name"] in mapped_ev:
            continue
        noicon.append({"frame": "", "group": "아이콘 없음(이벤트)", "name": e["name"],
                       "main": stat_label(e.get("main", {})),
                       "typedetail": TYPEDETAIL.get(next(iter(e.get("main", {})), ""), ""),
                       "catalog_key": "event:%s" % e["name"], "note": e.get("event", "")})
    for fam, fd in (equip.get("special", {}) or {}).items():
        if not isinstance(fd, dict):
            continue
        for it in fd.get("items", []):
            noicon.append({"frame": "", "group": "아이콘 없음(특수)", "name": it["name"],
                           "main": stat_label(it.get("main", {})),
                           "typedetail": TYPEDETAIL.get(next(iter(it.get("main", {})), ""), ""),
                           "catalog_key": "special:%s:%s" % (fam, it["name"]),
                           "note": fd.get("name", fam)})
    return rows, noicon


def paint(groups, outdir):
    f_hdr, f_name, f_sub, f_id, f_no = (font(19, True), font(14), font(12), font(11), font(13, True))
    state = {"pages": 0, "page": None, "draw": None, "y": 0}

    def new_page():
        w = MARGIN * 2 + CELL_W * COLS
        h = MARGIN * 2 + (CELL_H + 6) * PAGE_ROWS + HDR_H * 3
        state["page"] = Image.new("RGB", (w, h), BG)
        state["draw"] = ImageDraw.Draw(state["page"])
        state["y"] = MARGIN
        state["pages"] += 1

    def flush():
        p = state["page"]
        if p is not None:
            p.crop((0, 0, p.width, min(p.height, state["y"] + MARGIN))) \
             .save(os.path.join(outdir, "equipment_icons_%02d.png" % state["pages"]))

    def header(title):
        d = state["draw"]
        d.rectangle([MARGIN, state["y"], state["page"].width - MARGIN, state["y"] + HDR_H - 6],
                    fill=HDR_BG)
        d.text((MARGIN + 10, state["y"] + 5), title, font=f_hdr, fill=TXT)
        state["y"] += HDR_H

    new_page()
    for gname, gr in groups:
        if state["y"] + HDR_H + CELL_H > state["page"].height - MARGIN:
            flush(); new_page()
        header("%s   (%d)" % (gname, len(gr)))
        for i, r in enumerate(gr):
            col = i % COLS
            if i and col == 0:
                state["y"] += CELL_H + 6
                if state["y"] + CELL_H > state["page"].height - MARGIN:
                    flush(); new_page(); header("%s (계속)" % gname)
            d = state["draw"]
            x = MARGIN + col * CELL_W
            y = state["y"]
            d.rectangle([x, y, x + CELL_W - 4, y + CELL_H - 4], outline=GRID)
            ic = crop_icon(*r["src"])
            state["page"].paste(ic, (x + (CELL_W - 4 - ic.width) // 2,
                                     y + 6 + (ICON_BOX - ic.height) // 2))
            d.text((x + 6, y + 5), "#%d" % r["no"], font=f_no, fill=WARN)
            ty = y + 6 + ICON_BOX + 2
            for ln in wrap(d, r["name"] or "(우리 매핑 없음)", f_name, CELL_W - 14):
                d.text((x + 7, ty), ln, font=f_name, fill=TXT)
                ty += 17
            if r["main"]:
                d.text((x + 7, ty), ellipsize(d, r["main"], f_sub, CELL_W - 14), font=f_sub, fill=SUB)
                ty += 15
            d.text((x + 7, ty), ellipsize(d, r["frame"], f_id, CELL_W - 14), font=f_id, fill=SUB)
        state["y"] += CELL_H + 6
    flush()
    return state["pages"]


def main():
    os.makedirs(OUT, exist_ok=True)
    equip = json.load(open(os.path.join(ROOT, "data", "equipment.json"), encoding="utf-8"))
    icon_map = json.load(open(os.path.join(ROOT, "data", "icon_map.json"), encoding="utf-8"))
    frames = load_frames(ATLAS)

    rows, noicon = build_rows(equip, icon_map, frames)
    for r in rows:
        r["src"] = frames[r["frame"]]

    order = {g: i for i, g in enumerate(GROUP_ORDER)}
    rows.sort(key=lambda r: (order.get(r["group"], 99), r["frame"]))

    groups = []
    for r in rows:
        if not groups or groups[-1][0] != r["group"]:
            groups.append((r["group"], []))
        groups[-1][1].append(r)

    n = 0
    for _, gr in groups:
        for r in gr:
            n += 1
            r["no"] = n
    for r in noicon:
        n += 1
        r["no"] = n

    pages = paint(groups, OUT)
    write_csv(rows + noicon, OUT)
    print("프레임 %d + 아이콘없는 장비 %d / 페이지 %d장" % (len(rows), len(noicon), pages))
    print("→", os.path.join(OUT, "equipment_check.csv"))


def write_csv(rows, outdir):
    p = os.path.join(outdir, "equipment_check.csv")
    with open(p, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["번호", "구분", "우리이름", "주능력(현재값)", "프레임(원본)",
                    "원작 typeDetail(확정)", "카탈로그키", "참고",
                    "맞나요(O/X)", "실제 이름·등급", "비고"])
        for r in rows:
            w.writerow([r["no"], r["group"], r["name"], r["main"], r["frame"],
                        r["typedetail"], r["catalog_key"], r["note"], "", "", ""])


if __name__ == "__main__":
    main()

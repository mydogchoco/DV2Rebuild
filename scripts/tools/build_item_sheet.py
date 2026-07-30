"""아이템 아이콘 몽타주(콘택트 시트) + 용도 입력용 CSV 스켈레톤 생성.

목적: `data/items.json` 의 **용도(effect) 매핑이 전부 비어 있어**(257종 effect=null,
그중 151종은 어디서도 참조되지 않음) 사용자가 원작 지식으로 채워야 한다. 눈으로 아이콘을
보면서 채울 수 있도록 (1) 아이콘 격자 이미지 (2) 같은 번호를 키로 갖는 CSV 를 함께 낸다.

출력:
  docs/input/items/items_NN.png   아이콘 격자(번호·한글이름·id 라벨)
  docs/input/items/items.csv      번호,id,이름,분류,용도,설명 + 참고 열(현재상태·참조처·시트)
  docs/input/items/groups.csv     분류/세부분류 39줄 — 규칙이 같은 무리는 여기 한 줄로 끝낸다

채워서 돌려주면 items.json 의 effect/offline 과 data/item_effects.json 에 반영한다.
작성 요령은 docs/input/items/README.md.

주의:
  · 변환 산출물 PNG 는 **PMA(프리멀티플라이드 알파)** 다 → out = rgb + bg*(1-a) 로 합성한다.
    (스트레이트로 잘못 합성하면 반투명 가장자리가 하얗게 뜬다)
  · 프레임 회전은 변환 단계에서 이미 정규화됐다(fix_rotated_frames.py) → 여기서 보정 금지.

usage:
  python scripts/tools/build_item_sheet.py
  python scripts/tools/build_item_sheet.py --dirs item_accessory,item_gem   # 장비·젬까지
  python scripts/tools/build_item_sheet.py --only-todo                      # 미배선만
"""
import argparse, csv, json, os, re, sys
from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CONV = os.path.join(ROOT, "assets", "converted")
OUTDIR = os.path.join(ROOT, "docs", "_item_sheet")

# 기본 대상 = items.json 이 쓰는 7개 아이템 아틀라스.
# 장비(item_accessory)·젬(item_gem)은 equipment.json/gems.json 이 위키 확정 효과를 이미
# 들고 있어 제외한다. 필요하면 --dirs 로 추가.
DEFAULT_DIRS = ["item_food", "item_egg", "item_mtr", "item_etc",
                "item_doc", "item_quest", "item_spc"]

# 라벨용 한글 폰트(Windows 기본). 없으면 PIL 기본 폰트로 떨어진다(한글은 두부).
FONT_CANDIDATES = [r"C:\Windows\Fonts\malgun.ttf", r"C:\Windows\Fonts\malgunbd.ttf"]

CELL_W, CELL_H = 168, 146      # 셀 크기
ICON_BOX = 74                  # 아이콘이 들어갈 정사각 영역
COLS = 8
MARGIN = 24
HDR_H = 34                     # 그룹 머리글 높이
PAGE_ROWS = 7                  # 페이지당 셀 행 수

BG = (250, 248, 244)
GRID = (222, 216, 206)
HDR_BG = (232, 224, 210)
TXT = (40, 36, 30)
SUB = (128, 120, 108)


def font(sz, bold=False):
    for p in (FONT_CANDIDATES[::-1] if bold else FONT_CANDIDATES):
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()


def load_frames(dirname):
    """<dir>/*.tres 의 region 을 읽어 {키: (png경로, Rect)} 로 돌려준다."""
    d = os.path.join(CONV, dirname)
    if not os.path.isdir(d):
        return {}
    out = {}
    for fn in sorted(os.listdir(d)):
        if not fn.endswith(".tres"):
            continue
        txt = open(os.path.join(d, fn), encoding="utf-8").read()
        m_png = re.search(r'path="res://assets/converted/[^"]*/([^"/]+\.png)"', txt)
        m_rc = re.search(r"region = Rect2\(([-\d.]+), ([-\d.]+), ([-\d.]+), ([-\d.]+)\)", txt)
        if not (m_png and m_rc):
            continue
        rect = tuple(int(float(g)) for g in m_rc.groups())
        out[fn[:-5]] = (os.path.join(d, m_png.group(1)), rect)
    return out


_sheets = {}


def crop_icon(png, rect):
    """PMA 합성 + 셀 크기에 맞춰 축소. 원본보다 키우지는 않는다."""
    if png not in _sheets:
        _sheets[png] = Image.open(png).convert("RGBA")
    x, y, w, h = rect
    src = _sheets[png].crop((x, y, x + w, y + h))
    # PMA 합성: out = rgb + bg*(1-a)
    inv = src.getchannel("A").point(lambda v: 255 - v)
    bg = Image.new("RGB", src.size, BG)
    bg = ImageChops.multiply(bg, Image.merge("RGB", (inv, inv, inv)))
    out = ImageChops.add(src.convert("RGB"), bg)
    s = min(ICON_BOX / out.width, ICON_BOX / out.height, 1.0)
    if s < 1.0:
        out = out.resize((max(1, int(out.width * s)), max(1, int(out.height * s))),
                         Image.LANCZOS)
    return out


def ellipsize(draw, text, fnt, max_w):
    if draw.textlength(text, font=fnt) <= max_w:
        return text
    while text and draw.textlength(text + "…", font=fnt) > max_w:
        text = text[:-1]
    return text + "…"


def wrap(draw, text, fnt, max_w, max_lines=2):
    """이름은 셀 폭에서 최대 2줄로 접는다(잘림 최소화). 넘치면 마지막 줄만 말줄임."""
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


def status_of(entry, refs):
    """CSV 참고열 '현재상태' — 사용자가 어디부터 채우면 되는지 가늠하는 값."""
    if entry is None:
        return "아이콘만(items.json 미등록)"
    off = entry.get("offline", "")
    if off in ("todo", "stub"):
        return "미배선(%s)" % off
    if refs:
        return "배선됨"
    return "미참조(어디서도 안 씀)"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dirs", default=",".join(DEFAULT_DIRS))
    ap.add_argument("--out", default=OUTDIR)
    ap.add_argument("--only-todo", action="store_true",
                    help="현재상태가 '배선됨'인 것을 빼고 낸다(채울 것만)")
    args = ap.parse_args()
    dirs = [d.strip() for d in args.dirs.split(",") if d.strip()]
    os.makedirs(args.out, exist_ok=True)

    items = json.load(open(os.path.join(ROOT, "data", "items.json"), encoding="utf-8"))
    refs = build_refs(set(items))

    # 프레임 → 아이템 엔트리 결합. items.json 의 icon 은 "<dir>/<frame>" 이다.
    by_icon = {v["icon"]: (k, v) for k, v in items.items() if v.get("icon")}
    rows = []
    for d in dirs:
        frames = load_frames(d)
        if not frames:
            print("[warn] 프레임 없음:", d)
            continue
        for frame, (png, rect) in frames.items():
            key, entry = by_icon.get("%s/%s" % (d, frame), (None, None))
            r = {
                "dir": d, "frame": frame, "png": png, "rect": rect,
                "id": key or "", "entry": entry,
                "name": (entry or {}).get("name", ""),
                "cat": (entry or {}).get("category", ""),
                "sub": (entry or {}).get("subcategory", ""),
                "refs": refs.get(key, []) if key else [],
            }
            r["status"] = status_of(entry, r["refs"])
            rows.append(r)
    if args.only_todo:
        rows = [r for r in rows if r["status"] != "배선됨"]

    # 그룹: 분류/세부분류. 미등록 아이콘은 아틀라스별로 맨 뒤.
    def gkey(r):
        if r["entry"] is None:
            return ("~미등록", r["dir"])
        return (r["cat"], r["sub"])
    rows.sort(key=lambda r: (gkey(r), r["id"] or r["frame"]))

    groups = []
    for r in rows:
        if not groups or groups[-1][0] != gkey(r):
            groups.append((gkey(r), []))
        groups[-1][1].append(r)

    # 번호 부여(=CSV 키). 그룹 순서대로 1부터.
    n = 0
    for _, gr in groups:
        for r in gr:
            n += 1
            r["no"] = n

    pages = paint(groups, args.out)
    write_csv(rows, args.out)
    write_groups_csv(groups, args.out)
    print("아이콘 %d개 / 그룹 %d개 / 페이지 %d장" % (len(rows), len(groups), pages))
    print("→", os.path.join(args.out, "items.csv"), "/ groups.csv")


def build_refs(ids):
    """아이템 id 가 data/*.json · scripts/**.gd 어디서 쓰이는지(문자열 리터럴 기준)."""
    hits = {}
    targets = []
    for base, exts in (("data", (".json",)), ("scripts", (".gd",))):
        for dp, _, fs in os.walk(os.path.join(ROOT, base)):
            for f in fs:
                if f.endswith(exts) and f != "items.json":
                    targets.append(os.path.join(dp, f))
    for p in targets:
        try:
            t = open(p, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        rel = os.path.relpath(p, ROOT).replace(os.sep, "/")
        for i in ids:
            if '"%s"' % i in t:
                hits.setdefault(i, []).append(rel)
    return hits


def paint(groups, outdir):
    f_hdr, f_name, f_id, f_no = font(19, True), font(14), font(11), font(13, True)
    pages, page, rows_used = 0, None, 0
    draw = None
    y = 0

    def new_page():
        nonlocal page, draw, y, rows_used, pages
        w = MARGIN * 2 + CELL_W * COLS
        h = MARGIN * 2 + (CELL_H + 6) * PAGE_ROWS + HDR_H * 3
        page = Image.new("RGB", (w, h), BG)
        draw = ImageDraw.Draw(page)
        y = MARGIN
        rows_used = 0
        pages += 1

    def flush():
        if page is not None:
            # 아래쪽 빈 공간은 잘라낸다(마지막 장이 허옇게 비는 것 방지).
            page.crop((0, 0, page.width, min(page.height, y + MARGIN))) \
                .save(os.path.join(outdir, "items_%02d.png" % pages))

    new_page()
    for (cat, sub), gr in groups:
        need = HDR_H + (CELL_H + 6) * ((len(gr) + COLS - 1) // COLS)
        if rows_used > 0 and y + min(need, HDR_H + CELL_H + 6) > page.height - MARGIN:
            flush(); new_page()
        draw.rectangle([MARGIN, y, page.width - MARGIN, y + HDR_H - 6], fill=HDR_BG)
        draw.text((MARGIN + 10, y + 4), "%s / %s   (%d)" % (cat, sub, len(gr)),
                  font=f_hdr, fill=TXT)
        y += HDR_H
        for i, r in enumerate(gr):
            col = i % COLS
            if i and col == 0:
                y += CELL_H + 6
                rows_used += 1
                if y + CELL_H > page.height - MARGIN:
                    flush(); new_page()
                    draw.rectangle([MARGIN, y, page.width - MARGIN, y + HDR_H - 6], fill=HDR_BG)
                    draw.text((MARGIN + 10, y + 4), "%s / %s (계속)" % (cat, sub),
                              font=f_hdr, fill=TXT)
                    y += HDR_H
            x = MARGIN + col * CELL_W
            draw.rectangle([x, y, x + CELL_W - 4, y + CELL_H - 4], outline=GRID)
            ic = crop_icon(r["png"], r["rect"])
            page.paste(ic, (x + (CELL_W - 4 - ic.width) // 2,
                            y + 6 + (ICON_BOX - ic.height) // 2))
            # 번호는 아이콘 좌상단 뱃지 — 이름 줄을 셀 폭 전체로 쓰기 위해.
            draw.text((x + 6, y + 5), "#%d" % r["no"], font=f_no, fill=(178, 96, 40))
            ty = y + 6 + ICON_BOX + 2
            for ln in wrap(draw, r["name"] or "(이름 미상)", f_name, CELL_W - 14):
                draw.text((x + 7, ty), ln, font=f_name, fill=TXT)
                ty += 17
            draw.text((x + 7, ty + 1),
                      ellipsize(draw, r["id"] or r["frame"], f_id, CELL_W - 14),
                      font=f_id, fill=SUB)
        y += CELL_H + 6
        rows_used += 1
    flush()
    return pages


def write_csv(rows, outdir):
    # utf-8-sig = Excel 이 한글을 바로 연다.
    p = os.path.join(outdir, "items.csv")
    with open(p, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["번호", "id", "이름", "분류", "용도", "설명",
                    "용도코드(내가채움)", "현재상태(참고)", "참조처(참고)", "아이콘(참고)"])
        for r in rows:
            cls = "%s/%s" % (r["cat"], r["sub"]) if r["entry"] else ""
            w.writerow([r["no"], r["id"] or "", r["name"], cls, "", "",
                        "", r["status"], " ".join(r["refs"][:3]),
                        "%s/%s" % (r["dir"], r["frame"])])


def write_groups_csv(groups, outdir):
    """무리 단위 입력용. shard 49종처럼 규칙이 같은 것은 여기 한 줄이면 끝난다.
    개별 예외만 items.csv 에 적으면 되므로 322줄 → 39줄 + 예외로 줄어든다."""
    p = os.path.join(outdir, "groups.csv")
    with open(p, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["분류", "개수", "번호범위", "예시", "그룹 공통 용도", "설명"])
        for (cat, sub), gr in groups:
            w.writerow(["%s/%s" % (cat, sub), len(gr),
                        "#%d~#%d" % (gr[0]["no"], gr[-1]["no"]),
                        ", ".join((r["name"] or r["frame"]) for r in gr[:3]), "", ""])


if __name__ == "__main__":
    main()

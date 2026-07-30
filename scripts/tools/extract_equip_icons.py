#!/usr/bin/env python3
"""장비 아이콘(이벤트 25 · 특수 12 · 편린 6 · 전용 95)을 커뮤니티 위키 PDF 에서 복원한다.

## 왜 이 경로인가 (조회 근거, 2026-07-31)

이 네 계열은 **원작 후기 업데이트분**이라 아이콘 아틀라스가 우리 구판 덤프에 없다:
  · `Item::getAccessoryPath()` 가 번호로 폴더를 가른다 — `>20303` → `item/newaccessory2/`,
    `>20057` → `item/newaccessory/`. `ls DV2/480/item/` → `accessory.img_plist` **하나뿐**
    (127키, 번호 20057 이하 구판만)
  · 편린은 `Item.c` `"raidpiece_acc/"` · `RaidpieceItem::getImageInCave` `"raidpiece_cave/"` 로
    경로를 조립하는데 `find DV2 -ipath "*raidpiece*"` → **0건**
그래서 2026-07-30/31 에 "아이콘 없는 장비는 구현 제외"로 껐다.

그런데 소울젬 복원(`extract_soul_gem_icons.py`)에서 확인했듯 **위키 PDF의 '사진' 열에는
원본 아이콘이 PNG + SMask(알파)로 그대로** 박혀 있다. 장비도 같다:
  · `equipment_0.pdf` p3~p5 이벤트 **25** · p6~p8 특수 **12** · p11 편린 **6**
  · `equipment_1.pdf` 전 페이지 전용 **95**
개수가 `data/equipment.json` 과 정확히 일치하고, 이름까지 1:1 로 대조된다(아래 `--check`).

## 매핑 규칙 (표 행 구조)

위키 표는 [사진 | 이름 | (드래곤) | 효과] 이고 사진 열의 x 가 30~60pt 로 일정하다.
  · 이미지를 **읽기 순서**(페이지 → y → x)로 모으면 그대로 표의 행 순서다
  · 같은 행 = 이미지의 y 범위 안에 세로 중심이 들어오는 텍스트 줄
  · 이름 = 그중 x < 160 인 줄들을 이어 붙인 것(셀 안에서 줄바꿈된다)
`data/equipment.json` 의 각 배열도 같은 PDF 를 같은 순서로 파싱한 것이라(build_equipment.py)
**행 순서로 짝짓고 이름으로 검산**한다 — 이름이 어긋나면 굽지 않고 멈춘다.

## 산출물

`assets/converted/equip_wiki/` 에 형제 장비 아이콘과 같은 규약으로:
  · 캔버스 **95×95**(원본 `item/accessory` 프레임의 `src` 가 전부 95×95), 종횡비 유지 후 가운데
  · **PMA(premultiplied alpha)** — 렌더가 `CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA` 를 건다
  · `_manifest.json` + `.tres`(AtlasTexture) + `_rows.json`(행↔이름 대조표, 검산 기록)

`assets/converted/` 는 gitignore 대상이라 **이 스크립트가 변환 기록이자 재생성 수단**이다.

    python scripts/tools/extract_equip_icons.py --check   # 굽지 않고 이름 대조만
    python scripts/tools/extract_equip_icons.py
"""
from __future__ import annotations

import io
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
WIKI = REPO / "docs" / "ref" / "wiki"
EQJSON = REPO / "data" / "equipment.json"
OUT = REPO / "assets" / "converted" / "equip_wiki"

CANVAS = 95                 # 형제 프레임(item/accessory)의 src 규격
FOOTNOTE = (88, 31)         # 각주 아이콘 — 사진 열에 섞여 있다
COL_X = (30, 60)            # 사진 열의 x0 범위
NAME_X = 160                # 이름 열 오른쪽 경계

# 그룹 → (PDF, 페이지 집합(None=전부), 기대 개수)
GROUPS = {
    "event":     ("equipment_0.pdf", {3, 4, 5}, 25),
    "special":   ("equipment_0.pdf", {6, 7, 8}, 12),
    "piece":     ("equipment_0.pdf", {11}, 6),
    "exclusive": ("equipment_1.pdf", None, 95),
}


def read_rows(pdf: str, pages) -> list[dict]:
    """사진 열 이미지를 읽기 순서로 → [{img, name, page}]."""
    import fitz
    from PIL import Image
    doc = fitz.open(WIKI / pdf)
    out = []
    for pno in range(len(doc)):
        if pages is not None and pno not in pages:
            continue
        page = doc[pno]
        lines = []
        for b in page.get_text("dict")["blocks"]:
            if b["type"] != 0:
                continue
            for l in b["lines"]:
                s = "".join(sp["text"] for sp in l["spans"]).strip()
                if s:
                    lines.append((round(l["bbox"][0], 1),
                                  (l["bbox"][1] + l["bbox"][3]) / 2, s))
        items = []
        for im in page.get_images(full=True):
            xref, smask = im[0], im[1]
            info = doc.extract_image(xref)
            if not smask or (info["width"], info["height"]) == FOOTNOTE:
                continue
            for r in page.get_image_rects(xref):
                if not (COL_X[0] <= r.x0 <= COL_X[1]):
                    continue
                same = sorted([(x, y, s) for x, y, s in lines
                               if r.y0 <= y <= r.y1 and x > r.x1 - 2])
                name = "".join(s for x, y, s in same if x < NAME_X)
                rgb = Image.open(io.BytesIO(info["image"])).convert("RGB")
                a = Image.open(io.BytesIO(doc.extract_image(smask)["image"])).convert("L")
                if a.size != rgb.size:
                    a = a.resize(rgb.size)
                img = rgb.copy()
                img.putalpha(a)
                items.append((r.y0, r.x0, {"img": img, "name": name, "page": pno}))
        items.sort(key=lambda t: (t[0], t[1]))
        out += [it[2] for it in items]
    return out


def norm(s: str) -> str:
    """이름 비교용 정규화 — 각주 표시(`[19]`)·공백·**사유 영역(PUA) 글리프** 제거.

    PDF 텍스트에는 폰트 사설 글리프(U+E000~U+F8FF)가 섞여 들어온다 — 예를 들어
    `data/equipment.json` exclusive[86] 은 `  아카이아의 성 물 아카이아` 다.
    비교에서 조용히 어긋나지 않도록 문자 클래스에 그 범위를 넣어 지운다.
    """
    return re.sub(r"[\[\]\d\s-]", "", s)


def our_names(eq: dict) -> dict[str, list[str]]:
    """equipment.json 에서 그룹별 이름을 **PDF 와 같은 순서로**."""
    special = []
    for fam, v in eq["special"].items():
        for it in v["items"]:
            special.append("%s:%s" % (fam, it["name"]))
    exclusive = []
    for x in eq["exclusive"]["list"]:
        exclusive.append(x.get("name_raw") or x.get("raw", ""))
    return {
        "event": [e["name"] for e in eq["event"]],
        "special": special,
        "piece": [p["name"] for p in eq["pieces"]["list"]],
        "exclusive": exclusive,
    }


def check(rows: dict, names: dict) -> int:
    """행 순서 짝짓기가 맞는지 이름으로 검산. 반환 = 불일치 수."""
    bad = 0
    for g, rs in rows.items():
        want = GROUPS[g][2]
        ours = names[g]
        if len(rs) != want or len(ours) != want:
            print("  ✗ %s: 위키 %d행 / 우리 %d항목 (기대 %d)" % (g, len(rs), len(ours), want))
            bad += abs(len(rs) - want) + abs(len(ours) - want)
            continue
        miss = 0
        for i, r in enumerate(rs):
            w, o = norm(r["name"]), norm(ours[i])
            if g == "special":
                o = o.split(":", 1)[1] if ":" in o else o
            # 위키 이름은 셀 줄바꿈으로 잘릴 수 있어 접두 일치를 본다(양방향).
            if not w or not (o.startswith(w) or w.startswith(o)):
                print("  ✗ %s[%d] 위키=%r 우리=%r" % (g, i, r["name"], ours[i]))
                miss += 1
        print("  %s %d행 · 이름 일치 %d/%d" % (g, len(rs), len(rs) - miss, len(rs)))
        bad += miss
    return bad


def to_pma_canvas(img):
    """종횡비 유지로 95×95 에 맞추고 가운데 정렬 + premultiplied alpha."""
    from PIL import Image
    w, h = img.size
    k = CANVAS / max(w, h)
    img = img.resize((max(1, round(w * k)), max(1, round(h * k))), Image.LANCZOS)
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.paste(img, ((CANVAS - img.size[0]) // 2, (CANVAS - img.size[1]) // 2))
    px = canvas.load()
    for j in range(CANVAS):
        for i in range(CANVAS):
            r, g, b, a = px[i, j]
            f = a / 255.0
            px[i, j] = (int(round(r * f)), int(round(g * f)), int(round(b * f)), a)
    return canvas


TRES = """[gd_resource type="AtlasTexture" load_steps=2 format=3]

[ext_resource type="Texture2D" path="res://assets/converted/equip_wiki/{png}" id="1"]

[resource]
atlas = ExtResource("1")
region = Rect2(0, 0, {n}, {n})
filter_clip = true
"""


def main() -> None:
    try:
        import fitz  # noqa: F401
    except ImportError:
        sys.exit("PyMuPDF 가 필요하다: pip install pymupdf")

    eq = json.loads(EQJSON.read_text(encoding="utf-8"))
    names = our_names(eq)
    rows = {g: read_rows(pdf, pages) for g, (pdf, pages, _n) in GROUPS.items()}

    print("[extract_equip_icons] 행 대조")
    bad = check(rows, names)
    if bad:
        sys.exit("이름 대조 %d건 불일치 — 위키 판이 바뀌었는지 확인하고 굽지 않는다" % bad)
    if "--check" in sys.argv:
        return

    OUT.mkdir(parents=True, exist_ok=True)
    manifest, rowmap = {}, {}
    for g, rs in rows.items():
        rowmap[g] = []
        for i, r in enumerate(rs):
            key = "equip_wiki_%s%02d" % (g, i)
            to_pma_canvas(r["img"]).save(OUT / f"{key}.png")
            (OUT / f"{key}.tres").write_text(TRES.format(png=f"{key}.png", n=CANVAS),
                                             encoding="utf-8")
            manifest[key] = {"rotated": False, "w": CANVAS, "h": CANVAS,
                             "off": [0, 0], "src": [CANVAS, CANVAS]}
            rowmap[g].append({"index": i, "frame": key,
                              "wiki_name": r["name"], "ours": names[g][i], "page": r["page"]})

    (OUT / "_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1),
                                        encoding="utf-8")
    (OUT / "_rows.json").write_text(json.dumps(
        {"_source": "scripts/tools/extract_equip_icons.py — 위키 표 행 순서 ↔ equipment.json",
         "_canvas": CANVAS, "rows": rowmap}, ensure_ascii=False, indent=1), encoding="utf-8")
    print("[extract_equip_icons] wrote %d frames -> %s (%d×%d PMA)"
          % (len(manifest), OUT.relative_to(REPO), CANVAS, CANVAS))
    print("  다음: python scripts/tools/build_item_icons.py && python scripts/tools/build_equipment.py")


if __name__ == "__main__":
    main()

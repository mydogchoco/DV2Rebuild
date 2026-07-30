#!/usr/bin/env python3
"""소울젬 아이콘 40종을 커뮤니티 위키 PDF 에서 복원한다.

## 왜 이 경로인가 (조회 근거, 2026-07-31)

소울젬은 **원작 후기 업데이트**라 우리 구판 덤프에 아이콘이 없다:
  · `asset_index.py --grep soul` → 1건(`music/bg_soul.mp3`)뿐, 프레임 0건
  · `item/gem.img_plist` = **190프레임 = 10종 × 19티어** (일반3 + 혼성6 + 샌즈1). 소울 몫 없음
  · `item/item_small.img_plist` 도 같은 190종
그동안은 같은 축 일반젬 19티어 아이콘을 **빌려 쓰고** 있었다(`SOUL_FALLBACK`) — 가방에서
`공격의 소울젬 +3` 과 `공격의 젬 19티어` 가 같은 그림으로 보였다.

그런데 `docs/ref/wiki/gems.pdf` §3(소울젬)의 '사진' 열에 **원본 아이콘이 그대로** 실려 있다.
93×93 PNG + SMask(알파)로 40장 전량. 같은 PDF §2.2.7(샌즈의 젬) 꼬리 10장을 우리 아틀라스
`gem_white9~18` 과 **같은 인덱스로 대조해 RMSE 10~11**(PDF 재압축 + 93↔95 리샘플 수준)이므로,
이 이미지들이 원본 에셋 그대로임이 교차검증된다 — 흉내가 아니라 원본 복원이다.

선례: `extract_main_bar.py`(레퍼런스 스크린샷에서 하단바를 픽셀로 잘라 통짜 에셋으로 사용,
사용자 확정 2026-07-28)와 같은 부류.

## 하는 일
PDF §3.1~3.4 의 40장을 절 순서(공격→방어→체력→샌즈) × 단계 1~10 으로 뽑아
`assets/converted/gem_soul/` 에 형제 젬과 같은 규격으로 굽는다:
  · 93 → **95×95** 로 맞춘다 (형제 프레임 규격. `Icons.gem_texture` 를 고정 배율로 쓰는
    호출부가 있어 크기가 다르면 소울젬만 2% 작게 그려진다)
  · **PMA(premultiplied alpha)** 로 변환 — 렌더가 `CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA`
    를 걸기 때문(cave.gd `_pma`). 형제 아틀라스도 전부 PMA 다.
  · `_manifest.json` + `.tres`(AtlasTexture) 를 형제 폴더와 같은 형식으로 생성

`assets/converted/` 는 gitignore 대상이라 **이 스크립트가 변환 기록이자 재생성 수단**이다.
아이콘이 생기면 `build_item_icons.py` 가 icon_map `gem` 섹션의 SOUL* 키를 폴백이 아닌
실물로 채운다.

    python scripts/tools/extract_soul_gem_icons.py
    python scripts/tools/extract_soul_gem_icons.py --dry
"""
from __future__ import annotations

import io
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PDF = REPO / "docs" / "ref" / "wiki" / "gems.pdf"
OUT = REPO / "assets" / "converted" / "gem_soul"

SIZE = 95                      # 형제 젬 프레임 규격(item/gem 190장 전부 95×95)
WIKI_SIZE = 93                 # 위키 PDF 안의 원본 크기
STAGES = 10                    # 소울젬은 1~10단계(일반·혼성의 19티어와 다르다)

# 문서 순서 = 절 순서. gems.json 의 code 와 맞춘다.
SECTIONS = [("SOULATT", "att"), ("SOULDEF", "def"), ("SOULHP", "hp"), ("SOULALL", "all")]

# ⚠️ PDF 전체에는 93×93 이 230장 있다(일반·혼성젬 표 전부가 같은 규격) — 앞에서 세면 안 된다.
# **§3.1 이 시작하는 페이지**를 앵커로 잡는다. §3 도입부가 있는 페이지(p18)의 이미지 10장은
# 그 위 §2.2.7(샌즈의 젬) 표의 꼬리라서 포함하면 안 되고, 바로 그 10장이 `gem_white9~18` 과
# 일치하는 것이 위 교차검증의 근거다.
ANCHOR = "3.1."           # 그 페이지 본문에 §3.1 제목이 있다
ANCHOR_WORD = "소울젬"


def find_anchor(doc) -> int:
    """§3.1(공격의 소울젬)이 시작하는 페이지. 목차(0쪽)는 건너뛴다."""
    for pno in range(1, len(doc)):
        t = doc[pno].get_text()
        if ANCHOR in t and ANCHOR_WORD in t:
            return pno
    raise SystemExit("위키 PDF 에서 §3.1(소울젬) 절을 못 찾았다 — 위키 판이 바뀌었는지 확인")


def collect(doc, start: int) -> list:
    """start 쪽부터 93×93 이미지를 **읽기 순서**(페이지 → y → x)로 모아 RGBA 로 돌려준다."""
    from PIL import Image
    out = []
    for pno in range(start, len(doc)):
        page = doc[pno]
        items = []
        for im in page.get_images(full=True):
            xref, smask = im[0], im[1]
            info = doc.extract_image(xref)
            if (info["width"], info["height"]) != (WIKI_SIZE, WIKI_SIZE) or not smask:
                continue
            rects = page.get_image_rects(xref)
            y, x = (rects[0].y0, rects[0].x0) if rects else (0, 0)
            rgb = Image.open(io.BytesIO(info["image"])).convert("RGB")
            a = Image.open(io.BytesIO(doc.extract_image(smask)["image"])).convert("L")
            if a.size != rgb.size:
                a = a.resize(rgb.size)
            img = rgb.copy()
            img.putalpha(a)
            items.append((y, x, img))
        items.sort(key=lambda t: (t[0], t[1]))
        out += [it[2] for it in items]
    return out


def to_pma(img, size: int):
    """straight alpha → premultiplied alpha, 그리고 형제 규격으로 리사이즈."""
    from PIL import Image
    img = img.resize((size, size), Image.LANCZOS)
    px = img.load()
    out = Image.new("RGBA", img.size)
    op = out.load()
    for j in range(size):
        for i in range(size):
            r, g, b, a = px[i, j]
            k = a / 255.0
            op[i, j] = (int(round(r * k)), int(round(g * k)), int(round(b * k)), a)
    return out


TRES = """[gd_resource type="AtlasTexture" load_steps=2 format=3]

[ext_resource type="Texture2D" path="res://assets/converted/gem_soul/{png}" id="1"]

[resource]
atlas = ExtResource("1")
region = Rect2(0, 0, {w}, {h})
filter_clip = true
"""


def main() -> None:
    try:
        import fitz
    except ImportError:
        sys.exit("PyMuPDF 가 필요하다: pip install pymupdf")
    if not PDF.exists():
        sys.exit(f"위키 PDF 가 없다: {PDF}")

    doc = fitz.open(PDF)
    anchor = find_anchor(doc)
    imgs = collect(doc, anchor)
    want = len(SECTIONS) * STAGES
    # 소울젬 절은 문서 끝이라 앵커 이후 93×93 은 정확히 40장이어야 한다. 개수가 다르면
    # 위키 판이 바뀐 것이므로 조용히 어긋난 그림을 굽지 말고 멈춘다.
    if len(imgs) != want:
        sys.exit(f"§3.1({anchor}쪽) 이후 93×93 이 {len(imgs)}장 — {want}장이어야 한다"
                 " (위키 판이 바뀌었는지 확인)")
    soul = imgs

    if "--dry" in sys.argv:
        print(f"[extract_soul_gem_icons] §3.1 앵커 = {anchor}쪽, 이후 93×93 {len(soul)}장 인식")
        for i, (code, short) in enumerate(SECTIONS):
            print(f"  {code}: gem_soul_{short}0 ~ gem_soul_{short}{STAGES - 1}")
        return

    OUT.mkdir(parents=True, exist_ok=True)
    manifest = {}
    for i, img in enumerate(soul):
        code, short = SECTIONS[i // STAGES]
        stage = i % STAGES
        key = f"gem_soul_{short}{stage}"
        to_pma(img, SIZE).save(OUT / f"{key}.png")
        (OUT / f"{key}.tres").write_text(
            TRES.format(png=f"{key}.png", w=SIZE, h=SIZE), encoding="utf-8")
        manifest[key] = {"rotated": False, "w": SIZE, "h": SIZE,
                         "off": [0, 0], "src": [SIZE, SIZE]}

    manifest_path = OUT / "_manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"[extract_soul_gem_icons] wrote {len(manifest)} frames -> "
          f"{OUT.relative_to(REPO)} (95×95 PMA)")
    print("  다음: python scripts/tools/build_item_icons.py   # icon_map 의 SOUL* 를 실물로 교체")


if __name__ == "__main__":
    main()

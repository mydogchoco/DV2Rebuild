"""원작 BMFont 를 Godot 이 **한글까지** 읽을 수 있는 형태로 복사 + **미보유 글리프 보강**.

## 1) `unicode=0` 오진 (2026-07-28 정정)

CLAUDE.md §10 에는 오랫동안 이렇게 적혀 있었다:
  "Godot 4.7 BMFont 임포터 제약 — 임포트 결과 글리프가 96자(ASCII)뿐, has_char(0xB808)=false.
   … 한글은 TTF"
**틀린 진단이었다.** 원인은 임포터가 아니라 원작 `.fnt` 헤더의 `unicode=0` 이다.

    info face="Noto Sans CJK KR" size=19 … charset="" unicode=0 …

BMFont 규약에서 `unicode=0` 은 "char id 가 유니코드가 아니라 **ANSI 코드페이지** 값"이라는 뜻이라,
Godot 임포터가 256 이상 id 를 버리고 ASCII 97자만 남긴다. 실제 파일에는 한글이 다 들어 있다
(`font_subtitle.fnt` `chars count=1271`, `char id=47112` = '레').

⇒ 헤더의 `unicode=0` → `unicode=1` 로 바꿔 복사하면 원작 폰트를 그대로 쓸 수 있다.

## 2) 한글 글리프 보강 (2026-07-30 추가)

원작 비트맵은 **원작 문자열에 쓰인 1271자 부분집합**만 담고 있어 '샛'·'팬' 같은 조합이
빠져 있다(도감 드래곤 이름 깨짐 — 사용자 보고). 시스템 폰트 폴백은 서체가 섞여 보이므로,
**같은 계열 TTF 로 미보유 글리프를 렌더해 비트맵에 페이지를 증설**한다.

- 대상 폰트: font_subtitle(Noto 19) · font_common(HCR Dotum 17) · font_title(Noto 37)
- 대상 글자: KS X 1001 완성형 2,350자 ∪ `data/*.json` 의 모든 한글 음절 − 기존 보유분
  (그 밖의 희귀 조합은 런타임 SystemFont 폴백이 안전망)
- 렌더 파라미터(채움/외곽선/그림자)는 **기존 글리프와의 픽셀 대조(RMSE 그리드 탐색)로 확정**:
  · font_subtitle: NotoSansKR-VF 20px wght400 + 검정(20,20,20) 외곽선 1px + 회색 그림자 (1,1)
  · font_common:   NotoSansKR-VF 17px wght500, 흰 채움만 (원본 = 외곽선 없는 중간 굵기 —
                   HCR Dotum 실물이 시스템에 없어 획 굵기가 가장 근접한 Noto 500 사용)
  · font_title:    아래 CALIB 그리드에서 자동 탐색(수동 확정값 없음)
  근거 이미지: (분석 세션 산출) font_match*.png — 원본과 육안 구분 어려움 확인.

## 산출물

`assets/converted/font_ui/<이름>.fnt` + 페이지 png(+증설분 `<이름>_kr<N>.png`).
원본(`assets/480/font/`)은 건드리지 않는다. 실행 후 Godot 재임포트 필요:

    python scripts/tools/build_fonts.py
    Godot --path . --headless --import
"""
from __future__ import annotations

import itertools
import re
import shutil
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")   # cp949 콘솔 보호

from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parents[2]

# 입력 = 원작 BMFont 9종. `assets/480/font/` 는 원작 덤프 `DV2/480/font/` 의 **복사본**이라
# 둘 중 있는 쪽을 쓴다. 원작 폰트는 저작물이라 공개 레포에 올리지 않으므로(사용자 확정
# 2026-07-30) 갓 클론한 트리에는 복사본이 없다 — 그때는 원작 덤프에서 바로 읽는다.
_SRC_CANDIDATES = [REPO / "assets" / "480" / "font", REPO / "DV2" / "480" / "font"]
SRC = next((p for p in _SRC_CANDIDATES if p.is_dir()), _SRC_CANDIDATES[0])

OUT = REPO / "assets" / "converted" / "font_ui"
DATA = REPO / "data"

NOTO_VF = "C:/Windows/Fonts/NotoSansKR-VF.ttf"

# 원작이 어디에 쓰는지(`GameManager::getFontName_*`) — 고를 때 근거로 쓴다.
USAGE = {
    "font_subtitle": "getFontName_subtitle — 본문/부제(Noto Sans CJK KR 19). 한글 1271자",
    "font_title": "getFontName_title — 제목(Noto Sans CJK KR 37). 한글 619자",
    "font_common": "getFontName_common — 공용 소형(HCR Dotum 17). 한글 1271자",
    "font_combine": "조합 화면(Noto Sans CJK KR 26). 395자",
    "font_opening": "오프닝(Noto Sans CJK KR 26). 105자",
    "font_rating": "등급 표기(KoreanDGHR 22). 14자",
    "font_heal": "전투 힐 수치(Fontdinerdotcom Huggable 56). 숫자 12자",
    "font_normal": "전투 데미지 수치(동 폰트 56). 숫자 11자",
    "font_total": "합계 수치(동 폰트 93). 숫자 12자",
}

# 보강 대상 폰트: 확정 파라미터(fixed) 또는 탐색 그리드(grid).
# 파라미터 = (px크기, VF weight, 외곽선 두께, 그림자 (dx,dy), 그림자 RGBA)
# 2026-07-30 2차 보정(사용자 검수): w400+반투명 그림자는 원본보다 흰 획이 얇고 그림자가 안 보였다
# → subtitle 은 w500 + 불투명 회색(90) 그림자. 기준선도 원본이 1px 위 — 렌더 후 yoffset 델타를
#   기존 글리프 실측(중앙값)으로 자동 보정한다(calibrate_yoffset).
AUGMENT = {
    "font_subtitle": {"fixed": (20, 500, 1, (1, 1), (90, 90, 90, 255))},
    "font_common": {"fixed": (17, 500, 0, (0, 0), None)},
    "font_title": {"grid": {
        "size": [37, 38, 39, 40, 41], "wght": [500, 600],
        "stroke": [1, 2], "shadow": [(1, 1), (2, 2)],
        "shcol": [(90, 90, 90, 255), (110, 110, 110, 255)],
    }},
}
OUTLINE = (20, 20, 20, 255)   # 원본 외곽선 색(글리프 색 실측)
PAGE_W = PAGE_H = 1024
CALIB_SAMPLE = "레드래곤스킬가나마을"   # 파라미터 검증에 쓸 기존 글리프
# 사용자 육안 보정(2026-07-30 3차): 자동 정합 결과가 원작 대비 미세하게 크고 위에 있었다.
USER_SIZE_SCALE = 0.95        # 렌더 px 크기 ×0.95 (5% 축소)
USER_DY = 1                   # 자동 yoffset 보정 뒤 +1px 아래로


def parse_fnt(path: Path):
    txt = path.read_text(encoding="utf-8", errors="replace")
    chars = {}
    for m in re.finditer(
        r"char id=(\d+)\s+x=(\d+)\s+y=(\d+)\s+width=(\d+)\s+height=(\d+)"
        r"\s+xoffset=(-?\d+)\s+yoffset=(-?\d+)\s+xadvance=(-?\d+)", txt):
        v = list(map(int, m.groups()))
        chars[v[0]] = v[1:]
    base = int(re.search(r"\bbase=(\d+)", txt).group(1))
    pages = int(re.search(r"\bpages=(\d+)", txt).group(1))
    return txt, chars, base, pages


def target_charset() -> set[str]:
    """KS X 1001 완성형 2,350자 ∪ data/*.json 의 한글 음절."""
    out = set()
    for cp in range(0xAC00, 0xD7A4):
        ch = chr(cp)
        try:
            ch.encode("euc_kr")
            out.add(ch)
        except UnicodeEncodeError:
            pass
    for p in DATA.glob("*.json"):
        try:
            txt = p.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for ch in txt:
            if 0xAC00 <= ord(ch) <= 0xD7A3:
                out.add(ch)
    return out


def make_font(size: int, wght: int) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(NOTO_VF, size)
    try:
        f.set_variation_by_axes([wght])
    except Exception:
        pass
    return f


def render_glyph(ch: str, font, base: int, stroke: int, shadow, shcol):
    """글리프 1자를 (이미지, xoffset, yoffset, xadvance) 로 렌더.
    오프셋 기준 = BMFont 규약(커서 = 줄 좌상단, base 아래가 베이스라인)."""
    pad = 12
    W = H = 96 if font.size < 50 else 160
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ox, oy = pad, pad + base          # 커서 좌상단 (pad,pad) → 베이스라인 y
    if shadow and (shadow[0] or shadow[1]) and shcol:
        d.text((ox + shadow[0], oy + shadow[1]), ch, font=font, fill=shcol,
               anchor="ls", stroke_width=stroke, stroke_fill=shcol)
    d.text((ox, oy), ch, font=font, fill=(255, 255, 255, 255), anchor="ls",
           stroke_width=stroke, stroke_fill=OUTLINE if stroke else None)
    bb = img.getbbox()
    if bb is None:
        return None
    g = img.crop(bb)
    xoffset = bb[0] - pad
    yoffset = bb[1] - pad
    xadvance = int(round(font.getlength(ch)))
    return g, xoffset, yoffset, xadvance


def rmse(a: Image.Image, b: Image.Image) -> float:
    w, h = max(a.width, b.width), max(a.height, b.height)
    A = Image.new("RGBA", (w, h), (0, 0, 0, 0)); A.paste(a, (0, 0))
    B = Image.new("RGBA", (w, h), (0, 0, 0, 0)); B.paste(b, (0, 0))
    pa, pb = A.tobytes(), B.tobytes()
    return (sum((x - y) ** 2 for x, y in zip(pa, pb)) / len(pa)) ** 0.5


def calibrate(stem: str, atlas: Image.Image, chars: dict, base: int) -> tuple:
    spec = AUGMENT[stem]
    if "fixed" in spec:
        return spec["fixed"]
    g = spec["grid"]
    samples = [ord(c) for c in CALIB_SAMPLE if ord(c) in chars]
    best = None
    for size, wght, stroke, shadow, shcol in itertools.product(
            g["size"], g["wght"], g["stroke"], g["shadow"], g["shcol"]):
        font = make_font(size, wght)
        tot = 0.0
        for cid in samples:
            x, y, w, h, *_ = chars[cid]
            og = atlas.crop((x, y, x + w, y + h))
            r = render_glyph(chr(cid), font, base, stroke, shadow, shcol)
            if r is None:
                tot += 999
                continue
            tot += rmse(og, r[0])
        score = tot / max(1, len(samples))
        if best is None or score < best[0]:
            best = (score, (size, wght, stroke, shadow, shcol))
    print("  calib %-14s → size=%d wght=%d stroke=%d shadow=%s (RMSE %.1f)"
          % (stem, *best[1][:3], str(best[1][3]), best[0]))
    return best[1]


class ShelfPacker:
    """단순 선반 패킹 — 페이지(1024²)를 채우고 넘치면 새 페이지."""
    def __init__(self):
        self.pages: list[Image.Image] = []
        self.x = self.y = self.row_h = 0

    def put(self, g: Image.Image) -> tuple[int, int, int]:
        w, h = g.width + 1, g.height + 1
        if not self.pages or self.y + h > PAGE_H and self.x == 0:
            pass
        if not self.pages:
            self._new_page()
        if self.x + w > PAGE_W:
            self.x = 0
            self.y += self.row_h
            self.row_h = 0
        if self.y + h > PAGE_H:
            self._new_page()
        px, py = self.x, self.y
        self.pages[-1].paste(g, (px, py))
        self.x += w
        self.row_h = max(self.row_h, h)
        return len(self.pages) - 1, px, py

    def _new_page(self):
        self.pages.append(Image.new("RGBA", (PAGE_W, PAGE_H), (0, 0, 0, 0)))
        self.x = self.y = self.row_h = 0


def calibrate_yoffset(font, chars: dict, base: int, stroke, shadow, shcol) -> int:
    """기존 글리프의 yoffset 과 우리 렌더의 yoffset 차이(중앙값) — 기준선 정렬 보정.
    (원작 비트맵이 우리 렌더보다 ~1px 위에 놓여 있다 — 사용자 검수 2026-07-30)"""
    deltas = []
    for ch in CALIB_SAMPLE:
        if ord(ch) not in chars:
            continue
        oyo = chars[ord(ch)][5]
        r = render_glyph(ch, font, base, stroke, shadow, shcol)
        if r is None:
            continue
        deltas.append(oyo - r[2])
    if not deltas:
        return 0
    deltas.sort()
    return deltas[len(deltas) // 2]


def augment(stem: str) -> None:
    fnt_path = SRC / f"{stem}.fnt"
    txt, chars, base, pages = parse_fnt(fnt_path)
    atlas = Image.open(SRC / f"{stem}.png").convert("RGBA")
    missing = sorted(ch for ch in target_charset() if ord(ch) not in chars)
    if not missing:
        print("  %-14s 보강 불필요" % stem)
        return
    size, wght, stroke, shadow, shcol = calibrate(stem, atlas, chars, base)
    size = max(1, round(size * USER_SIZE_SCALE))
    font = make_font(size, wght)
    dy = calibrate_yoffset(font, chars, base, stroke, shadow, shcol) + USER_DY
    print("  %-14s size=%d(×%.2f) yoffset 보정 %+d" % (stem, size, USER_SIZE_SCALE, dy))
    packer = ShelfPacker()
    lines = []
    for ch in missing:
        r = render_glyph(ch, font, base, stroke, shadow, shcol)
        if r is None:
            continue
        g, xo, yo, xa = r
        yo += dy
        page_i, px, py = packer.put(g)
        lines.append(
            "char id=%d   x=%d   y=%d   width=%d   height=%d   xoffset=%d   "
            "yoffset=%d   xadvance=%d   page=%d  chnl=15"
            % (ord(ch), px, py, g.width, g.height, xo, yo, xa, pages + page_i))
    # .fnt 재조립: unicode=1 · pages/chars count 갱신 · 새 page 줄 + char 줄 추가.
    out_txt = txt.replace("unicode=0", "unicode=1")
    total_pages = pages + len(packer.pages)
    out_txt = re.sub(r"\bpages=\d+", "pages=%d" % total_pages, out_txt)
    old_count = int(re.search(r"chars count=(\d+)", out_txt).group(1))
    out_txt = re.sub(r"chars count=\d+",
                     "chars count=%d" % (old_count + len(lines)), out_txt)
    page_lines = "".join('page id=%d file="%s_kr%d.png"\n' % (pages + i, stem, i)
                         for i in range(len(packer.pages)))
    # 마지막 page 줄 뒤에 증설 page 줄 삽입(원본 형식: page → chars count → char들).
    out_txt = re.sub(r'(page id=\d+ file="[^"]+"\r?\n)(chars count)',
                     r"\1" + page_lines.replace("\\", "\\\\") + r"\2",
                     out_txt, count=1)
    if not out_txt.rstrip("\n").endswith(lines[-1] if lines else ""):
        out_txt = out_txt.rstrip("\n") + "\n" + "\n".join(lines) + "\n"
    (OUT / f"{stem}.fnt").write_text(out_txt, encoding="utf-8")
    shutil.copy(SRC / f"{stem}.png", OUT / f"{stem}.png")
    for i, page in enumerate(packer.pages):
        page.save(OUT / ("%s_kr%d.png" % (stem, i)))
    print("  %-14s +%d자 (페이지 +%d)" % (stem, len(lines), len(packer.pages)))


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for fnt in sorted(SRC.glob("*.fnt")):
        if fnt.stem in AUGMENT:
            augment(fnt.stem)
            print("%-16s unicode 1 + 한글 보강  %s" % (fnt.stem, USAGE.get(fnt.stem, "")))
            continue
        txt = fnt.read_text(encoding="utf-8", errors="replace")
        head, rest = txt.split("\n", 1)
        fixed = head.replace("unicode=0", "unicode=1")
        (OUT / fnt.name).write_text(fixed + "\n" + rest, encoding="utf-8")
        png = fnt.with_suffix(".png")
        if png.exists():
            shutil.copy(png, OUT / png.name)
        note = USAGE.get(fnt.stem, "")
        print("%-16s %s%s" % (fnt.stem, "unicode 1 " if fixed != head else "(그대로) ", note))
    print("\n→", OUT)
    print("   Godot 재임포트: Godot --path . --headless --import")


if __name__ == "__main__":
    main()

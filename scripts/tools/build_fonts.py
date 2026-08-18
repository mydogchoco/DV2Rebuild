from __future__ import annotations

import itertools
import re
import shutil
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parents[2]

_SRC_CANDIDATES = [REPO / "assets" / "480" / "font", REPO / "DV2" / "480" / "font"]
SRC = next((p for p in _SRC_CANDIDATES if p.is_dir()), _SRC_CANDIDATES[0])

OUT = REPO / "assets" / "converted" / "font_ui"
DATA = REPO / "data"

NOTO_VF = "C:/Windows/Fonts/NotoSansKR-VF.ttf"

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

AUGMENT = {
    "font_subtitle": {"fixed": (20, 500, 1, (1, 1), (90, 90, 90, 255))},
    "font_common": {"fixed": (17, 500, 0, (0, 0), None)},
    "font_title": {"grid": {
        "size": [37, 38, 39, 40, 41], "wght": [500, 600],
        "stroke": [1, 2], "shadow": [(1, 1), (2, 2)],
        "shcol": [(90, 90, 90, 255), (110, 110, 110, 255)],
    }},
}
OUTLINE = (20, 20, 20, 255)
PAGE_W = PAGE_H = 1024
CALIB_SAMPLE = "레드래곤스킬가나마을"
USER_SIZE_SCALE = 0.95
USER_DY = 1

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
    pad = 12
    W = H = 96 if font.size < 50 else 160
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ox, oy = pad, pad + base
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
    out_txt = txt.replace("unicode=0", "unicode=1")
    total_pages = pages + len(packer.pages)
    out_txt = re.sub(r"\bpages=\d+", "pages=%d" % total_pages, out_txt)
    old_count = int(re.search(r"chars count=(\d+)", out_txt).group(1))
    out_txt = re.sub(r"chars count=\d+",
                     "chars count=%d" % (old_count + len(lines)), out_txt)
    page_lines = "".join('page id=%d file="%s_kr%d.png"\n' % (pages + i, stem, i)
                         for i in range(len(packer.pages)))
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

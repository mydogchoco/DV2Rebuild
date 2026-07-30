"""메인 화면(월드맵) **하단 메뉴바**를 레퍼런스 스크린샷에서 잘라내 에셋으로 만든다.

왜 이 도구가 있나 (CLAUDE.md §10 '메인화면 하단 메뉴바' 행):
  · 구판 하단바의 **배치 코드**는 구 libgame.so 와 함께 유실됐다.
  · 디컴프한 후기판 `WorldMapScene::initUI` 가 부르는 `newCommon/ma_panel_bottom` 등은
    우리 구판 덤프에 **없다**(`asset_index.py --grep ma_panel` → 0건).
  · 그래서 종전 `main_hud.gd` 는 `9patch/ranking_teambox`(돌판) + `common/skill_circle*`
    (스킬 슬롯 링)으로 **형태만 흉내** 냈다 — 사용자가 "투박하다"고 지적한 그 화면이다.
  ⇒ 유일한 메인화면 레퍼런스 `docs/ref/orig_image/old_screenshots/Yutakan_main.png`(후기판, 1751×986)에서
    바 자체를 **픽셀로 추출**해 쓴다. 원본 `ma_*` 프레임이 발견되면 이 도구를 폐기한다.

출력 (assets/converted/mainbar_ui/):
  bottom_bar.png        원본 그대로 — 한글 라벨(미션/길드/경매장/…)이 구워져 있다
  bottom_bar_clean.png  라벨·알림뱃지를 지운 판 — 우리 메뉴 이름을 얹어 쓴다(기본)
  _bar_meta.json        원본 좌표계 정보 + 슬롯 중심 x + 동굴 원버튼 원/반지름

배경(월드맵) 제거 방식 — 세 가지를 조합한다:
  ① **저채도 마스크**  돌바는 S≤0.24, 위쪽 바다·바위는 S≥0.4.
  ② **바닥 연결요소 + 열별 상단 포락선**  파도 거품(저채도)이 바 위에 붙는 것을 잘라낸다.
     거품은 폭이 좁으므로 열별 top 의 이동중앙값보다 위는 버린다.
  ③ **원버튼은 기하로 채운다**  가운데 [동굴] 버튼의 링은 어둡고(v0.15) 일부는 청록(S0.37)
     이라 채도 마스크로 못 잡는다. 실측 원(cx,cy,r)을 그대로 칠한다.
  그 위에 바 위로 겹쳐 있던 던전 이름표('혼돈의 틈새'·'해골요새')는 좌표로 지운다.
"""
from __future__ import annotations
import json
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parents[2]
SRC = REPO / "docs" / "ref" / "orig_image" / "old_screenshots" / "Yutakan_main.png"
OUT = REPO / "assets" / "converted" / "mainbar_ui"

# ── 레퍼런스 실측 상수 (1751×986) ───────────────────────────────────────────
SAT_MAX = 0.24        # 돌바 채도 상한(실측: 돌 0.01~0.18 / 바다 0.4~1.0)
VAL_MIN = 0.10        # 하단 검은 레터박스(v=0.055)만 배제. 어두운 링은 살린다
TOP_CLAMP = 845       # 채도 마스크가 올라갈 수 있는 최상단(중앙 날개 꼭대기 ≈853)
LETTERBOX = 984       # 이 행부터 아래는 검은 레터박스
CAVE = (722, 897, 92)  # 중앙 [동굴] 원버튼 (cx, cy, r) 실측
# 원버튼(파란 구슬)은 TOP_CLAMP 보다 위로 솟는다(윗변 y≈805). 잘라내면 구슬 머리가 날아가므로
# 스트립을 그 위까지 확장한다 — 월드맵을 가려도 된다(사용자 확정 2026-07-28).
CAVE_TOP_PAD = 8      # 구슬 위 여유(외곽선·후광)

# 바 위에 겹쳐 있던 월드맵 던전 이름표 — 실루엣에서 제외한다(원본 좌표).
MASK_OUT = [
    (494, 845, 626, 906),    # 'LV28 혼돈의 틈새'
    (796, 845, 908, 872),    # 'LV22 해골요새'
]
# 지울 한글 라벨 — 각 판 안쪽의 '글자만' 들어 있는 사각형.
LABEL_BOXES = [
    (40, 918, 130, 968),      # 미션
    (196, 918, 290, 968),     # 길드
    (378, 918, 496, 968),     # 경매장
    (947, 918, 1043, 968),    # 상점
    (1110, 918, 1206, 968),   # 육성
    (1284, 918, 1380, 968),   # 던전
    (1452, 918, 1548, 968),   # 대전
    (1614, 918, 1710, 968),   # 기타
]
# 붉은 알림 뱃지(던전 우상단) — 색이 밝아 라벨 지우기(어두운 픽셀)로는 안 지워진다.
PATCH_BOXES = [(1355, 921, 1382, 945)]

# 슬롯 중심 x(원본 좌표) — main_hud 가 우리 라벨을 얹을 자리.
SLOT_CX = [85, 243, 437, 995, 1158, 1332, 1500, 1662]


def hsv_sv(rgb):
    mx = rgb.max(2)
    mn = rgb.min(2)
    return np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0.0), mx


def largest_bottom_component(mask):
    """바닥 행에 닿은 연결요소만 남긴다(4-이웃 BFS, 의존성 추가 없이)."""
    h, w = mask.shape
    out = np.zeros_like(mask)
    stack = []
    for x in range(w):
        if mask[h - 1, x]:
            out[h - 1, x] = True
            stack.append((h - 1, x))
    while stack:
        y, x = stack.pop()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not out[ny, nx]:
                out[ny, nx] = True
                stack.append((ny, nx))
    return out


def fill_holes(mask):
    """바깥에서 도달 못 하는 False 영역 = 구멍 → 메운다."""
    h, w = mask.shape
    free = ~mask
    outside = np.zeros_like(mask)
    stack = []

    def push(y, x):
        if free[y, x] and not outside[y, x]:
            outside[y, x] = True
            stack.append((y, x))

    for x in range(w):
        push(0, x)
        push(h - 1, x)
    for y in range(h):
        push(y, 0)
        push(y, w - 1)
    while stack:
        y, x = stack.pop()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w:
                push(ny, nx)
    return ~outside


def trim_by_envelope(mask, keep_x, deg=6, tol=7.0, iters=5):
    """바 윗변을 매끄러운 곡선으로 강건 적합해 파도 거품 돌기를 잘라낸다.

    바다에 뜬 흰 물거품도 저채도라 마스크에 붙는데, 폭이 250px 넘는 덩어리도 있어
    이동중앙값으로는 못 지운다. 반면 바 윗변은 완만한 아치라 **저차 다항식**으로
    잘 맞는다 ⇒ 잔차가 큰 열(=거품)을 버려 가며 몇 번 재적합한 뒤, 곡선 위쪽을 지운다.
    keep_x 구간(중앙 원버튼·날개)은 경계가 솟는 것이 정상이라 적합·절단에서 모두 뺀다.
    """
    h, w = mask.shape
    top = np.full(w, h, dtype=np.float64)
    for x in range(w):
        col = np.nonzero(mask[:, x])[0]
        if col.size:
            top[x] = float(col.min())
    xs = np.arange(w, dtype=np.float64)
    ok = (top < h) & ((xs < keep_x[0]) | (xs > keep_x[1]))
    for _ in range(iters):
        coef = np.polyfit(xs[ok], top[ok], deg)
        resid = top - np.polyval(coef, xs)
        ok = (top < h) & ((xs < keep_x[0]) | (xs > keep_x[1])) & (np.abs(resid) < tol)
    fit = np.polyval(np.polyfit(xs[ok], top[ok], deg), xs)
    for x in range(w):
        if keep_x[0] <= x <= keep_x[1]:
            continue
        cut = int(fit[x]) - 1
        if cut > top[x]:
            mask[:cut, x] = False
    return mask


def _erase_glyphs(out, x0, y0, x1, y1, anchor=4, thresh=4.0, grow=2):
    """글자 **획만** 지운다 — 판 질감은 그대로 둔다.

    이력(전부 사용자 지적/실측으로 폐기):
      ① 박스를 한 가지 색/선형보간으로 통째로 덮기 → 메운 자리가 매끈한 **네모**로 도드라짐
      ② 양옆 질감을 거울 반복해 채우기 → 여백에 걸린 **이음매 젬이 판 한가운데 복제**됨
      ③ x 방향 이동중앙값으로 배경 추정 → 한글의 **긴 가로획**(ㅡ·ㄷ)이 배경으로 흡수돼 잔상
    ⇒ 지금 방식: 글자띠 **위·아래 바깥**(획이 없는 행)에서 열별 색을 뽑아 **세로 선형보간**으로
       배경을 만든다. 판은 세로로 매끈하고 글자는 띠 안에만 있으므로 이 추정은 획에 오염되지
       않는다. 그런 다음 '배경보다 뚜렷이 어두운' 픽셀만 배경값으로 바꾼다 — 지워지는 건
       획뿐이라 질감·그라데이션·하이라이트가 보존된다.
    """
    h = out.shape[0]
    top = np.median(out[max(0, y0 - anchor):y0, x0:x1].astype(np.float32), axis=0)
    bot = np.median(out[y1:min(h, y1 + anchor), x0:x1].astype(np.float32), axis=0)
    n = y1 - y0
    for i in range(n):
        t = float(i) / max(1.0, float(n - 1))
        bg = top * (1.0 - t) + bot * t              # (폭, 3) 열별 배경 — **판정용**
        row = out[y0 + i, x0:x1].astype(np.float32)
        sel = row.mean(1) < bg.mean(1) - thresh
        for k in range(1, grow + 1):                # 안티에일리어싱 가장자리까지
            sel[k:] |= sel[:-k].copy()
            sel[:-k] |= sel[k:].copy()
        # 채우기는 **같은 행의 좌우 이웃**을 잇는다. 세로보간 배경으로 그대로 덮으면 글자
        # 그림자만큼 밝아져 흰 유령이 남는다(2026-07-28 실측). 획은 가로로 좁아 이웃이 가깝다.
        row[sel] = _bridge(row, sel, bg)[sel]
        out[y0 + i, x0:x1] = np.clip(row, 0, 255).astype(np.uint8)


def _bridge(row, sel, bg):
    """선택된 구간(획)을 같은 행의 **바로 좌우 성한 픽셀** 사이 선형보간으로 잇는다."""
    out = row.copy()
    n = row.shape[0]
    i = 0
    while i < n:
        if not sel[i]:
            i += 1
            continue
        j = i
        while j < n and sel[j]:
            j += 1
        left = row[i - 1] if i > 0 else (row[j] if j < n else bg[i])
        right = row[j] if j < n else left
        span = max(1, j - i + 1)
        for k in range(i, j):
            a = float(k - i + 1) / float(span)
            out[k] = left * (1.0 - a) + right * a
        i = j
    return out


def clean_rgb(rgb8):
    """판 위 한글 라벨 + 붉은 알림 뱃지를 지운다."""
    out = rgb8.copy()
    for box in LABEL_BOXES:
        _erase_glyphs(out, *box)
    # 붉은 알림 뱃지도 판보다 어둡다(평균휘도 ≈107 vs 판 ≈210) → 같은 판정에 걸린다.
    for box in PATCH_BOXES:
        _erase_glyphs(out, *box, grow=3)
    return out


def main():
    im = Image.open(SRC).convert("RGB")
    rgb8 = np.asarray(im)
    h, w, _ = rgb8.shape
    s, v = hsv_sv(rgb8.astype(np.float32) / 255.0)

    # 스트립 상단 = 원버튼 꼭대기(구슬을 온전히 살린다). 채도 마스크는 TOP_CLAMP 아래만 본다.
    y0 = min(TOP_CLAMP, CAVE[1] - CAVE[2] - CAVE_TOP_PAD)
    mask = np.zeros((LETTERBOX - y0, w), dtype=bool)
    band = slice(TOP_CLAMP - y0, LETTERBOX - y0)
    mask[band] = (s[TOP_CLAMP:LETTERBOX] < SAT_MAX) & (v[TOP_CLAMP:LETTERBOX] > VAL_MIN)
    for mx0, my0, mx1, my1 in MASK_OUT:
        mask[max(0, my0 - y0):my1 - y0, mx0:mx1] = False

    mask = largest_bottom_component(mask)
    keep_x = (CAVE[0] - CAVE[2] - 40, CAVE[0] + CAVE[2] + 40)
    mask = trim_by_envelope(mask, keep_x)

    # 원버튼은 기하로 채운다(어두운 링·청록 톱니를 채도 마스크가 못 잡는다).
    yy = np.arange(y0, LETTERBOX)[:, None]
    xx = np.arange(w)[None, :]
    mask |= ((xx - CAVE[0]) ** 2 + (yy - CAVE[1]) ** 2) <= CAVE[2] ** 2
    mask = fill_holes(mask)

    ys, xs = np.nonzero(mask)
    cy0 = y0 + int(ys.min())
    print("bar bbox (원본 좌표): y=%d..%d  x=%d..%d"
          % (cy0, y0 + int(ys.max()) + 1, int(xs.min()), int(xs.max())))

    alpha = np.zeros((h, w), dtype=np.uint8)
    alpha[y0:LETTERBOX][mask] = 255

    OUT.mkdir(parents=True, exist_ok=True)

    def save(name, src):
        arr = np.dstack([src[cy0:LETTERBOX], alpha[cy0:LETTERBOX, :, None]])
        Image.fromarray(arr, "RGBA").save(OUT / name)

    save("bottom_bar.png", rgb8)
    save("bottom_bar_clean.png", clean_rgb(rgb8))

    meta = {
        "_source": "docs/ref/orig_image/old_screenshots/Yutakan_main.png (1751x986, 후기판 유타칸 메인 화면)",
        "_tool": "scripts/tools/extract_main_bar.py",
        "src_size": [w, h],
        "crop": {"x": 0, "y": cy0, "w": w, "h": LETTERBOX - cy0},
        "slot_cx": SLOT_CX,
        "cave_circle": {"cx": CAVE[0], "cy": CAVE[1], "r": CAVE[2]},
        "label_center_y": 943,
        "_note": "좌표는 전부 원본 스크린샷 픽셀. crop 기준 상대좌표 = 원본 − crop.y",
    }
    (OUT / "_bar_meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1), encoding="utf-8")
    print("wrote", OUT)


if __name__ == "__main__":
    main()

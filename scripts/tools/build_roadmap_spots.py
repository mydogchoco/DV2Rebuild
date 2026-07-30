"""원작 로드맵 아트(scene/adventure/road_map)에서 **스팟 좌표를 추출**한다.

원작 `AdventureMapLayer`는 조우 수 N에 따라 `roadmap_spot{N}.png`(450×315 경로 지도) 한 장을
깔고, 그 위 스팟에 `roadmap_x_icon.png`(53×53, 지나간 표시)를 얹는다.
스팟 좌표는 서버 JSON에서 왔고(유실) — 하지만 **아트에 스팟이 그려져 있으므로** 알파 블롭
검출로 좌표를 되찾을 수 있다. 날조가 아니라 원본 아트에서 읽는 것.

출력: data/roadmap_spots.json  { "5": {"w":..,"h":..,"spots":[[x,y],...]}, "6": {...} }
      좌표는 **트림된 텍스처 로컬 픽셀**(우리가 실제로 그리는 스프라이트 기준).

⚠️ 스팟의 **진행 순서**는 아트로 알 수 없다(원작은 서버 데이터). 여기서는 최근접 이웃으로
경로를 훑어 순서를 만든다 — 렌더 측에서 ASSUMPTION으로 표기할 것.

사용: python scripts/tools/build_roadmap_spots.py
"""
from __future__ import annotations
import json
import plistlib
import re
import sys
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parents[2]
PLIST = REPO / "DV2/480/scene/adventure/road_map.img_plist"
SHEET = REPO / "DV2/480/scene/adventure/road_map.png"
OUT = REPO / "data/roadmap_spots.json"

# 우리 스테이지의 조우 수는 5(21개 던전)·6(1개) — 해당 프레임만 신뢰 구간.
COUNTS = [5, 6]
MIN_SIDE = 25      # 스팟 원 최소 크기(점선 조각은 이보다 작다)
MIN_PX = 200


def crop(frames: dict, sheet: Image.Image, name: str) -> Image.Image:
    f = frames[name]
    x, y, w, h = (int(v) for v in re.findall(r"-?\d+", f["frame"]))
    im = sheet.crop((x, y, x + w, y + h))
    return im.rotate(-90, expand=True) if f["rotated"] else im


def blobs(im: Image.Image) -> list[dict]:
    W, H = im.size
    a = im.load()
    seen = [[False] * H for _ in range(W)]
    out = []
    for X in range(W):
        for Y in range(H):
            if seen[X][Y] or a[X, Y][3] < 120:
                continue
            stack = [(X, Y)]
            seen[X][Y] = True
            px = []
            while stack:
                cx, cy = stack.pop()
                px.append((cx, cy))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < W and 0 <= ny < H and not seen[nx][ny] and a[nx, ny][3] >= 120:
                        seen[nx][ny] = True
                        stack.append((nx, ny))
            if len(px) < MIN_PX:
                continue
            xs = [p[0] for p in px]
            ys = [p[1] for p in px]
            bw, bh = max(xs) - min(xs) + 1, max(ys) - min(ys) + 1
            if bw >= MIN_SIDE and bh >= MIN_SIDE:
                out.append({"cx": sum(xs) / len(xs), "cy": sum(ys) / len(ys), "n": len(px)})
    return out


def order_path(spots: list[dict]) -> list[list[float]]:
    """최근접 이웃으로 경로 순서를 만든다(좌상단 시작). ASSUMPTION — 원작 순서는 서버 데이터."""
    rest = spots[:]
    cur = min(rest, key=lambda s: s["cx"] + s["cy"])
    rest.remove(cur)
    path = [cur]
    while rest:
        nxt = min(rest, key=lambda s: (s["cx"] - cur["cx"]) ** 2 + (s["cy"] - cur["cy"]) ** 2)
        rest.remove(nxt)
        path.append(nxt)
        cur = nxt
    return [[round(s["cx"], 1), round(s["cy"], 1)] for s in path]


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    if not PLIST.exists():
        sys.exit(f"[에러] 원본 없음: {PLIST}")
    frames = plistlib.loads(PLIST.read_bytes())["frames"]
    sheet = Image.open(SHEET).convert("RGBA")
    out: dict[str, dict] = {}
    for n in COUNTS:
        key = f"scene/adventure/road_map/roadmap_spot{n}.png"
        im = crop(frames, sheet, key)
        found = blobs(im)
        if len(found) != n:
            print(f"[경고] spot{n}: 블롭 {len(found)}개 검출(기대 {n}) — 건너뜀")
            continue
        out[str(n)] = {"w": im.size[0], "h": im.size[1], "spots": order_path(found)}
        print(f"spot{n}: {im.size} 스팟 {len(found)}개 → {out[str(n)]['spots']}")
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"기록 → {OUT.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

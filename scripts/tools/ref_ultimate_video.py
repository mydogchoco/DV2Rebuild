"""사용자가 준 **원작 각성기 영상**에서 속성별 대조용 프레임을 뽑는다.

## 왜 (2026-08-05)

`init<El>`·`run<El>` 을 기계로 뽑아도 "그래서 화면이 어떻게 보이나"는 눈으로 대조해야 한다.
사용자가 `각성기_불물땅바람빛어둠신성혼돈그림자.mp4`(1280×720 · 30fps · 83.6초)를 줬다 —
9속성이 **제목 순서대로** 한 번씩 들어 있다.

구간 경계는 `UltimateLayer::getDuration()` **탐험판 표**(`UltimateFx.DURATION_ADV`)에 비례해
자른다. 합이 85.15초로 영상 길이(83.57초)와 1.9% 차이라 그 비율로 눌러 맞춘다
(콜로세움판 표는 합이 96.4초라 안 맞는다 ⇒ 이 영상은 **탐험 연출**이다).

## 쓰는 법

    python scripts/tools/ref_ultimate_video.py --sheet out.png          # 속성 첫 프레임 9장
    python scripts/tools/ref_ultimate_video.py --el fire --n 9 --out f.png
    python scripts/tools/ref_ultimate_video.py --el fire --at 3.2 --out f.png   # 그 속성 3.2초
"""
from __future__ import annotations
import argparse, sys
from pathlib import Path

import cv2
import numpy as np

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO = Path(__file__).resolve().parents[2]
VIDEO = REPO / "각성기_불물땅바람빛어둠신성혼돈그림자.mp4"

# 영상 안의 순서 = 파일 이름 순서
ORDER = ["fire", "aqua", "earth", "wind", "light", "dark", "holy", "chaos", "shadow"]
# `UltimateLayer::getDuration()` 탐험판(.rodata DAT_021af2b8)
DUR = {"fire": 9.25, "aqua": 9.75, "earth": 7.85, "wind": 9.4, "light": 10.25,
       "dark": 9.75, "holy": 10.0, "chaos": 9.65, "shadow": 9.25}


def segments(total_s: float) -> dict[str, tuple[float, float]]:
    k = total_s / sum(DUR[e] for e in ORDER)
    out, t = {}, 0.0
    for e in ORDER:
        d = DUR[e] * k
        out[e] = (t, t + d)
        t += d
    return out


def grab(cap, sec: float):
    cap.set(cv2.CAP_PROP_POS_FRAMES, max(0, int(sec * cap.get(cv2.CAP_PROP_FPS))))
    ok, f = cap.read()
    return f if ok else None


def montage(frames: list, cols: int, label: list[str] | None = None):
    frames = [f for f in frames if f is not None]
    if not frames:
        return None
    h, w = frames[0].shape[:2]
    sc = 420.0 / w
    frames = [cv2.resize(f, (int(w * sc), int(h * sc))) for f in frames]
    if label:
        for f, s in zip(frames, label):
            cv2.putText(f, s, (8, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 0), 4)
            cv2.putText(f, s, (8, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 1)
    hh, ww = frames[0].shape[:2]
    rows = (len(frames) + cols - 1) // cols
    sheet = np.zeros((rows * hh, cols * ww, 3), np.uint8)
    for i, f in enumerate(frames):
        r, c = divmod(i, cols)
        sheet[r * hh:(r + 1) * hh, c * ww:(c + 1) * ww] = f
    return sheet


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--el", default=None)
    ap.add_argument("--n", type=int, default=9)
    ap.add_argument("--at", type=float, default=None, help="그 속성 구간 안에서의 초")
    ap.add_argument("--out", default="ref.png")
    ap.add_argument("--sheet", default=None)
    a = ap.parse_args()

    cap = cv2.VideoCapture(str(VIDEO))
    total = cap.get(cv2.CAP_PROP_FRAME_COUNT) / cap.get(cv2.CAP_PROP_FPS)
    seg = segments(total)

    if a.sheet or a.el is None:
        fr, lb = [], []
        for e in ORDER:
            s, t = seg[e]
            fr.append(grab(cap, s + (t - s) * 0.55))
            lb.append("%s %.1f~%.1f" % (e, s, t))
        cv2.imwrite(a.sheet or a.out, montage(fr, 3, lb))
        print("[write]", a.sheet or a.out)
        return

    s, t = seg[a.el]
    if a.at is not None:
        f = grab(cap, s + a.at)
        cv2.imwrite(a.out, f)
        print("[write] %s  (%s +%.2fs → 영상 %.2fs)" % (a.out, a.el, a.at, s + a.at))
        return
    fr, lb = [], []
    for i in range(a.n):
        u = (t - s) * (i + 0.5) / a.n
        fr.append(grab(cap, s + u))
        lb.append("%s +%.2fs" % (a.el, u))
    cv2.imwrite(a.out, montage(fr, 3, lb))
    print("[write] %s  (%s 구간 %.2f~%.2f초)" % (a.out, a.el, s, t))


if __name__ == "__main__":
    main()

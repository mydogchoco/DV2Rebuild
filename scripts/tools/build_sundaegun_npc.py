# -*- coding: utf-8 -*-
"""선대군 NPC 초상 — 사용자 제공 원화를 DV2 `NpcPortrait` 규약으로 굽는다.

원본: `DV2/ORIGINAL/WildSP/normal.png` (968×1625 RGBA, **스트레이트 알파**. 읽기 전용)
산출: `assets/converted/npc_sundaegun/`
  · `npc_sundaegun_body_1.{png,tres}`        — 몸통(3/4 신)
  · `npc_sundaegun_mouth_1_{1,2,3}.{png,tres}` — 말하기 입 프레임(다뭄/반개/전개)
  · `_manifest.json` · `_face.json`(파츠 좌표 사이드카 → `extract_npc_face.py` 가 병합)

선대군은 **원작에 없는 오리지널 캐릭터**(🟦 사용자 확정 2026-08-05)라 원작 아틀라스에 초상이
없다. CLAUDE.md §3 의 "남의 얼굴로 대체하지 않는다"는 그대로 유효하고, 여기서는 사용자가 넣어
둔 **그 캐릭터 전용 원화**를 쓴다 — 대체가 아니라 신규 반입이다(`build_loki800.py` 와 같은
드빌1/외부 에셋 반입 경로).

DV2 규약과 다른 점 셋:
  ① **스트레이트 알파** — DV2 아틀라스는 PMA 이고 `NpcPortrait._sprite` 도 PMA 블렌드다
     (`BLEND_MODE_PREMULT_ALPHA`). 그대로 넣으면 반투명 가장자리가 밝게 뜬다 → `_premul`.
  ② **전신 그림** — 원작 NPC 몸통은 머리~허벅지 중간에서 잘린 3/4 신이다(`npc_raon_body_1`
     263×338 실측). 전신을 그대로 넣으면 같은 화면에서 머리가 혼자 작아 보인다 →
     `CROP_BOTTOM` 에서 자른다.
  ③ **눈·입 파츠가 원화에 없다** — 원작 NPC 는 `eye_<e>_<f>`/`mouth_<e>_<f>` 를 따로
     움직이지만 이 그림은 통짜 1장이다. 입만 여기서 **자작**한다(🟦 사용자 지시 2026-08-06 —
     "입 에셋만 그림체에 맞게 임의로 제작, 말할 때는 웃는 모양"). 방식:
       · 프레임 1(다뭄) = 몸통 최종본에서 입 자리를 **그대로 잘라낸 것** — 몸통과 픽셀 동일이라
         쉬는 자세에서 이음새가 없다.
       · 프레임 2·3(반개/전개) = 원화의 다문 입 라인을 지운 바탕 위에, 원화 라인 색을 쓴
         **입꼬리가 올라간 초승달형 웃는 입**을 8배 슈퍼샘플로 그려 합성.
     눈은 계속 없다(깜빡임 프레임 미제작) — `NpcPortrait` 는 눈 없이도 정상 동작한다.
     좌표는 `_face.json` 사이드카로 남기고 `data/npc_face.json` 에도 직접 병합한다
     (그 파일은 `extract_npc_face.py` 가 통째로 재생성하므로 추출기 쪽에도 병합 훅이 있다).

    python scripts/tools/build_sundaegun_npc.py
"""
from __future__ import annotations
import json, os, sys

from PIL import Image, ImageDraw

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(REPO)

SRC = "DV2/ORIGINAL/WildSP/normal.png"
SUB = "npc_sundaegun"
OUT = os.path.join("assets/converted", SUB)
KEY = "npc_sundaegun_body_1"

# 알파 상자 기준 **세로 비율**로 자르는 위치. 실측: 고글 위 0% · 턱 22% · 반바지 밑단 62% ·
# 무릎 72%. 원작 NPC 몸통의 컷 라인(허벅지 중간)에 맞춰 65% 에서 끊는다.
CROP_BOTTOM = 0.65
# 산출 높이(px). 원작 몸통과 **머리 크기**를 맞추기 위한 값이다 —
#   원본 머리(고글~턱) ≈ 0.22 × 1452 ≈ 320px, `npc_raon_body_1` 머리 ≈ 115px ⇒ 배율 0.36,
#   자른 상자 높이 944 × 0.36 ≈ 340. 라온(338) · 아이다(341) 와 같은 급이 된다.
TARGET_H = 340

# ── 입 프레임 ────────────────────────────────────────────────────────────
# 원화의 다문 입 라인을 알파 상자 기준 좌표계에서 **탐색**한다(하드코딩 좌표가 아니라
# 어두운 픽셀 스캔 — 실측 2026-08-06: bbox x394~406 · y324~328, 코점 (388,302)은 창 밖).
MOUTH_SCAN = (375, 310, 425, 345)        # (x0, y0, x1, y1) 탐색창
MOUTH_DARK = 480                          # r+g+b 이 이 미만이면 라인 픽셀(피부는 ≈760)
# 입 파츠 상자(최종 몸통 px, 입 중심 기준 오프셋). 전개 웃는 입(w11·h7)+여백이 들어가는 크기.
# 위 6px 은 코점(중심에서 -8px)을 안 건드리고, 아래 12px 도 턱 라인(+20px)에 못 미친다.
PATCH_L, PATCH_R, PATCH_T, PATCH_B = 13, 13, 6, 12
# 웃는 입 모양 — 원작 딜리스(`npc_dilis_mouth_1_2/3` 11×10~12px)·포포를 참조한 **반달(D형)**:
#   거의 평평한 윗선(u 작게) + 깊고 둥근 아래 호(v). 🟦 사용자 피드백 2026-08-07 —
#   "초승달이 아니라 반달형으로, 조금 더 크게, 얼굴 구도·각도에 맞게".
#   u/v = 입꼬리 기준 윗/아랫입술 중앙 깊이(px, 최종 몸통 기준). 프레임 2 = 반개, 3 = 전개.
SMILE = {2: {"w": 10.5, "u": 0.8, "v": 5.0},
         3: {"w": 13.5, "u": 1.1, "v": 8.5}}
# 얼굴 각도 반영 — 이 원화는 고개를 기울인 3/4 구도다(정중앙 대칭 입은 어색하다는
# 사용자 피드백). 실측: 눈동자 중심 좌(324,292)·우(452,256) ⇒ 눈선 **-15.7°**(뷰어 왼쪽이
# 낮다), 입 중심(400)이 눈 중점(388)보다 오른쪽 = 얼굴을 뷰어 **왼쪽**으로 살짝 돌림.
# 다문 입 라인 자체는 거의 수평(-1°)으로 그려져 있어 눈선을 다 따르지 않고 6할만 준다.
TILT_DEG = -9.5                           # 반달 전체 회전(음수 = 뷰어 왼쪽 입꼬리가 내려감)
NEAR_BULGE = 0.18                         # 아래 호 비대칭 — 가까운 쪽(뷰어 오른쪽)을 더 볼록하게
LINE_RGB = (40, 30, 62)                   # 원화 입 라인 실측색(어두운 보라) — 윗선/윤곽
FILL_RGB = (201, 114, 122)                # 입 안 — 딜리스 실측 새먼(238,136,119)을 이 원화의
                                          #   수채 채도에 맞춰 로즈모브로 한 단 눌렀다
SS = 8                                    # 슈퍼샘플 배율(그리고 LANCZOS 축소로 AA)


def premultiply(im: Image.Image) -> Image.Image:
    from PIL import ImageChops
    r, g, b, a = im.convert("RGBA").split()
    return Image.merge("RGBA", (ImageChops.multiply(r, a),
                                ImageChops.multiply(g, a),
                                ImageChops.multiply(b, a), a))


def write_tres(path: str, png_res: str, w: int, h: int) -> None:
    with open(path, "w", encoding="utf-8") as f:
        f.write('[gd_resource type="AtlasTexture" load_steps=2 format=3]\n\n')
        f.write('[ext_resource type="Texture2D" path="%s" id="1"]\n\n' % png_res)
        f.write("[resource]\n")
        f.write('atlas = ExtResource("1")\n')
        f.write("region = Rect2(0, 0, %d, %d)\n" % (w, h))
        f.write("filter_clip = true\n")


def find_mouth(im2: Image.Image) -> tuple[float, float]:
    """알파 상자 기준 원화에서 다문 입 라인의 중심(px)을 찾는다."""
    x0, y0, x1, y1 = MOUTH_SCAN
    px = im2.load()
    xs, ys = [], []
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b, a = px[x, y]
            if a > 200 and r + g + b < MOUTH_DARK:
                xs.append(x)
                ys.append(y)
    if not xs:
        sys.exit("입 라인을 못 찾았다 — 원화가 바뀌었으면 MOUTH_SCAN 을 다시 실측할 것")
    return (min(xs) + max(xs)) / 2.0, (min(ys) + max(ys)) / 2.0


def draw_smile(patch: Image.Image, cx: float, cy: float, w: float, u: float, v: float) -> Image.Image:
    """patch(최종 몸통 px) 위에 웃는 반달 입을 그린다. (cx,cy) = 입꼬리 높이의 중심.

    모양 = 입꼬리 (±w/2, cy) 두 점 사이의 **반달(D형)**: 거의 평평한 윗선(깊이 u) +
    둥근 아래 호(깊이 v, `NEAR_BULGE` 만큼 뷰어 오른쪽이 더 볼록) — 딜리스 입 프레임 참조.
    전체를 `TILT_DEG` 회전해 원화의 기울인 얼굴 각도에 맞춘다.
    SS 배로 그려 LANCZOS 축소 — 원화의 부드러운 수채 라인에 맞춘다.
    """
    import math
    th = math.radians(TILT_DEG)
    co, si = math.cos(th), math.sin(th)

    def rot(x: float, y: float) -> tuple[float, float]:
        # (cx,cy) 중심 회전 → SS 좌표
        dx0, dy0 = x - cx, y - cy
        return ((cx + dx0 * co - dy0 * si) * SS, (cy + dx0 * si + dy0 * co) * SS)

    ov = Image.new("RGBA", (patch.width * SS, patch.height * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    pts_top, pts_bot = [], []
    n = 24
    for i in range(n + 1):
        t = i / n * 2.0 - 1.0                 # -1(왼 입꼬리) ~ +1(오른 입꼬리)
        x = cx + t * w * 0.5
        pts_top.append(rot(x, cy + u * (1.0 - t * t)))
        # 아래 호: 포물선 깊이에 (1 + k·t) — 얼굴이 돌아간 반대쪽(가까운 쪽)이 더 둥글다
        pts_bot.append(rot(x, cy + v * (1.0 - t * t) * (1.0 + NEAR_BULGE * t)))
    d.polygon(pts_top + pts_bot[::-1], fill=FILL_RGB + (255,))
    # 윤곽 — 원화의 입 라인처럼 윗선을 또렷하게, 아래 호는 반 톤 얇게.
    d.line(pts_top, fill=LINE_RGB + (255,), width=SS)
    d.line(pts_bot, fill=LINE_RGB + (185,), width=max(1, SS // 2))
    ov = ov.resize(patch.size, Image.LANCZOS)
    out = patch.copy()
    out.alpha_composite(ov)
    return out


def main() -> None:
    if not os.path.exists(SRC):
        sys.exit("원본 없음: %s" % SRC)
    im = Image.open(SRC).convert("RGBA")
    box = im.getbbox()                      # 원본 캔버스의 투명 여백 제거
    if box is None:
        sys.exit("원본이 전부 투명하다: %s" % SRC)
    im2 = im.crop(box)                      # 알파 상자 좌표계(입 탐색 기준)
    mx, my = find_mouth(im2)
    im = im2.crop((0, 0, im2.width, round(im2.height * CROP_BOTTOM)))
    box2 = im.getbbox()                     # 자르고 나면 좌우 여백이 다시 생긴다
    dx = 0
    if box2 is not None:
        dx = box2[0]
        im = im.crop((box2[0], 0, box2[2], im.height))
    w = max(1, round(im.width * TARGET_H / im.height))
    rx, ry = w / im.width, TARGET_H / im.height
    body = im.resize((w, TARGET_H), Image.LANCZOS)   # 스트레이트 알파 최종본(입 프레임 원판)

    # ── 입 프레임 3장 (최종 몸통 px 좌표계) ──
    mcx, mcy = (mx - dx) * rx, my * ry               # 다문 입 라인 중심
    px0, py0 = round(mcx) - PATCH_L, round(mcy) - PATCH_T
    pw, ph = PATCH_L + PATCH_R, PATCH_T + PATCH_B
    f1 = body.crop((px0, py0, px0 + pw, py0 + ph))   # 프레임 1 = 몸통과 픽셀 동일(다뭄)
    # 바탕: 다문 입 라인을 지운다 — 라인 상자(+여백)를 **아래쪽 깨끗한 피부**로 클론 스탬프.
    # (위쪽은 코점이 가까워서 못 쓴다. 피부는 거의 균일한 백색이라 이걸로 충분하다.)
    clean = f1.copy()
    lw, lh = round(7 * rx) + 4, round(5 * ry) + 4    # 원화 라인 13×5px → 최종 ≈5×2 + 여백
    lx, ly = round(mcx) - px0 - lw // 2, round(mcy) - py0 - lh // 2
    stamp = f1.crop((lx, ly + lh + 2, lx + lw, ly + 2 * lh + 2))
    clean.paste(stamp, (lx, ly))
    frames = {1: f1}
    ccx, ccy = mcx - px0, mcy - py0 - 1.0            # 입꼬리 기준선 = 원래 라인보다 1px 위
    for fi, s in SMILE.items():
        frames[fi] = draw_smile(clean, ccx, ccy, s["w"], s["u"], s["v"])

    # ── 저장: 몸통 + 입 3장 + 매니페스트 ──
    os.makedirs(OUT, exist_ok=True)
    man: dict[str, dict] = {}

    def save(key: str, img: Image.Image) -> None:
        premultiply(img).save(os.path.join(OUT, key + ".png"))
        write_tres(os.path.join(OUT, key + ".tres"),
                   "res://assets/converted/%s/%s.png" % (SUB, key), img.width, img.height)
        # `off`/`src` = 트림 없음 — 프레임 간 중심 흔들림(dv2-atlas-trim-offset)이 없다.
        man[key] = {"rotated": False, "w": img.width, "h": img.height,
                    "off": [0, 0], "src": [img.width, img.height]}

    save(KEY, body)
    for fi in sorted(frames):
        save("npc_sundaegun_mouth_1_%d" % fi, frames[fi])
    json.dump(man, open(os.path.join(OUT, "_manifest.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)

    # ── 파츠 좌표 → 사이드카 + data/npc_face.json 병합 ──
    # `npc_face.json` 규약(NpcPortrait._attach_part): 값 = 파츠 **좌상단**의 몸통 좌상단 기준
    # [x, 아래로 내려간 y] **포인트**(= 텍스처 px × 4/3). 표정 키 "?" = 모든 표정 공용.
    S = 4.0 / 3.0
    face = {"sundaegun": {"?": {"mouth": [round(px0 * S, 3), round(py0 * S, 3)]}}}
    json.dump(face, open(os.path.join(OUT, "_face.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    npc_face_path = "data/npc_face.json"
    doc = json.load(open(npc_face_path, encoding="utf-8"))
    doc.setdefault("npc", {}).update(face)
    json.dump(doc, open(npc_face_path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)

    print("[sundaegun] body %d×%d · mouth %d×%d @(%d,%d) · 입중심 최종(%.1f,%.1f) -> %s"
          % (body.width, body.height, pw, ph, px0, py0, mcx, mcy, OUT))
    # ⚠️ 게임은 .godot/imported/ 캐시를 읽는다 — PNG 를 **바꿔도** 재임포트 전엔 옛 그림이
    #   나온다(2026-08-07 실제로 냈던 사고: v2 재빌드 후 창을 띄웠는데 v1 입이 그대로 보였다).
    print("[sundaegun] ⚠️ 재임포트 필수:  godot --headless --path . --import")


if __name__ == "__main__":
    main()

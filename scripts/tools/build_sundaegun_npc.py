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
     움직이지만 이 그림은 통짜 1장이다. 입은 🟦 사용자 확정(2026-08-07)대로 **원작 포포의
     입 프레임 18종(표정 1~6 × 3)을 이식**한다 — 음영 컷·회전·앵커는 아래 상수 블록 참조.
     몸통에서는 원화의 다문 입 라인을 지운다(입 파츠가 항상 얹힌다). 자작 입(초승달→반달
     draw_smile)은 이 확정으로 폐기됐다(이력은 git — 83bc411 까지).
     눈은 계속 없다(깜빡임 프레임 미제작) — `NpcPortrait` 는 눈 없이도 정상 동작한다.
     좌표는 `_face.json` 사이드카로 남기고 `data/npc_face.json` 에도 직접 병합한다
     (그 파일은 `extract_npc_face.py` 가 통째로 재생성하므로 추출기 쪽에도 병합 훅이 있다).

    python scripts/tools/build_sundaegun_npc.py
"""
from __future__ import annotations
import json, os, sys

from PIL import Image

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

# ── 입 프레임 — 원작 **포포** 입 18종(표정 1~6 × 프레임 3) 이식 ──────────────
# 🟦 사용자 확정 2026-08-07: 자작 반달(종전 draw_smile)을 폐기하고 원작 포포의 입 프레임을
# 그대로 이식한다(형제 NPC 에셋 재사용 — 사용자가 참조 NPC 로 포포를 지정·확정).
# 파라미터는 몽타주·테스트 창 반복 검수로 확정(🟦 사용자 확정 2026-08-07):
#   · 위치 = 입 중심 (148.5, 120.5) — 실측 중심(144,119)에서 사용자가 몽타주/실행 화면을
#     보며 픽셀 단위(0.5px 포함)로 보정한 값. 좌표는 npc_face 포인트라 소수도 그대로 실린다.
#   · 각도 = 20° 반시계 — 눈선 실측은 -15.7°(눈동자 중심 좌(324,292)·우(452,256))지만,
#     17px 입에서 1° ≈ 0.15px 라 15~17은 구분이 안 됐고(실측 +14.0~+15.0°로 죽기도 한다)
#     실행 화면 비교로 20 이 얼굴에 맞는다고 확정.
#   · 포포 원본의 입 아래 음영(고정 아랫입술)은 **제거** — 이 원화에 없는 요소
POPO = "assets/converted/npc_popo"
MOUTH_POS = (148.5, 120.5)                # 최종 몸통 px, 입(원본 상자) 중심
TILT = 20.0                               # PIL rotate 양수 = 반시계(뷰어 오른쪽 입꼬리 위)
SS = 8                                    # 슈퍼샘플 배율(회전 후 LANCZOS 축소로 AA)
EMOS = (1, 2, 3, 4, 5, 6)
# 입 아래 음영 시작 행(프레임 로컬 y) — 18프레임 픽셀 맵 전수 실측 2026-08-07.
# 이 행부터 아래를 전부 지운다(열린 입의 연한 아랫변은 보존되는 행으로 잡았다).
CUTS = {(1, 1): 4, (1, 2): 7, (1, 3): 10, (2, 1): 4, (2, 2): 7, (2, 3): 10,
        (3, 1): 4, (3, 2): 8, (3, 3): 12, (4, 1): 4, (4, 2): 7, (4, 3): 12,
        (5, 1): 5, (5, 2): 8, (5, 3): 9, (6, 1): 5, (6, 2): 9, (6, 3): 14}
# 몸통에서 원화의 다문 입 라인을 지운다(클론 스탬프, 최종 몸통 px) — 입 파츠가 항상
# 얹히므로 원작 NPC 몸통처럼 입 없는 몸통이 맞다. 스탬프 소스는 입 **위** 깨끗한 피부
# (입 아래 y123~ 는 마이크 붐 라인이 지나가 오염된다 — 몽타주 v1 실사고).
STAMP_SRC = (136, 105, 154, 111)
STAMP_DST = (136, 114)


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


def unpremultiply(im: Image.Image) -> Image.Image:
    """PMA(변환 산출물) → 스트레이트 알파. 합성·회전은 스트레이트에서 하고 저장 때 되곱한다."""
    im = im.copy()
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = (min(255, r * 255 // a), min(255, g * 255 // a),
                            min(255, b * 255 // a), a)
    return im


def load_popo_frame(key: str, atlas: Image.Image) -> Image.Image:
    """포포 입 프레임 로드(스트레이트 알파). 낱장 PNG 가 없는 프레임은 tres region 으로."""
    import re
    p = os.path.join(POPO, key + ".png")
    if os.path.exists(p):
        return unpremultiply(Image.open(p).convert("RGBA"))
    t = open(os.path.join(POPO, key + ".tres"), encoding="utf-8").read()
    m = re.search(r"region = Rect2\(([\d.]+), ([\d.]+), ([\d.]+), ([\d.]+)\)", t)
    x, y, w, h = (int(float(v)) for v in m.groups())
    return unpremultiply(atlas.crop((x, y, x + w, y + h)))


def prep_mouth(e: int, f: int, pman: dict, atlas: Image.Image) -> Image.Image:
    """포포 프레임 1장 → 선대군용: 음영 컷 → 트림 복원(src 상자 정위치) → TILT° 회전.

    반환 이미지의 **중심**이 입 앵커(MOUTH_POS)다 — 프레임마다 크기가 달라도 원본 상자
    중심을 공유하므로, 매니페스트 `src` 를 공통 상자로 적으면 `NpcPortrait._place` 가
    같은 점에 중심을 맞춘다(off=[0,0] + src 공통 ⇒ 중심 고정).
    """
    key = "npc_popo_mouth_%d_%d" % (e, f)
    info = pman[key]
    im = load_popo_frame(key, atlas)
    px = im.load()
    for y in range(CUTS[(e, f)], im.height):        # 입 아래 음영 제거
        for x in range(im.width):
            px[x, y] = (0, 0, 0, 0)
    w, h, src, off = info["w"], info["h"], info["src"], info["off"]
    box = Image.new("RGBA", (src[0], src[1]), (0, 0, 0, 0))
    box.alpha_composite(im, ((src[0] - w) // 2 + off[0], (src[1] - h) // 2 - off[1]))
    big = box.resize((src[0] * SS, src[1] * SS), Image.LANCZOS)
    big = big.rotate(TILT, resample=Image.BICUBIC, expand=True)
    return big.resize((big.width // SS, big.height // SS), Image.LANCZOS)


def main() -> None:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")   # cp949 콘솔에서 ⚠️ 등이 죽는다
    except Exception:
        pass
    if not os.path.exists(SRC):
        sys.exit("원본 없음: %s" % SRC)
    im = Image.open(SRC).convert("RGBA")
    box = im.getbbox()                      # 원본 캔버스의 투명 여백 제거
    if box is None:
        sys.exit("원본이 전부 투명하다: %s" % SRC)
    im2 = im.crop(box)                      # 알파 상자 좌표계
    im = im2.crop((0, 0, im2.width, round(im2.height * CROP_BOTTOM)))
    box2 = im.getbbox()                     # 자르고 나면 좌우 여백이 다시 생긴다
    if box2 is not None:
        im = im.crop((box2[0], 0, box2[2], im.height))
    w = max(1, round(im.width * TARGET_H / im.height))
    body = im.resize((w, TARGET_H), Image.LANCZOS)   # 스트레이트 알파 최종본
    # 원화의 다문 입 라인 제거 — 입 파츠(포포 이식)가 항상 얹히므로, 원작 NPC 몸통처럼
    # 몸통에는 입이 없어야 한다(안 지우면 다문 입 위에 포포 입이 겹친다).
    body.paste(body.crop(STAMP_SRC), STAMP_DST)

    # ── 입 프레임 18장 — 포포 이식(음영 컷 → 트림 복원 → TILT° 회전) ──
    pman = json.load(open(os.path.join(POPO, "_manifest.json"), encoding="utf-8"))
    atlas = Image.open(os.path.join(POPO, "popo.png")).convert("RGBA")
    frames = {(e, f): prep_mouth(e, f, pman, atlas) for e in EMOS for f in (1, 2, 3)}
    # 공통 원본 상자 = 회전 후 최대 크기. 모든 프레임의 매니페스트 src 를 이걸로 적으면
    # `NpcPortrait._place` 가 프레임 크기와 무관하게 **중심**을 같은 점에 맞춘다.
    bw = max(f.width for f in frames.values())
    bh = max(f.height for f in frames.values())

    # ── 저장: 몸통 + 입 18장 + 매니페스트 ──
    os.makedirs(OUT, exist_ok=True)
    man: dict[str, dict] = {}

    def save(key: str, img: Image.Image, src: list | None = None) -> None:
        premultiply(img).save(os.path.join(OUT, key + ".png"))
        write_tres(os.path.join(OUT, key + ".tres"),
                   "res://assets/converted/%s/%s.png" % (SUB, key), img.width, img.height)
        man[key] = {"rotated": False, "w": img.width, "h": img.height,
                    "off": [0, 0], "src": src or [img.width, img.height]}

    save(KEY, body)
    for (e, f), img in sorted(frames.items()):
        save("npc_sundaegun_mouth_%d_%d" % (e, f), img, [bw, bh])
    json.dump(man, open(os.path.join(OUT, "_manifest.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)

    # ── 파츠 좌표 → 사이드카 + data/npc_face.json 병합 ──
    # `npc_face.json` 규약(NpcPortrait._attach_part): 값 = 파츠 **원본 상자 좌상단**의 몸통
    # 좌상단 기준 [x, 아래로 내려간 y] **포인트**(= 텍스처 px × 4/3). "?" = 모든 표정 공용.
    S = 4.0 / 3.0
    tlx, tly = MOUTH_POS[0] - bw * 0.5, MOUTH_POS[1] - bh * 0.5
    face = {"sundaegun": {"?": {"mouth": [round(tlx * S, 3), round(tly * S, 3)]}}}
    json.dump(face, open(os.path.join(OUT, "_face.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    npc_face_path = "data/npc_face.json"
    doc = json.load(open(npc_face_path, encoding="utf-8"))
    doc.setdefault("npc", {}).update(face)
    json.dump(doc, open(npc_face_path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)

    print("[sundaegun] body %d×%d · mouth %d장(공통상자 %d×%d, 중심 %s) -> %s"
          % (body.width, body.height, len(frames), bw, bh, MOUTH_POS, OUT))
    # ⚠️ 게임은 .godot/imported/ 캐시를 읽는다 — PNG 를 **바꿔도** 재임포트 전엔 옛 그림이
    #   나온다(2026-08-07 실제로 냈던 사고: v2 재빌드 후 창을 띄웠는데 v1 입이 그대로 보였다).
    print("[sundaegun] ⚠️ 재임포트 필수:  godot --headless --path . --import")


if __name__ == "__main__":
    main()

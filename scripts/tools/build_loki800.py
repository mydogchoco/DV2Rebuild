"""로키(도감 800) — 드빌1 에셋을 DV2 규약으로 굽는다.

원본: `DV2/ORIGINAL/Loki/`  (사용자가 넣어 둔 드빌1 추출본. 읽기 전용)
  288.{json,atlas,png}          각성체 스켈레톤
  3607/{child1,child2,adult,transcended,advent}.{json,atlas,png}   성장단계 스켈레톤
  3607/profile.{plist,png}      단계별 아이콘 6장
  3607/effect_adventure.{plist,png}          탐험 이펙트 2프레임
  3607/effect_pvp/col_action{10,20}.{plist,png}   콜로세움 이펙트 12·16프레임

산출:
  assets/converted/dragon_800/{baby,child,adult,aura,e}.json   (build_all.gd 가 씬으로 굽는다)
  assets/converted/portrait_800/                               (도감·가방·파티 초상)
  assets/converted/critical_800/                               (크리티컬 컷인 얼굴)
  assets/converted/dragon_800_fx/                              (탐험·콜로세움 이펙트 프레임)

**왜 전용 빌더가 필요한가** — 세 가지가 DV2 규약과 다르다(측정치·근거는 포팅 카드
`docs/ref/porting/DragonLoki800.md` §3):
  ① 어태치먼트는 `arm1` 인데 아틀라스 리전은 `dragon/3607/adult/arm1` (→ region_basename)
  ② PNG 가 스트레이트 알파다. DV2 는 PMA 이고 우리 씬 빌더도 PMA 블렌드다 (→ premultiply)
  ③ 공격 애니 이름이 `att` 다. 우리 렌더는 `attack` 을 부른다 (→ anim_map)

    python scripts/tools/build_loki800.py           # 전부
    python scripts/tools/build_loki800.py --spine   # 스파인만 (--portrait/--cutin/--fx)
"""
from __future__ import annotations
import json, os, plistlib, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spine_export  # noqa: E402
import cocos_export  # noqa: E402
import atlas as atlaslib  # noqa: E402

from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# ⚠️ **레포 루트로 이동한 뒤 상대경로만 쓴다.** `spine_export.export` 는 outdir 을 그대로
#    `res://` 경로에 이어 붙이므로(`png_res[...] = f"res://{outdir}/..."`) 절대경로를 넘기면
#    `res://C:/Users/.../assets/converted/...` 라는 **깨진 경로**가 씬에 박힌다. 실제로 한 번
#    이렇게 나서 스파인 씬이 텍스처 없이(ext_resource 0개) 빌드돼 화면에 아무것도 안 그려졌다.
os.chdir(REPO)
SRC = "DV2/ORIGINAL/Loki"
OUT = "assets/converted"
DID = 800

# ── 스파인: (원본 파일 스템, 원본 폴더, 우리 단계키) ──────────────────────────
#
# `transcended` → **`aura`** 는 우리 신규 단계키다. 원작 DV2 는 오라성체가 성체와 같은 그림이라
# 단계키가 없다(`growth.gd` 주석). 로키는 드빌1에 전용 아트가 있어 쓴다 — 🟦 사용자 확정
# 2026-08-04. 다른 372종은 `dragons.json` 의 `aura_art` 플래그가 꺼져 있어 영향받지 않는다.
#
# 4번째 열 = **씬 루트 배율**(`spine_export.export(root_scale=)`). 성장 단계(`3607/`)는 DV2
# 드래곤과 저작 단위가 비슷해 1.0 이지만, **각성체 `288` 만 다른 축에서 저작돼 과도하게 크다** —
# 포팅 카드 §1 실측 스켈레톤 w×h 가 `288` **859×798** 대 `adult` 247×289 · `transcended`
# 362×390 으로 3배 넘게 벌어진다. 🟦 사용자 확정 2026-08-05: **원본의 42%** 로 줄인다
# (35% → 38.5% → 42% 로 게임 창에서 눈으로 보며 확정. → 약 361×335 로 성체·오라성체 사이).
SPINES = [
    ("child1",      "3607", "baby",   1.0),
    ("child2",      "3607", "child",  1.0),
    ("adult",       "3607", "adult",  1.0),
    ("transcended", "3607", "aura",   1.0),
    ("288",         "",     "e",      0.42),
    ("advent",      "3607", "advent", 1.0),
]
# `advent`(강림) 은 사용자 최초 매핑(알·해치·해츨링·성체·오라성체·각성)에 없었지만
# `계획 및 아이디어.txt:2` 가 "로키·크툴루는 듭1 에셋에서 **레이드용 일러**를 사용하자" 라고
# 적어 둔 그 그림이다. 우리 레이드 화면이 아직 없어 **읽는 곳은 없고**, 단계키 `advent` 로
# 구워만 둔다(도감·성장 어디에도 안 걸린다 — `Growth.stage_for_level` 은 이 키를 모른다).

ANIM_MAP = {"att": "attack"}

# ── 초상: 드빌1 profile 번호 → DV2 프레임 이름 ────────────────────────────────
#
# 번호 정체는 그림으로 확인했다(6장을 나란히 뽑아 대조): 1=알 2=해치 3=해츨링 4=성체
# 7=오라성체 8=각성. 5·6 은 원본 아틀라스에 없다.
PROFILE_MAP = {
    "1": "egg",
    "2": "box_baby",
    "3": "box_child",
    "4": "box_adult",
    "7": "box_aura",        # 신규 — 도감 5번째 칸(오라성체)이 쓴다
    "8": "box_evolution",
}
# DV2 는 알을 큰 것/작은 것 두 벌로 갖는다(`portrait_1`: egg 캔버스 111² · egg_small 67²).
# 원본엔 한 벌뿐이라 같은 비율로 줄여 만든다.
EGG_SMALL_RATIO = 67.0 / 111.0


def _pair(s):
    return [int(x) for x in re.findall(r"-?\d+", s)]


def _premul(im: Image.Image) -> Image.Image:
    from PIL import ImageChops
    r, g, b, a = im.convert("RGBA").split()
    return Image.merge("RGBA", (ImageChops.multiply(r, a),
                                ImageChops.multiply(g, a),
                                ImageChops.multiply(b, a), a))


def _write_tres(path: str, png_res: str, w: int, h: int) -> None:
    with open(path, "w", encoding="utf-8") as f:
        f.write('[gd_resource type="AtlasTexture" load_steps=2 format=3]\n\n')
        f.write('[ext_resource type="Texture2D" path="%s" id="1"]\n\n' % png_res)
        f.write("[resource]\n")
        f.write('atlas = ExtResource("1")\n')
        f.write("region = Rect2(0, 0, %d, %d)\n" % (w, h))
        f.write("filter_clip = true\n")


def _emit_frame(outdir: str, sub: str, name: str, img: Image.Image, manifest: dict,
                off=None, src=None) -> None:
    """프레임 1장을 낱장 PNG + .tres 로 굽고 매니페스트에 등록.

    낱장으로 떼는 이유 = 원본 프레임에 회전·트림이 섞여 있어 아틀라스 리전으로 남기면 소비자가
    보정해야 한다. 우리 규약은 "변환 단계가 회전을 흡수한다"(`fix_rotated_frames.py` 주석)이다.

    off/src 는 **원본 캔버스 기준 트림 정보**다(cocos, y-up). 이펙트 시퀀스처럼 프레임마다
    크기가 다른 것은 이 값이 없으면 재생 중 중심이 흔들린다(`dv2-atlas-trim-offset` 사고).
    안 주면 "트림 없음"으로 적는다.
    """
    img.save(os.path.join(outdir, name + ".png"))
    _write_tres(os.path.join(outdir, name + ".tres"),
                "res://assets/converted/%s/%s.png" % (sub, name), img.width, img.height)
    manifest[name] = {"rotated": False, "w": img.width, "h": img.height,
                      "off": off or [0, 0], "src": src or [img.width, img.height]}


def cut_plist_frame(page: Image.Image, fr: dict) -> Image.Image:
    """cocos plist 프레임 1장을 세워서 잘라낸다(회전 흡수)."""
    x, y, w, h = _pair(fr.get("frame") or fr["textureRect"])
    rot = bool(fr.get("rotated") or fr.get("textureRotated"))
    box = (x, y, x + (h if rot else w), y + (w if rot else h))
    c = page.crop(box)
    if rot:
        c = c.transpose(Image.ROTATE_90)
    return c


# ═══════════════════════════════════════════════════════════════════════════════
def build_spines() -> None:
    outdir = os.path.join(OUT, "dragon_%d" % DID)
    for stem, folder, stage, rscale in SPINES:
        base = os.path.join(SRC, folder, stem) if folder else os.path.join(SRC, stem)
        sj, at = base + ".json", base + ".atlas"
        if not (os.path.exists(sj) and os.path.exists(at)):
            print("  [skip] 원본 없음:", sj)
            continue
        print("[spine] %s -> %s (x%.2f)" % (stem, stage, rscale))
        spine_export.export(DID, stage, "all", sj_path=sj, atlas_paths=[at], outdir=outdir,
                            region_basename=True, premultiply=True, anim_map=ANIM_MAP,
                            root_scale=rscale)


def build_portrait() -> None:
    sub = "portrait_%d" % DID
    outdir = os.path.join(OUT, sub)
    os.makedirs(outdir, exist_ok=True)
    pl = plistlib.load(open(os.path.join(SRC, "3607/profile.plist"), "rb"))
    page = _premul(Image.open(os.path.join(SRC, "3607/profile.png")))
    manifest, egg = {}, None
    for key, fr in pl["frames"].items():
        num = key.rsplit("/", 1)[-1]
        dv2 = PROFILE_MAP.get(num)
        if dv2 is None:
            print("  [skip] 매핑 없는 profile 번호:", num)
            continue
        img = cut_plist_frame(page, fr)
        name = "dragon_dragon_%d_%s" % (DID, dv2)
        _emit_frame(outdir, sub, name, img, manifest)
        if dv2 == "egg":
            egg = img
    if egg is not None:
        small = egg.resize((max(1, round(egg.width * EGG_SMALL_RATIO)),
                            max(1, round(egg.height * EGG_SMALL_RATIO))), Image.LANCZOS)
        _emit_frame(outdir, sub, "dragon_dragon_%d_egg_small" % DID, small, manifest)
    json.dump(manifest, open(os.path.join(outdir, "_manifest.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print("[portrait] %d 프레임 -> %s" % (len(manifest), sub))


# 크리티컬 컷인 — (att 컷 이름, 얼굴 상자 x0,y0,x1,y1, 산출 키 접미사)
#
# 원본 att 컷에서 **얼굴이 있는 상자**를 눈으로 찍은 값이다(격자를 얹어 확인).
# 로키의 통짜 컷은 288 에만 있으므로 각성 전/후 모두 여기서 뽑되 **서로 다른 컷**을 써서
# 두 상태가 같은 그림이 되지 않게 한다(각성 전=att3 · 각성 후=att1).
# 상자는 **원작 컷인의 화각**에 맞춘 값이다 — `critical_1` 실측 444×112(≈4:1)로, 얼굴이 띠
# 높이를 꽉 채우는 극단적 클로즈업이다. 그래서 머리 높이만큼만 세로로 자르고 가로로 길게 뺀다.
CUTIN = [
    ("att1", (240, 195, 750, 350), "e_cut_in"),   # 각성체 — 옆얼굴
    ("att3", (170, 150, 680, 320), "cut_in"),     # 각성 전 — 정면 포효
]
## 원작 컷인 프레임 높이 — `critical_*` 전수가 **112**다(폭만 444~576 으로 트림 차이).
## `cutin.gd::show` 가 `vis.x/576` 로 배율을 잡으므로 높이를 맞춰야 다른 종과 크기가 같다.
CUTIN_H = 112


def build_cutin() -> None:
    """크리티컬 컷인 얼굴. `cutin.gd::show` ③ 이 `critical_<id>/dragon_dragon_<id>_critical_cut_in`
    (각성 시 `..._critical_e_cut_in`)을 찾으므로 **그 키 이름만 맞추면 코드 변경이 없다.**

    원작 컷인은 얼굴 클로즈업 띠다(`docs/ref/porting/MakeInterface_critical.md`). 로키는 전용
    컷인 그림이 없어 🟦 사용자 확정(2026-08-04)대로 **att 컷에서 얼굴을 잘라 쓴다.**
    성체·오라성체에는 통짜 컷이 없어(파츠 애니뿐) 각성 전 컷인도 288 의 다른 컷에서 뽑는다 —
    같은 드래곤의 원본 그림이므로 자작이 아니고, 원작의 기본 폴백(`dragon_1` 얼굴, Cutin.c:699)
    보다 훨씬 낫다.
    """
    sub = "critical_%d" % DID
    outdir = os.path.join(OUT, sub)
    os.makedirs(outdir, exist_ok=True)
    manifest = {}
    a = atlaslib.parse_spine_atlas(os.path.join(SRC, "288.atlas"))
    page = _premul(Image.open(os.path.join(SRC, "288.png")))
    for att, box, suffix in CUTIN:
        r = a["regions"]["monster/288/" + att]
        x, y = r["xy"]; w, h = r["size"]
        cut = page.crop((x, y, x + w, y + h)).crop(box)
        scale = CUTIN_H / float(cut.height)
        cut = cut.resize((max(1, round(cut.width * scale)), CUTIN_H), Image.LANCZOS)
        _emit_frame(outdir, sub, "dragon_dragon_%d_critical_%s" % (DID, suffix), cut, manifest)
    json.dump(manifest, open(os.path.join(outdir, "_manifest.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print("[cutin] %d 프레임 -> %s" % (len(manifest), sub))


# 이펙트 아틀라스: (plist 상대경로, 페이지 png 상대경로, 우리 키 접두사)
#
# ⚠️ `cocos_export` 를 쓰지 않는다 — 두 가지가 걸린다.
#   ① `effect_adventure.plist` 의 metadata 는 페이지를 `effect.pvr.ccz` 라고 적는데 실제 파일은
#      `effect_adventure.png` 다(드빌1 빌드 시점의 이름). 형제 `.png` 규약이 안 통한다.
#   ② 키가 원본 그대로면 `dragon_3607_effect_col_action1_00` 처럼 **드빌1 종족번호**가 박힌다.
#      우리 규약은 우리 도감 id 다.
FX_SETS = [
    ("3607/effect_adventure.plist",          "3607/effect_adventure.png",          "adv"),
    ("3607/effect_pvp/col_action10.plist",   "3607/effect_pvp/col_action10.png",   "col"),
    ("3607/effect_pvp/col_action20.plist",   "3607/effect_pvp/col_action20.png",   "col"),
]


def build_fx() -> None:
    """탐험·콜로세움 이펙트 프레임. 셋을 한 폴더에 모은다.
    `off`/`src`(원본 캔버스 — col_action 은 800×480)를 그대로 실어야 재생 중 중심이 안 흔들린다."""
    sub = "dragon_%d_fx" % DID
    outdir = os.path.join(OUT, sub)
    os.makedirs(outdir, exist_ok=True)
    manifest = {}
    for plist_rel, png_rel, _tag in FX_SETS:
        pl = plistlib.load(open(os.path.join(SRC, plist_rel), "rb"))
        page = _premul(Image.open(os.path.join(SRC, png_rel)))
        for key, fr in sorted(pl["frames"].items()):
            # "dragon/3607/effect/col_action1/07" -> "dragon_800_col_action1_07"
            tail = key.split("/effect/", 1)[-1].replace("/", "_")
            name = "dragon_%d_%s" % (DID, tail)
            _emit_frame(outdir, sub, name, cut_plist_frame(page, fr), manifest,
                        # ⚠️ 이 plist 는 `spriteOffset`/`spriteSourceSize` 표기다(`offset`/
                        #    `sourceSize` 가 아니라). 키를 틀리면 전부 0 이 되어 조용히 어긋난다.
                        off=_pair(fr.get("spriteOffset") or fr.get("offset") or "{0,0}"),
                        src=_pair(fr.get("spriteSourceSize") or fr["sourceSize"]))
    json.dump(manifest, open(os.path.join(outdir, "_manifest.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print("[fx] %d 프레임 -> %s" % (len(manifest), sub))


def main() -> None:
    args = sys.argv[1:]
    todo = [a.lstrip("-") for a in args if a.startswith("--")] or \
        ["spine", "portrait", "cutin", "fx"]
    if "spine" in todo:
        build_spines()
    if "portrait" in todo:
        build_portrait()
    if "cutin" in todo:
        build_cutin()
    if "fx" in todo:
        build_fx()


if __name__ == "__main__":
    main()

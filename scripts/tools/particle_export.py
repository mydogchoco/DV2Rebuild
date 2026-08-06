# -*- coding: utf-8 -*-
"""
particle_export.py — Cocos2d 파티클 plist(gravity 모드) → Godot CPUParticles2D 파라미터 JSON.

원작 연출 자산(DV2/particle/scene/adventure/pt_*.plist)을 Godot 좌표계(y-down)로 변환해
assets/converted/particles/<name>.json 으로 저장. 런타임 빌더=battle.gd _levelup_particle.

## 텍스처 (2026-08-06 — 종전엔 절차생성 점으로 **전량 대체**하고 있었다)

종전 주석은 "대상이 부드러운 원형 점이라 런타임 절차생성 텍스처로 대체(견고)"였는데,
`textureFileName` 을 전수로 찍어 보니 **원형 점이 아닌 것이 5종**이었다 —
`effect_damaged.png`(콜로세움 피격 = **오각별**) · `skill_29.png` · `skill_31.png` ·
`batttttt.png` · `fire.png`. 노란 별이 노란 동그라미로 나오고 있었다(§3 위반).
⇒ 이제 **원본 텍스처를 그대로 굽는다**: 형제 PNG 가 있으면 그걸, 없으면 plist 에 박힌
`<textureImageData>`(gzip PNG)를 풀어 `<name>.png` 로 낸다. 절차생성 점은
`cocos_particle.gd` 에서 **텍스처가 없을 때의 폴백**으로만 남는다.

⚠️ 크기 기준도 텍스처를 따라간다 — 종전 `BASE = 32.0`(절차생성 점의 px)에 plist 의
`startParticleSize` 를 나눴다. 실제 텍스처는 50×50 등이라 그 상수를 쓰면 배율이 어긋난다.

좌표 변환: Cocos(y-up) → Godot(y-down): 방향/중력 y 부호 반전.
블렌드 770/1 = GL_SRC_ALPHA/GL_ONE = 가산(additive).
"""
import base64, io, json, math, os, plistlib, struct, zlib

DST = "assets/converted/particles"
# (plist 상대경로, 출력 이름). 경로는 DV2/particle/ 기준.
# ⚠️ 예전엔 SRC 를 scene/adventure 로 고정해서 다른 씬의 파티클을 아예 변환할 수 없었다.
SOURCES = [
    ("scene/adventure/pt_levelup_light", "pt_levelup_light"),
    ("scene/adventure/pt_3max1", "pt_3max1"),
    ("scene/adventure/pt_3max2", "pt_3max2"),
    # 몬스터 조우 연출 — 원작 AdventureScene::incomeMonster 가 화면 상단에 뿌린다.
    ("scene/adventure/pt_monster_income_1", "pt_monster_income_1"),
    # 점술집 수정구 — 원작 MagicShopScene::initWidget 이 수정구 중앙에 붙인다.
    ("scene/fortunetent/crystalball", "crystalball"),
    # 레벨업 연출(원작 ExpLayer/FeatherLayer) — 깃털 버스트 금가루 · 진화 상승 · 스킬 슬롯 개방.
    ("scenario/pt_feature_c", "pt_feature_c"),
    ("scene/common/pt_rev_up", "pt_rev_up"),
    ("scene/common/pt_take_skill", "pt_take_skill"),
    # 연구소 B1 결정 생산 — 원작 CrystalLayer::initGenerateBtn 이 작동 중 슬롯에 뿌린다.
    ("scene/laboratory/generate_effect", "generate_effect"),
    # 젬/스킬 슬롯 재추첨 — 원작 ResetLayer::randomGemEffect 가 굴러가는 칸마다 tag 0x7b+i 로 붙인다.
    ("scene/common/reset_slot", "reset_slot"),
    # 혼돈의 틈새 — 원작 AdventureScene::init(:20929)이 다크닉스 모드일 때만 화면 하단에
    # z=999999/tag=0x9c 로 붙이는 화염. 문자열 <AdventureField_8> "작열하는 화염 속에서".
    ("scene/adventure/pt_monster_fire_back", "pt_monster_fire_back"),
    # 흡혈 임팩트 — 원작 AdventureScene::setVampImpact @00ca52e4 가 피격 지점에 scale 0.8 로
    # 붙인다(그 함수의 나머지 절반인 `common/backlight1.png` 은 추출 아틀라스에 없다 — §10 표).
    ("scene/adventure/pt_skill_14_vamp", "pt_skill_14_vamp"),
    # 전투 스킬 파티클 — 원작 AdventureScene::makeSkillParticle @00c9e4a4 가 부르는 3종.
    #   pt_shild             → battle.gd::_shield_impact (원작 setCheckShildImpact 와 같은 순간)
    #   pt_monster_dead_2_2  → battle.gd::_kill (격파)
    #   effect_fire2         → ⚠️ **아직 배선 안 함**. makeSkillParticle 의 호출자를 디컴프 400클래스에서
    #     못 찾아(함수 포인터로 불리는 듯) 발동 조건을 특정하지 못했다. 조건을 지어내지 않고
    #     변환본만 둔다 — 조건이 밝혀지면 그때 연결한다(docs/reimplementation_gaps.md §B).
    ("scene/adventure/pt_shild", "pt_shild"),
    ("scene/adventure/effect_fire2", "effect_fire2"),
    ("scene/adventure/pt_monster_dead_2_2", "pt_monster_dead_2_2"),
    # 회복 물약 사용 — 원작 InterFace::setRecoverItemHeal @00d3eb88 이 카드 중앙에 붙이고
    # music/effect_skill_29.mp3 를 같이 낸다. 레퍼런스 docs/ref/adventure/전투4.png 의 카드 위 버튼.
    ("scene/adventure/skill_29", "skill_29"),
    # 축복 둥지(황금 월계관) 먼지 — 원작 CaveScene::setDragonInfo 알 분기가
    # `getNestLevel()==1` 일 때만 둥지 중심에 붙인다(CaveScene.c:23392).
    ("scene/cave/dust", "cave_dust"),
    # 콜로세움 전투 — 원작 MakeInterface 가 부르는 두 종(리터럴 확인).
    #   damagedEffect @0108f4cc → 피격 대상 레이어에 z=6
    #   deadEffect    @0109a654 → 격파 대상 중앙 (같이 music/effect_dead.mp3 볼륨 0.5)
    ("scene/colosseum/effect_damaged", "colosseum_damaged"),
    ("scene/colosseum/effect_dead", "colosseum_dead"),
    # 스킬 파티클 — 원작 castSkill 의 `particle/skill/skill_%d.plist` 와
    # particleEffect @010908d8 의 `skill_%d_effect.plist`. DV2/particle/skill 에 있는 전량.
    ("skill/skill_14", "skill_14"),
    ("skill/skill_31", "skill_31"),
    ("skill/skill_13_effect", "skill_13_effect"),
    ("skill/skill_14_effect", "skill_14_effect"),
]
# 초월맥스 가산은 연출측(battle.gd)에서 처리; 여기선 순수 파티클 파라미터만.


def F(d, k, default=0.0):
    v = d.get(k, default)
    try:
        return float(v)
    except (TypeError, ValueError):
        return default


def texture_png(d, rel):
    """이 plist 가 쓰는 텍스처의 **PNG 바이트**. 형제 파일 우선(엔진도 그걸 먼저 연다).

    ⚠️ 임베드본(`<textureImageData>`)은 base64 문자열 → zlib → **TIFF**(`MM\\0*`) 다.
       PNG 인 줄 알고 그대로 쓰면 Godot 이 못 읽는다 — TIFF 면 PNG 로 다시 굽는다.
    """
    src = os.path.join("DV2/particle", os.path.dirname(rel), str(d.get("textureFileName", "")))
    if os.path.isfile(src):
        return open(src, "rb").read()
    raw = d.get("textureImageData")
    if not raw:
        return None
    if isinstance(raw, str):
        raw = base64.b64decode(raw)
    try:
        blob = zlib.decompress(bytes(raw), 47)      # 47 = gzip/zlib 헤더 자동 판별
    except zlib.error:
        blob = bytes(raw)
    if blob[:8] == b"\x89PNG\r\n\x1a\n":
        return blob
    from PIL import Image                            # TIFF 변환에만 필요
    buf = io.BytesIO()
    Image.open(io.BytesIO(blob)).convert("RGBA").save(buf, "PNG")
    return buf.getvalue()


def png_size(blob):
    """PNG IHDR 만 읽어 (w, h). PIL 의존 없이."""
    if not blob or blob[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    w, h = struct.unpack(">II", blob[16:24])
    return (w, h)


def convert(rel):
    d = plistlib.load(open(os.path.join("DV2/particle", rel + ".plist"), "rb"))
    angle = F(d, "angle")
    ang_var = F(d, "angleVariance")
    # Godot 방향 = (cos θ, -sin θ) (y 반전). spread=angleVariance(도).
    rad = math.radians(angle)
    direction = [math.cos(rad), -math.sin(rad)]
    speed = F(d, "speed"); speed_var = F(d, "speedVariance")
    life = F(d, "particleLifespan"); life_var = F(d, "particleLifespanVariance")
    life_max = life + life_var
    start_size = F(d, "startParticleSize"); start_size_var = F(d, "startParticleSizeVariance")
    finish_size = F(d, "finishParticleSize", -1)
    # 배율 기준 = **실제 텍스처 폭**. 텍스처를 못 구하면 절차생성 점(32px)으로 돌아간다.
    png = texture_png(d, rel)
    wh = png_size(png)
    BASE = float(wh[0]) if wh else 32.0
    scale_min = max(0.05, (start_size - start_size_var) / BASE)
    scale_max = max(scale_min, (start_size + start_size_var) / BASE)
    # finishSize < 0 = "startSize와 동일"(변화 없음) → 비율 1.0.
    scale_end_ratio = 1.0 if finish_size < 0 else max(0.0, finish_size / max(1.0, start_size))
    out = {
        "_src": rel,
        "amount": int(F(d, "maxParticles", 100)),
        "lifetime": round(life_max, 4),
        "lifetime_randomness": round((life_var / life_max) if life_max > 0 else 0.0, 4),
        "direction": [round(direction[0], 4), round(direction[1], 4)],
        "spread": round(ang_var, 2),
        "vmin": round(speed - speed_var, 2),
        "vmax": round(speed + speed_var, 2),
        "gravity": [round(F(d, "gravityx"), 2), round(-F(d, "gravityy"), 2)],  # y 반전
        "radial_min": round(F(d, "radialAcceleration") - F(d, "radialAccelVariance"), 2),
        "radial_max": round(F(d, "radialAcceleration") + F(d, "radialAccelVariance"), 2),
        "tangential_min": round(F(d, "tangentialAcceleration") - F(d, "tangentialAccelVariance"), 2),
        "tangential_max": round(F(d, "tangentialAcceleration") + F(d, "tangentialAccelVariance"), 2),
        "scale_min": round(scale_min, 4),
        "scale_max": round(scale_max, 4),
        "scale_end_ratio": round(scale_end_ratio, 4),
        "emit_rect": [round(F(d, "sourcePositionVariancex"), 1), round(F(d, "sourcePositionVariancey"), 1)],
        "color_start": [round(F(d, "startColorRed"), 3), round(F(d, "startColorGreen"), 3),
                        round(F(d, "startColorBlue"), 3), round(F(d, "startColorAlpha"), 3)],
        "color_end": [round(F(d, "finishColorRed"), 3), round(F(d, "finishColorGreen"), 3),
                      round(F(d, "finishColorBlue"), 3), round(F(d, "finishColorAlpha"), 3)],
        "additive": int(F(d, "blendFuncDestination")) == 1,
        # 입자 회전 — 별처럼 모양이 있는 텍스처에서만 눈에 띈다(원형 점은 티가 안 난다).
        "angle_min": round(F(d, "rotationStart") - F(d, "rotationStartVariance"), 2),
        "angle_max": round(F(d, "rotationStart") + F(d, "rotationStartVariance"), 2),
        "angle_end": round(F(d, "rotationEnd"), 2),
    }
    if wh:
        out["tex_size"] = [wh[0], wh[1]]            # `texture` 키는 main 이 출력 이름으로 채운다
    return out, png


def main():
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    dst = os.path.join(root, DST)
    os.makedirs(dst, exist_ok=True)
    os.chdir(root)
    for rel, name in SOURCES:
        o, png = convert(rel)
        if png:
            o["texture"] = name + ".png"
            with open(os.path.join(dst, o["texture"]), "wb") as f:
                f.write(png)
        with open(os.path.join(dst, name + ".json"), "w", encoding="utf-8") as f:
            json.dump(o, f, ensure_ascii=False, indent=1)
        print("[particle] %-18s amount=%3d life=%.2f dir=%s add=%-5s tex=%s" % (
            name, o["amount"], o["lifetime"], o["direction"], o["additive"],
            "%s %s" % (o.get("texture"), o.get("tex_size")) if png else "(절차생성 점)"))


if __name__ == "__main__":
    main()

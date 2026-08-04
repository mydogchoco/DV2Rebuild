"""Export an old DV2 Spine skeleton to a Godot-friendly intermediate JSON.

Pipeline step 2 of the 4b offline converter:
  spine_json + Spine atlas(es) (.img_plist) + page PNG  ->
  assets/converted/dragon_<id>/<stage>.json  (+ copied page PNGs)

Coordinate conversion Spine(Y-up, CCW deg) -> Godot(Y-down, CW rad):
  pos=(x,-y)  rot=-deg2rad(angle)  scale=(sx,sy)   (reflection about X axis)

Region attachment rendering bakes atlas rotation + trim(offset/orig) so each
slot becomes: bone -> attach-frame(Node2D) -> Sprite2D(AtlasTexture region).

usage: spine_export.py <dragon_id> <stage> [--anim NAME|all]
"""
import sys, os, json, math, shutil, glob
import atlas as atlaslib

SRC = "DV2/480/dragon"
OUTROOT = "assets/converted"


def d2r(deg):
    return -math.radians(deg)  # negate for Y-flip


def parse_color(c):  # "RRGGBBAA" -> [r,g,b,a] in 0..1
    return [int(c[i:i + 2], 16) / 255.0 for i in (0, 2, 4, 6)]


def _premult(c):  # spine color -> Godot modulate(premult): rgb·a, a
    r, g, b, a = parse_color(c)
    return [r * a, g * a, b * a, a]


def find_atlases(stage_json_basename):
    """Atlases for a dragon: main dragon_<id>_spine.img_plist + skin subfolder."""
    return []  # filled by caller (explicit list)


def png_for_page(atlas_path, page_image):
    # "X.pvr.ccz" -> sibling "X.png"
    stem = os.path.basename(page_image).split(".")[0]
    return os.path.join(os.path.dirname(atlas_path), stem + ".png")


def load_merged_atlas(atlas_paths, region_basename=False):
    """Merge regions across atlases. Returns regions{name->info(+png abs path, +page size)}.

    region_basename: 리전 이름의 마지막 경로 조각으로도 찾을 수 있게 별칭을 단다.
      DV2 원본 아틀라스는 리전명이 평면(`dragon_god_adult_love`)이라 이 옵션이 무의미하지만,
      DV1 에서 가져온 스켈레톤은 **어태치먼트가 `arm1` 인데 리전은 `dragon/3607/adult/arm1`**
      이라 그대로는 하나도 안 붙는다(§10 판본/출처 불일치, 포팅카드 DragonLoki800.md §3-2).
      별칭은 **원래 이름이 없을 때만** 넣으므로 기존 변환에는 영향이 없다.
    """
    regions = {}
    for ap in atlas_paths:
        a = atlaslib.parse_spine_atlas(ap)
        for name, r in a["regions"].items():
            page = a["pages"][r["page"]]
            r = dict(r)
            r["png"] = png_for_page(ap, page["image"])
            regions[name] = r
    if region_basename:
        for name, r in list(regions.items()):
            base = name.rsplit("/", 1)[-1]
            if base != name and base not in regions:
                regions[base] = r
    return regions


def premultiply_png(src, dst):
    """스트레이트 알파 PNG → 프리멀티플라이 사본. 우리 씬 빌더가 PMA 블렌드로 그리기 때문에
    (`build_spine_scene.gd` BLEND_MODE_PREMULT_ALPHA) 스트레이트 원본을 그대로 쓰면 반투명
    가장자리가 흰 테를 두른다. DV2 원본 아틀라스는 이미 PMA 라 이 경로를 타지 않는다."""
    from PIL import Image, ImageChops
    im = Image.open(src).convert("RGBA")
    r, g, b, a = im.split()
    # ImageChops.multiply 는 (v1*v2)/255 — 채널마다 알파를 곱하는 것이 곧 프리멀티플라이다.
    Image.merge("RGBA", (ImageChops.multiply(r, a),
                         ImageChops.multiply(g, a),
                         ImageChops.multiply(b, a), a)).save(dst)


def export(dragon_id, stage, anim_filter="all", sj_path=None, atlas_paths=None, outdir=None,
           region_basename=False, premultiply=False, anim_map=None):
    # 드래곤 기본 경로 규약. sj_path/atlas_paths/outdir 명시 시 그걸 사용(몬스터 등 일반 스파인).
    if sj_path is None:
        sj_path = os.path.join(SRC, f"dragon_{dragon_id}_{stage}_spine.spine_json")
    skel = json.load(open(sj_path, encoding="utf-8"))

    if atlas_paths is None:
        atlas_paths = [
            os.path.join(SRC, f"dragon_{dragon_id}_spine.img_plist"),
            os.path.join(SRC, f"dragon_{dragon_id}_spine", f"skin_{dragon_id}_spine.img_plist"),
        ]
    atlas_paths = [p for p in atlas_paths if os.path.exists(p)]
    regions = load_merged_atlas(atlas_paths, region_basename=region_basename)

    if outdir is None:
        outdir = os.path.join(OUTROOT, f"dragon_{dragon_id}")
    os.makedirs(outdir, exist_ok=True)

    # copy needed page PNGs, map png abs path -> res:// path
    png_res = {}
    for r in regions.values():
        src_png = r["png"]
        if src_png not in png_res and os.path.exists(src_png):
            dst = os.path.join(outdir, os.path.basename(src_png))
            if premultiply:
                premultiply_png(src_png, dst)
            else:
                shutil.copyfile(src_png, dst)
            png_res[src_png] = f"res://{outdir.replace(os.sep,'/')}/{os.path.basename(src_png)}"

    # ---- bones (setup pose, Godot space) ----
    bones = []
    for b in skel["bones"]:
        bones.append({
            "name": b["name"],
            "parent": b.get("parent"),
            "pos": [b.get("x", 0.0), -b.get("y", 0.0)],
            "rot": d2r(b.get("rotation", 0.0)),
            "scale": [b.get("scaleX", 1.0), b.get("scaleY", 1.0)],
        })

    bone_names = {b["name"] for b in skel["bones"]}   # 슬롯 스프라이트 이름 충돌 회피용
    # 슬롯 attachment 처리: 한 슬롯이 여러 attachment(예: eye/eye2/eye3=눈 깜빡임)로 교체되면
    # attachment마다 Sprite2D를 만들어 두고 애니에서 활성 1개만 visible로 토글한다.
    # 이펙트/스킨 슬롯(heart/eff/*_skin)은 attachment=None/alpha0으로 평소 숨김.
    src_anims = skel.get("animations", {})
    wait_slots = src_anims.get("wait", {}).get("slots", {})
    default_skin = skel["skins"]["default"] if isinstance(skel["skins"], dict) else {}

    slot_setup_att = {s["name"]: s.get("attachment") for s in skel["slots"]}
    slot_variants = {}    # slot -> set(att names with region)
    slot_has_none = {}    # slot -> 타임라인에 None(숨김)이 등장하는가
    for s in skel["slots"]:
        sa = s.get("attachment")
        if sa and sa in regions:
            slot_variants.setdefault(s["name"], set()).add(sa)
    for a in src_anims.values():
        for sn, tl in a.get("slots", {}).items():
            for k in tl.get("attachment", []):
                nm = k.get("name")
                if nm is None:
                    slot_has_none[sn] = True
                elif nm in regions:
                    slot_variants.setdefault(sn, set()).add(nm)

    def default_att(slot_name):
        # 쉬는 상태에서 활성인 attachment(None=숨김). wait t0 기준, 없으면 setup.
        tl = wait_slots.get(slot_name, {})
        att = tl.get("attachment")
        if att:
            return att[0].get("name")
        col = tl.get("color")
        if col and int(col[0]["color"][6:8], 16) == 0:
            return None
        return slot_setup_att.get(slot_name)

    # 동적 슬롯 = attachment 교체/토글이 있어 visible 관리가 필요
    slot_dynamic = {}
    for sn, vs in slot_variants.items():
        slot_dynamic[sn] = (len(vs) > 1) or slot_has_none.get(sn, False) or (default_att(sn) is None)

    def make_sprite(slot, att_name, idx, multi):
        att = default_skin.get(slot["name"], {}).get(att_name, {})
        reg = regions.get(att_name)
        if reg is None:
            return None
        ax, ay = att.get("x", 0.0), att.get("y", 0.0)
        arot = att.get("rotation", 0.0)
        asx, asy = att.get("scaleX", 1.0), att.get("scaleY", 1.0)
        aw, ah = att.get("width", reg["orig"][0]), att.get("height", reg["orig"][1])
        ow, oh = reg["orig"]
        rw, rh = reg["size"]
        ox, oy = reg["offset"]
        px, py = reg["xy"]
        cx = ox + rw / 2.0 - ow / 2.0
        cy = oy + rh / 2.0 - oh / 2.0
        ux = (aw / ow) if ow else 1.0
        uy = (ah / oh) if oh else 1.0
        region_rect = [px, py, rh, rw] if reg["rotate"] else [px, py, rw, rh]
        name = (slot["name"] + "__" + att_name) if multi else slot["name"]
        # 슬롯 스프라이트 이름이 본(Node2D) 이름과 충돌하면 애니 visible 토글이 구조용 본을
        # 숨겨 크리처 전체가 사라진다(예: 슬롯 'bone1' vs 본 'bone1'). 충돌 시 접미사로 분리.
        if name in bone_names:
            name = name + "_slot"
        return {
            "name": name, "slot": slot["name"], "bone": slot["bone"], "z": idx,
            "png": png_res.get(reg["png"]),
            "region_rect": region_rect, "rotated": reg["rotate"],
            "sprite_pos": [cx * ux, -cy * uy], "sprite_scale": [ux, uy],
            "frame_pos": [ax, -ay], "frame_rot": d2r(arot), "frame_scale": [asx, asy],
            "visible_default": (att_name == default_att(slot["name"])),
        }

    # ---- slots (draw order) -> sprite definitions ----
    slots = []
    slot_sprites = {}   # slot -> [(sprite_name, att_name)]
    for idx, s in enumerate(skel["slots"]):
        variants = sorted(slot_variants.get(s["name"], set()))
        multi = len(variants) > 1
        for att_name in variants:
            sp = make_sprite(s, att_name, idx, multi)
            if sp:
                slots.append(sp)
                slot_sprites.setdefault(s["name"], []).append((sp["name"], att_name))

    # ---- animations ----
    setup = {b["name"]: b for b in skel["bones"]}
    anims = {}
    names = list(src_anims) if anim_filter == "all" else [anim_filter]
    for an in names:
        a = src_anims.get(an)
        if not a:
            continue
        tracks = {}  # bone -> {rotation:[(t,val)],position:[(t,[x,y])],scale:[(t,[x,y])]}
        def cflag(k):
            # "S"=stepped(hold). bezier arrays approximated as linear "L".
            return "S" if k.get("curve") == "stepped" else "L"
        for bone_name, tl in a.get("bones", {}).items():
            su = setup.get(bone_name, {})
            bt = {}
            if "rotate" in tl:
                rk = [[k["time"], d2r(su.get("rotation", 0.0) + k.get("angle", 0.0)), cflag(k)]
                      for k in tl["rotate"]]
                # 회전 최단경로 보간: 절대각(rad) 시퀀스를 언랩해 인접 키 차이를 [-pi,pi]로.
                # (Godot 밸류트랙은 각도 wrap을 모르므로, 안 하면 body/tail이 한 바퀴 돌며 깨짐)
                for i in range(1, len(rk)):
                    while rk[i][1] - rk[i - 1][1] > math.pi:
                        rk[i][1] -= 2 * math.pi
                    while rk[i][1] - rk[i - 1][1] < -math.pi:
                        rk[i][1] += 2 * math.pi
                bt["rotation"] = rk
            if "translate" in tl:
                bt["position"] = [[k["time"], [su.get("x", 0.0) + k.get("x", 0.0),
                                               -(su.get("y", 0.0) + k.get("y", 0.0))], cflag(k)]
                                  for k in tl["translate"]]
            if "scale" in tl:
                bt["scale"] = [[k["time"], [su.get("scaleX", 1.0) * k.get("x", 1.0),
                                            su.get("scaleY", 1.0) * k.get("y", 1.0)], cflag(k)]
                               for k in tl["scale"]]
            if bt:
                tracks[bone_name] = bt
        # ---- slot timelines: 변형별 표시여부(visible) + 색알파(modulate) ----
        # 동적 슬롯은 attachment 타임라인으로 변형별 visible 토글(눈 깜빡임/이펙트 등장).
        slot_tracks = {}   # sprite_name -> {visible, modulate}
        anim_slots = a.get("slots", {})
        for slot_name, sprite_list in slot_sprites.items():
            tl = anim_slots.get(slot_name, {})
            att_tl = tl.get("attachment")
            col_tl = tl.get("color")
            dyn = slot_dynamic.get(slot_name, False)
            da = default_att(slot_name)
            mod = [[k["time"], _premult(k["color"]), cflag(k)] for k in col_tl] if col_tl else None
            for sprite_name, att_name in sprite_list:
                stt = {}
                if dyn:
                    if att_tl:
                        stt["visible"] = [[k["time"], (k.get("name") == att_name), "S"] for k in att_tl]
                    else:
                        stt["visible"] = [[0.0, (att_name == da), "S"]]   # 타임라인 없으면 기본 유지
                if mod is not None:
                    stt["modulate"] = mod
                if stt:
                    slot_tracks[sprite_name] = stt

        # duration (본 + 슬롯 타임라인 모두 고려)
        dur = 0.0
        for bt in tracks.values():
            for keys in bt.values():
                if keys:
                    dur = max(dur, keys[-1][0])
        for stt in slot_tracks.values():
            for keys in stt.values():
                if keys:
                    dur = max(dur, keys[-1][0])
        # anim_map: 원본 애니 이름 → 우리 규약 이름. DV1 에서 온 스켈레톤은 공격 애니가
        # `att` 인데 우리 렌더는 DV2 이름 `attack` 을 부른다(`fight.gd::_play_anim`).
        # 호출부 40여 곳을 드래곤별로 분기시키는 대신 **변환 시점에** 이름을 맞춘다(§8.4 카탈로그 계층).
        anims[(anim_map or {}).get(an, an)] = {
            "length": dur, "tracks": tracks, "slot_tracks": slot_tracks}

    out = {
        "id": dragon_id, "stage": stage,
        "bones": bones, "slots": slots, "animations": anims,
        "missing_regions": sorted(set(s.get("attachment") for s in skel["slots"]
                                      if s.get("attachment") and s["attachment"] not in regions)),
    }
    outpath = os.path.join(outdir, f"{stage}.json")
    json.dump(out, open(outpath, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"wrote {outpath}")
    print(f"  bones={len(bones)} slots={len(slots)} anims={list(anims)} pages={len(set(png_res.values()))}")
    if out["missing_regions"]:
        print("  WARNING missing regions:", out["missing_regions"])
    rot = sum(1 for s in slots if s["rotated"])
    print(f"  rotated-region slots: {rot}/{len(slots)}")


def export_monster(mid, anim_filter="all"):
    """몬스터 스파인 변환: DV2/480/monster/<id>/<id>_monster_spine.spine_json + <id>_spine.img_plist
    → assets/converted/monster_<id>/monster.json (이미지 아틀라스와 같은 dir 병합)."""
    base = os.path.join("DV2/480/monster", str(mid))
    sj = os.path.join(base, f"{mid}_monster_spine.spine_json")
    atl = [os.path.join(base, f"{mid}_spine.img_plist")]
    outdir = os.path.join(OUTROOT, f"monster_{mid}")
    export(mid, "monster", anim_filter, sj_path=sj, atlas_paths=atl, outdir=outdir)


def export_critical(did, awaken=False, anim_filter="all"):
    """크리티컬 연출 스파인 변환.

    원작 `MakeInterface::criticalEffectMake`(MakeInterface.c:9853-9925)가 쓰는 조합 그대로다:
      · 스켈레톤 = `dragon/dragon_<id>_critical_spine.spine_json`
                   (각성이면 `dragon_<id>_e_critical_spine.spine_json` — getAwaken 분기)
      · 아틀라스 = `dragon/dragon_<id>_spine.img_plist`  ← **크리티컬 전용 아틀라스가 아니라
                   드래곤의 일반 스파인 아틀라스**를 쓴다. 원작 코드가 그렇게 부른다.
      · 애니메이션 이름 = "animation" (criticalPlaceEffect 가 getDuration("animation") 로 확인)

    산출은 `assets/converted/dragon_<id>/{critical|e_critical}.json` — 이미 임포트된 같은 폴더의
    페이지 PNG를 재사용하려는 것이다(중복 복사 방지 + 임포트 안 된 PNG를 참조해 아틀라스 링크가
    빠지는 사고 방지). 씬은 build_all.gd 가 이 폴더의 json 을 그대로 훑어 만든다."""
    stage = "e_critical" if awaken else "critical"
    sj = os.path.join(SRC, f"dragon_{did}_{'e_' if awaken else ''}critical_spine.spine_json")
    if not os.path.exists(sj):
        return None
    atl = [os.path.join(SRC, f"dragon_{did}_spine.img_plist")]
    if not os.path.exists(atl[0]):
        return None
    outdir = os.path.join(OUTROOT, f"dragon_{did}")
    export(did, stage, anim_filter, sj_path=sj, atlas_paths=atl, outdir=outdir)
    return os.path.join(outdir, f"{stage}.json")


def export_scene(spine_path, anim_filter="all", atlas_path=None):
    """씬 스파인 변환(월드맵 앰비언트 등): <dir>/<name>_spine.spine_json + 같은 이름 .img_plist
    → assets/converted/scenespine_<name>/<name>.json.
    원작 WorldMapYutakanLayer가 쓰는 ani_*_spine 12종이 이 경로에 있다(드래곤/몬스터와 디렉터리
    규약이 달라 전용 진입점이 필요)."""
    base = os.path.splitext(spine_path)[0]          # .../ani_waterfall_spine
    name = os.path.basename(base)
    # 스켈레톤과 아틀라스 이름이 다른 경우가 있다(dragon_enchant_lvup ↔ enchant_lvup_spine).
    atl = [atlas_path] if atlas_path else [base + ".img_plist"]
    if not os.path.exists(atl[0]):
        print(f"[skip] 아틀라스 없음: {atl[0]}  (--atlas 로 지정)")
        return None
    outdir = os.path.join(OUTROOT, f"scenespine_{name}")
    export(name, "scene", anim_filter, sj_path=spine_path, atlas_paths=atl, outdir=outdir)
    return os.path.join(outdir, "scene.json")


if __name__ == "__main__":
    af = "all"
    if "--anim" in sys.argv:
        af = sys.argv[sys.argv.index("--anim") + 1]
    if "--scene" in sys.argv:
        ap = sys.argv[sys.argv.index("--atlas") + 1] if "--atlas" in sys.argv else None
        export_scene(sys.argv[sys.argv.index("--scene") + 1], af, atlas_path=ap)
    elif "--monster" in sys.argv:
        export_monster(sys.argv[sys.argv.index("--monster") + 1], af)
    else:
        did = sys.argv[1] if len(sys.argv) > 1 else "1"
        stage = sys.argv[2] if len(sys.argv) > 2 else "baby"
        export(did, stage, af)

import sys, os, json, math, shutil, glob
import atlas as atlaslib

SRC = "DV2/480/dragon"
OUTROOT = "assets/converted"
ATLAS_FIX = "assets/converted/atlas_fix"

AWAKEN_ATLAS_MISSING = {
    ("104", "e"), ("104", "e_critical"),
    ("4099", "e"), ("4099", "e_critical"),
}

def d2r(deg):
    return -math.radians(deg)

def parse_color(c):
    return [int(c[i:i + 2], 16) / 255.0 for i in (0, 2, 4, 6)]

def _premult(c):
    r, g, b, a = parse_color(c)
    return [r * a, g * a, b * a, a]

def find_atlases(stage_json_basename):
    return []

def png_for_page(atlas_path, page_image):
    stem = os.path.basename(page_image).split(".")[0]
    return os.path.join(os.path.dirname(atlas_path), stem + ".png")

def atlas_fix_for(atlas_path):
    fixed = os.path.join(ATLAS_FIX, os.path.basename(atlas_path))
    return fixed if os.path.exists(fixed) else atlas_path

def load_merged_atlas(atlas_paths, region_basename=False):
    regions = {}
    for ap in atlas_paths:
        a = atlaslib.parse_spine_atlas(atlas_fix_for(ap))
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
    from PIL import Image, ImageChops
    im = Image.open(src).convert("RGBA")
    r, g, b, a = im.split()
    Image.merge("RGBA", (ImageChops.multiply(r, a),
                         ImageChops.multiply(g, a),
                         ImageChops.multiply(b, a), a)).save(dst)

def export(dragon_id, stage, anim_filter="all", sj_path=None, atlas_paths=None, outdir=None,
           region_basename=False, premultiply=False, anim_map=None, root_scale=1.0):
    if sj_path is None:
        sj_path = os.path.join(SRC, f"dragon_{dragon_id}_{stage}_spine.spine_json")

    if sj_path.endswith(".src.json"):
        doc = json.load(open(sj_path, encoding="utf-8"))
        skel = doc["rig"]
        src_dir = os.path.dirname(sj_path)
        regions = {}
        for name, r in doc["regions"].items():
            r = dict(r)
            r["png"] = os.path.join(src_dir, doc["pages"][r["page"]]["image"])
            regions[name] = r
        if region_basename:
            for name, r in list(regions.items()):
                base = name.rsplit("/", 1)[-1]
                if base != name and base not in regions:
                    regions[base] = r
    else:
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

    bones = []
    for b in skel["bones"]:
        bones.append({
            "name": b["name"],
            "parent": b.get("parent"),
            "pos": [b.get("x", 0.0), -b.get("y", 0.0)],
            "rot": d2r(b.get("rotation", 0.0)),
            "scale": [b.get("scaleX", 1.0), b.get("scaleY", 1.0)],
        })

    bone_names = {b["name"] for b in skel["bones"]}
    src_anims = skel.get("animations", {})
    wait_slots = src_anims.get("wait", {}).get("slots", {})
    default_skin = skel["skins"]["default"] if isinstance(skel["skins"], dict) else {}

    slot_setup_att = {s["name"]: s.get("attachment") for s in skel["slots"]}
    slot_variants = {}
    slot_has_none = {}
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
        tl = wait_slots.get(slot_name, {})
        att = tl.get("attachment")
        if att:
            return att[0].get("name")
        col = tl.get("color")
        if col and int(col[0]["color"][6:8], 16) == 0:
            return None
        return slot_setup_att.get(slot_name)

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

    slots = []
    slot_sprites = {}
    for idx, s in enumerate(skel["slots"]):
        variants = sorted(slot_variants.get(s["name"], set()))
        multi = len(variants) > 1
        for att_name in variants:
            sp = make_sprite(s, att_name, idx, multi)
            if sp:
                slots.append(sp)
                slot_sprites.setdefault(s["name"], []).append((sp["name"], att_name))

    setup = {b["name"]: b for b in skel["bones"]}
    anims = {}
    names = list(src_anims) if anim_filter == "all" else [anim_filter]
    for an in names:
        a = src_anims.get(an)
        if not a:
            continue
        tracks = {}
        def cflag(k):
            return "S" if k.get("curve") == "stepped" else "L"
        for bone_name, tl in a.get("bones", {}).items():
            su = setup.get(bone_name, {})
            bt = {}
            if "rotate" in tl:
                rk = [[k["time"], d2r(su.get("rotation", 0.0) + k.get("angle", 0.0)), cflag(k)]
                      for k in tl["rotate"]]
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
        slot_tracks = {}
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
                        stt["visible"] = [[0.0, (att_name == da), "S"]]
                if mod is not None:
                    stt["modulate"] = mod
                if stt:
                    slot_tracks[sprite_name] = stt

        dur = 0.0
        for bt in tracks.values():
            for keys in bt.values():
                if keys:
                    dur = max(dur, keys[-1][0])
        for stt in slot_tracks.values():
            for keys in stt.values():
                if keys:
                    dur = max(dur, keys[-1][0])
        anims[(anim_map or {}).get(an, an)] = {
            "length": dur, "tracks": tracks, "slot_tracks": slot_tracks}

    out = {
        "id": dragon_id, "stage": stage,
        "root_scale": float(root_scale),
        "bones": bones, "slots": slots, "animations": anims,
        "missing_regions": sorted(set(s.get("attachment") for s in skel["slots"]
                                      if s.get("attachment") and s["attachment"] not in regions)),
    }
    if (str(dragon_id), stage) in AWAKEN_ATLAS_MISSING:
        print(f"[skip] dragon {dragon_id} {stage}: 각성체 아틀라스 부재 — 굽지 않는다 "
              f"(리전 {len(out['missing_regions'])}종 없음, Icons.AWAKEN_SPINE_MISSING 이 대체)")
        return
    outpath = os.path.join(outdir, f"{stage}.json")
    json.dump(out, open(outpath, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"wrote {outpath}")
    print(f"  bones={len(bones)} slots={len(slots)} anims={list(anims)} pages={len(set(png_res.values()))}")
    if out["missing_regions"]:
        print("  WARNING missing regions:", out["missing_regions"])
    rot = sum(1 for s in slots if s["rotated"])
    print(f"  rotated-region slots: {rot}/{len(slots)}")

def export_monster(mid, anim_filter="all"):
    base = os.path.join("DV2/480/monster", str(mid))
    sj = os.path.join(base, f"{mid}_monster_spine.spine_json")
    atl = [os.path.join(base, f"{mid}_spine.img_plist")]
    outdir = os.path.join(OUTROOT, f"monster_{mid}")
    export(mid, "monster", anim_filter, sj_path=sj, atlas_paths=atl, outdir=outdir)

def export_critical(did, awaken=False, anim_filter="all"):
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
    base = os.path.splitext(spine_path)[0]
    name = os.path.basename(base)
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

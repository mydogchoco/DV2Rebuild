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


def find_atlases(stage_json_basename):
    """Atlases for a dragon: main dragon_<id>_spine.img_plist + skin subfolder."""
    return []  # filled by caller (explicit list)


def png_for_page(atlas_path, page_image):
    # "X.pvr.ccz" -> sibling "X.png"
    stem = os.path.basename(page_image).split(".")[0]
    return os.path.join(os.path.dirname(atlas_path), stem + ".png")


def load_merged_atlas(atlas_paths):
    """Merge regions across atlases. Returns regions{name->info(+png abs path, +page size)}."""
    regions = {}
    for ap in atlas_paths:
        a = atlaslib.parse_spine_atlas(ap)
        for name, r in a["regions"].items():
            page = a["pages"][r["page"]]
            r = dict(r)
            r["png"] = png_for_page(ap, page["image"])
            regions[name] = r
    return regions


def export(dragon_id, stage, anim_filter="all"):
    sj_path = os.path.join(SRC, f"dragon_{dragon_id}_{stage}_spine.spine_json")
    skel = json.load(open(sj_path, encoding="utf-8"))

    atlas_paths = [
        os.path.join(SRC, f"dragon_{dragon_id}_spine.img_plist"),
        os.path.join(SRC, f"dragon_{dragon_id}_spine", f"skin_{dragon_id}_spine.img_plist"),
    ]
    atlas_paths = [p for p in atlas_paths if os.path.exists(p)]
    regions = load_merged_atlas(atlas_paths)

    outdir = os.path.join(OUTROOT, f"dragon_{dragon_id}")
    os.makedirs(outdir, exist_ok=True)

    # copy needed page PNGs, map png abs path -> res:// path
    png_res = {}
    for r in regions.values():
        src_png = r["png"]
        if src_png not in png_res and os.path.exists(src_png):
            dst = os.path.join(outdir, os.path.basename(src_png))
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

    # ---- slots (draw order) -> sprite definitions ----
    default_skin = skel["skins"]["default"] if isinstance(skel["skins"], dict) else {}
    slots = []
    for idx, s in enumerate(skel["slots"]):
        att_name = s.get("attachment")
        if not att_name:
            continue
        skin_slot = default_skin.get(s["name"], {})
        att = skin_slot.get(att_name, {})
        reg = regions.get(att_name)
        if reg is None:
            continue  # region not found (warn later)
        ax, ay = att.get("x", 0.0), att.get("y", 0.0)
        arot = att.get("rotation", 0.0)
        asx, asy = att.get("scaleX", 1.0), att.get("scaleY", 1.0)
        aw, ah = att.get("width", reg["orig"][0]), att.get("height", reg["orig"][1])
        ow, oh = reg["orig"]
        rw, rh = reg["size"]
        ox, oy = reg["offset"]
        px, py = reg["xy"]
        # trim center: region center within orig box (y-up), origin at box center
        cx = ox + rw / 2.0 - ow / 2.0
        cy = oy + rh / 2.0 - oh / 2.0
        # bone-unit scale from pixels (usually ~1 when aw==ow)
        ux = (aw / ow) if ow else 1.0
        uy = (ah / oh) if oh else 1.0
        if reg["rotate"]:
            region_rect = [px, py, rh, rw]   # occupied (swapped) in page
        else:
            region_rect = [px, py, rw, rh]
        slots.append({
            "name": s["name"],
            "bone": s["bone"],
            "z": idx,
            "png": png_res.get(reg["png"]),
            "region_rect": region_rect,         # [x,y,w,h] on page
            "rotated": reg["rotate"],            # atlas 90deg rotation
            "sprite_pos": [cx * ux, -cy * uy],   # under attach-frame, Godot space
            "sprite_scale": [ux, uy],
            # attach-frame transform (under bone)
            "frame_pos": [ax, -ay],
            "frame_rot": d2r(arot),
            "frame_scale": [asx, asy],
        })

    # ---- animations ----
    setup = {b["name"]: b for b in skel["bones"]}
    anims = {}
    src_anims = skel.get("animations", {})
    names = list(src_anims) if anim_filter == "all" else [anim_filter]
    for an in names:
        a = src_anims.get(an)
        if not a:
            continue
        tracks = {}  # bone -> {rotation:[(t,val)],position:[(t,[x,y])],scale:[(t,[x,y])]}
        for bone_name, tl in a.get("bones", {}).items():
            su = setup.get(bone_name, {})
            bt = {}
            if "rotate" in tl:
                bt["rotation"] = [[k["time"], d2r(su.get("rotation", 0.0) + k.get("angle", 0.0))]
                                  for k in tl["rotate"]]
            if "translate" in tl:
                bt["position"] = [[k["time"], [su.get("x", 0.0) + k.get("x", 0.0),
                                               -(su.get("y", 0.0) + k.get("y", 0.0))]]
                                  for k in tl["translate"]]
            if "scale" in tl:
                bt["scale"] = [[k["time"], [su.get("scaleX", 1.0) * k.get("x", 1.0),
                                            su.get("scaleY", 1.0) * k.get("y", 1.0)]]
                               for k in tl["scale"]]
            if bt:
                tracks[bone_name] = bt
        # duration
        dur = 0.0
        for bt in tracks.values():
            for keys in bt.values():
                if keys:
                    dur = max(dur, keys[-1][0])
        anims[an] = {"length": dur, "tracks": tracks}

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


if __name__ == "__main__":
    did = sys.argv[1] if len(sys.argv) > 1 else "1"
    stage = sys.argv[2] if len(sys.argv) > 2 else "baby"
    af = "all"
    if "--anim" in sys.argv:
        af = sys.argv[sys.argv.index("--anim") + 1]
    export(did, stage, af)

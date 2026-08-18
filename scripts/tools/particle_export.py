import base64, io, json, math, os, plistlib, struct, zlib

DST = "assets/converted/particles"
SOURCES = [
    ("scene/adventure/pt_levelup_light", "pt_levelup_light"),
    ("scene/adventure/pt_3max1", "pt_3max1"),
    ("scene/adventure/pt_3max2", "pt_3max2"),
    ("scene/adventure/pt_monster_income_1", "pt_monster_income_1"),
    ("scene/fortunetent/crystalball", "crystalball"),
    ("scenario/pt_feature_c", "pt_feature_c"),
    ("scene/common/pt_rev_up", "pt_rev_up"),
    ("scene/common/pt_take_skill", "pt_take_skill"),
    ("scene/laboratory/generate_effect", "generate_effect"),
    ("scene/common/reset_slot", "reset_slot"),
    ("scene/adventure/pt_monster_fire_back", "pt_monster_fire_back"),
    ("scene/adventure/pt_skill_14_vamp", "pt_skill_14_vamp"),
    ("scene/promote/mate", "promote_mate"),
    ("scene/adventure/pt_shild", "pt_shild"),
    ("scene/adventure/effect_fire2", "effect_fire2"),
    ("scene/adventure/pt_monster_dead_2_2", "pt_monster_dead_2_2"),
    ("scene/adventure/skill_29", "skill_29"),
    ("scene/cave/dust", "cave_dust"),
    ("scene/colosseum/effect_damaged", "colosseum_damaged"),
    ("scene/colosseum/effect_dead", "colosseum_dead"),
    ("skill/skill_14", "skill_14"),
    ("skill/skill_31", "skill_31"),
    ("skill/skill_13_effect", "skill_13_effect"),
    ("skill/skill_14_effect", "skill_14_effect"),
]

def F(d, k, default=0.0):
    v = d.get(k, default)
    try:
        return float(v)
    except (TypeError, ValueError):
        return default

def texture_png(d, rel):
    src = os.path.join("DV2/particle", os.path.dirname(rel), str(d.get("textureFileName", "")))
    if os.path.isfile(src):
        return open(src, "rb").read()
    raw = d.get("textureImageData")
    if not raw:
        return None
    if isinstance(raw, str):
        raw = base64.b64decode(raw)
    try:
        blob = zlib.decompress(bytes(raw), 47)
    except zlib.error:
        blob = bytes(raw)
    if blob[:8] == b"\x89PNG\r\n\x1a\n":
        return blob
    from PIL import Image
    buf = io.BytesIO()
    Image.open(io.BytesIO(blob)).convert("RGBA").save(buf, "PNG")
    return buf.getvalue()

def png_size(blob):
    if not blob or blob[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    w, h = struct.unpack(">II", blob[16:24])
    return (w, h)

def convert(rel):
    d = plistlib.load(open(os.path.join("DV2/particle", rel + ".plist"), "rb"))
    angle = F(d, "angle")
    ang_var = F(d, "angleVariance")
    rad = math.radians(angle)
    direction = [math.cos(rad), -math.sin(rad)]
    speed = F(d, "speed"); speed_var = F(d, "speedVariance")
    life = F(d, "particleLifespan"); life_var = F(d, "particleLifespanVariance")
    life_max = life + life_var
    start_size = F(d, "startParticleSize"); start_size_var = F(d, "startParticleSizeVariance")
    finish_size = F(d, "finishParticleSize", -1)
    png = texture_png(d, rel)
    wh = png_size(png)
    BASE = float(wh[0]) if wh else 32.0
    scale_min = max(0.05, (start_size - start_size_var) / BASE)
    scale_max = max(scale_min, (start_size + start_size_var) / BASE)
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
        "gravity": [round(F(d, "gravityx"), 2), round(-F(d, "gravityy"), 2)],
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
        "angle_min": round(F(d, "rotationStart") - F(d, "rotationStartVariance"), 2),
        "angle_max": round(F(d, "rotationStart") + F(d, "rotationStartVariance"), 2),
        "angle_end": round(F(d, "rotationEnd"), 2),
    }
    if wh:
        out["tex_size"] = [wh[0], wh[1]]
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

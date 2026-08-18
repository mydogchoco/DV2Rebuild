from __future__ import annotations
import json, math, os, sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(REPO)
DIR = "assets/converted/dragon_800"
STAGES = ["baby", "child", "adult", "aura", "e", "advent"]

D = math.radians

def _rot(base: float, keys) -> list:
    return [[t, base + D(deg), "L"] for t, deg in keys]

def _pos(base, keys) -> list:
    return [[t, [base[0] + dx, base[1] + dy], "L"] for t, dx, dy in keys]

def _scl(base, keys) -> list:
    return [[t, [base[0] * sx, base[1] * sy], "L"] for t, sx, sy in keys]

def _wave(dur, amp, cycles, phase=0.0, steps=8):
    return [(round(dur * i / steps, 4),
             amp * math.sin(2 * math.pi * (cycles * i / steps + phase)))
            for i in range(steps + 1)]

BODY_PREF = ("ctr", "all", "bone", "body1")
FX_BONE = ("portal", "smoke", "feather", "effect", "shadow", "bird")

SKEL_H = {"baby": 122.0, "child": 210.0, "adult": 289.0, "aura": 390.0, "e": 798.0,
          "advent": 491.0}

def _body_bone(data: dict) -> str | None:
    par = {b["name"]: b.get("parent") for b in data["bones"]}
    for want in BODY_PREF:
        if want in par:
            return want
    kids: dict[str, int] = {}
    for name in par:
        cur, seen = par.get(name), 0
        while cur is not None and seen < 64:
            kids[cur] = kids.get(cur, 0) + 1
            cur, seen = par.get(cur), seen + 1
    cands = [n for n, p in par.items() if p in (None, "root") and n != "root"
             and not any(f in n for f in FX_BONE)]
    return max(cands, key=lambda n: kids.get(n, 0)) if cands else None

def _setup(data: dict) -> dict:
    return {b["name"]: b for b in data["bones"]}

def _names(data: dict, *prefixes) -> list:
    return [b["name"] for b in data["bones"]
            if any(b["name"].startswith(p) for p in prefixes)]

def _slot_hold(data: dict) -> dict:
    wait = data.get("animations", {}).get("wait", {})
    out = {}
    for sprite, tracks in wait.get("slot_tracks", {}).items():
        held = {}
        for kind, keys in tracks.items():
            if keys:
                held[kind] = [[0.0, keys[0][1], keys[0][2]]]
        if held:
            out[sprite] = held
    return out

EYE = {
    "baby":   ("eye1__eye1", "eye1__eye3"),
    "child":  ("eye1__eye1", "eye1__eye4"),
    "adult":  ("eye1__eye1", "eye1__eye4"),
    "aura":   ("eye1__eye1", "eye1__eye3"),
    "advent": ("eye1__eye1", "eye1__eye3"),
    "e":      ("eye1_slot", "eye3"),
}

def close_eyes(anim: dict, stage: str) -> None:
    pair = EYE.get(stage)
    if pair is None:
        return
    opened, closed = pair
    st = anim.setdefault("slot_tracks", {})
    st[opened] = {"visible": [[0.0, False, "S"]],
                  "modulate": [[0.0, [0.0, 0.0, 0.0, 0.0], "S"]]}
    st[closed] = {"visible": [[0.0, True, "S"]],
                  "modulate": [[0.0, [1.0, 1.0, 1.0, 1.0], "S"]]}

def make_attack_from_pose(data: dict, pose: dict) -> dict:
    dur = 0.68
    su = _setup(data)
    tracks: dict[str, dict] = {}
    for bone, ch in pose.get("tracks", {}).items():
        base = su.get(bone)
        if base is None:
            continue
        out = {}
        for kind, keys in ch.items():
            if not keys:
                continue
            tgt = keys[0][1]
            if kind == "rotation":
                b = float(base["rot"])
                t = float(tgt)
                while t - b > math.pi:
                    t -= 2 * math.pi
                while t - b < -math.pi:
                    t += 2 * math.pi
                anti = b - (t - b) * 0.12
                out[kind] = [[0.0, b, "L"], [0.06, anti, "L"], [0.18, t, "L"],
                             [0.42, t, "L"], [dur, b, "L"]]
            else:
                b = list(base["pos"] if kind == "position" else base["scale"])
                t = list(tgt)
                anti = [b[i] - (t[i] - b[i]) * 0.12 for i in (0, 1)]
                out[kind] = [[0.0, b, "L"], [0.06, anti, "L"], [0.18, t, "L"],
                             [0.42, t, "L"], [dur, b, "L"]]
        if out:
            tracks[bone] = out
    return {"length": dur, "tracks": tracks,
            "slot_tracks": pose.get("slot_tracks", {}) or _slot_hold(data)}

def make_love(data: dict, skel_h: float) -> dict:
    dur = 1.20
    su = _setup(data)
    tracks: dict[str, dict] = {}

    def put(bone, **kw):
        if bone not in su:
            return
        tracks.setdefault(bone, {}).update(kw)

    body = _body_bone(data)
    if body and body in su:
        b = su[body]
        hop = skel_h * 0.045
        put(body,
            position=_pos(b["pos"], [(0.0, 0, 0), (0.16, 0, -hop), (0.34, 0, 0),
                                     (0.50, 0, -hop * 0.55), (0.66, 0, 0), (dur, 0, 0)]),
            scale=_scl(b["scale"], [(0.0, 1, 1), (0.10, 0.97, 1.05), (0.34, 1.05, 0.95),
                                    (0.46, 1.0, 1.0), (dur, 1, 1)]))

    for h in _names(data, "head1"):
        put(h, rotation=_rot(su[h]["rot"],
                             [(0.0, 0), (0.14, -9), (0.32, 7), (0.52, -4), (0.78, 2), (dur, 0)]))
    for i, e in enumerate(_names(data, "ear")):
        s = 1 if i % 2 == 0 else -1
        put(e, rotation=_rot(su[e]["rot"],
                             [(0.0, 0), (0.10, s * 16), (0.26, s * -9), (0.44, s * 5), (dur, 0)]))
    for i, bl in enumerate(_names(data, "bell")):
        put(bl, rotation=_rot(su[bl]["rot"], _wave(dur, 13 - i, 2.5, phase=i * 0.17)))
    for i, t in enumerate(_names(data, "tail")):
        put(t, rotation=_rot(su[t]["rot"], _wave(dur, 9 + i * 3, 1.5, phase=-0.12 * i)))
    for i, m in enumerate(_names(data, "mane", "headmane", "smoke", "wing", "feather")):
        put(m, rotation=_rot(su[m]["rot"], _wave(dur, 5 + (i % 3) * 2, 1.0, phase=-0.2)))
    for i, a in enumerate(_names(data, "arm", "hand")):
        s = 1 if i % 2 == 0 else -1
        put(a, rotation=_rot(su[a]["rot"],
                             [(0.0, 0), (0.18, s * 10), (0.40, s * -5), (dur, 0)]))
    return {"length": dur, "tracks": tracks, "slot_tracks": _slot_hold(data)}

def make_attack_288(data: dict, skel_h: float) -> dict:
    dur = 0.75
    su = _setup(data)
    tracks: dict[str, dict] = {}

    def put(bone, **kw):
        if bone not in su:
            return
        tracks.setdefault(bone, {}).update(kw)

    body = _body_bone(data)
    if body and body in su:
        b = su[body]
        lunge = skel_h * (34.0 / 798.0)
        put(body,
            position=_pos(b["pos"], [(0.0, 0, 0), (0.14, -lunge * 0.30, 5),
                                     (0.30, lunge, -6), (0.46, lunge * 0.8, -2), (dur, 0, 0)]),
            rotation=_rot(b["rot"], [(0.0, 0), (0.14, 5), (0.30, -11), (0.46, -8), (dur, 0)]),
            scale=_scl(b["scale"], [(0.0, 1, 1), (0.14, 0.96, 1.04), (0.30, 1.06, 0.96),
                                    (0.46, 1.02, 0.99), (dur, 1, 1)]))
    for h in _names(data, "head1"):
        put(h, rotation=_rot(su[h]["rot"],
                             [(0.0, 0), (0.14, 12), (0.30, -20), (0.46, -15), (dur, 0)]))
    for i, a in enumerate(_names(data, "arm", "hand")):
        s = 1 if i % 2 == 0 else -1
        put(a, rotation=_rot(su[a]["rot"],
                             [(0.0, 0), (0.14, s * -18), (0.30, s * 30), (0.48, s * 12), (dur, 0)]))
    for i, m in enumerate(_names(data, "mane", "headmane", "smoke", "wing", "feather")):
        amp = 14 + (i % 4) * 4
        put(m, rotation=_rot(su[m]["rot"],
                             [(0.0, 0), (0.14, amp * 0.4), (0.32, -amp), (0.52, -amp * 0.45),
                              (dur, 0)]))
    for i, t in enumerate(_names(data, "tail")):
        put(t, rotation=_rot(su[t]["rot"],
                             [(0.0, 0), (0.16, 14 + i * 4), (0.34, -12 - i * 3),
                              (0.56, 5), (dur, 0)]))
    for i, bl in enumerate(_names(data, "bell")):
        put(bl, rotation=_rot(su[bl]["rot"],
                             [(0.0, 0), (0.14, -10), (0.30, 26 - i * 2), (0.48, -12),
                              (0.62, 5), (dur, 0)]))
    for i, l in enumerate(_names(data, "leg", "foot")):
        put(l, rotation=_rot(su[l]["rot"],
                             [(0.0, 0), (0.14, 10), (0.30, -14), (0.50, -4), (dur, 0)]))
    return {"length": dur, "tracks": tracks, "slot_tracks": _slot_hold(data)}

def main() -> None:
    dry = "--list" in sys.argv
    for stage in STAGES:
        path = os.path.join(DIR, "%s.json" % stage)
        if not os.path.exists(path):
            print("  [skip] 없음:", path)
            continue
        data = json.load(open(path, encoding="utf-8"))
        anims = data.setdefault("animations", {})
        added = []

        h = SKEL_H.get(stage, 400.0)
        anims["love"] = make_love(data, h)
        added.append("love(%d본)" % len(anims["love"]["tracks"]))

        atk = anims.get("attack")
        if atk is not None and float(atk.get("length", 0.0)) <= 0.001 and atk.get("tracks"):
            anims["attack"] = make_attack_from_pose(data, atk)
            added.append("attack←원본포즈(%d본)" % len(anims["attack"]["tracks"]))
        elif atk is None:
            anims["attack"] = make_attack_288(data, h)
            added.append("attack합성(%d본)" % len(anims["attack"]["tracks"]))

        for an in ("love", "attack"):
            if an in anims:
                close_eyes(anims[an], stage)
        added.append("눈감김(%s)" % (EYE.get(stage, ("?", "-"))[1]))

        print("[%-5s] %s  기준본=%s" % (stage, " + ".join(added), _body_bone(data)))
        if not dry:
            json.dump(data, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    if dry:
        print("(--list: 파일을 쓰지 않았다)")

if __name__ == "__main__":
    main()

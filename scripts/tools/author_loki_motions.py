"""로키(800) 의 **없는 애니메이션을 저작**해 중간 JSON 에 심는다.

왜 필요한가 — 드빌1 로키는 `wait` 와 `att` 밖에 없다. 우리 렌더가 부르는 이름은 두 개다:
  · `love`   동굴 터치 반응 (`cave.gd:2000,2057,2126,4684`) — **다섯 단계 전부 없다**
  · `attack` 콜로세움 평타 (`fight.gd::_play_anim`) — 288(각성)만 없다
    (adult/transcended 는 원본 `att` 를 `build_loki800.ANIM_MAP` 이 `attack` 으로 넘겨 준다)
🟦 사용자 확정 2026-08-04: 전 단계 `love` 제작 · 288 `attack` 은 **파츠로 att 컷 구도 재현**.

## 자작 범위를 좁게 유지하는 방법
안무를 지어내되 **뼈 이름의 의미**로만 움직인다. 다섯 스켈레톤이 같은 규약을 쓴다(실측):
`head1` `ear1/2` `body1/2` `tail1~3` `arm1~4` `mane1` `headmane1/2` `wing1~5` `bell1~6`
`leg1/2` `foot1/2` `smoke1~5`. 없는 뼈는 그냥 건너뛴다 — 스켈레톤마다 다르므로.
루트 아래 **가장 자손이 많은 뼈**를 몸통 기준으로 잡아 전체 바운스를 건다(이름에 의존하지 않음).

## 값 규약
중간 JSON 의 애니 값은 **이미 Godot 공간의 절대값**이다(`spine_export.export` 참조):
rotation = -radians(spine 각) · position = (x, -y) · +y 가 아래. 그래서 여기서는
`bones[]` 의 셋업값을 기준으로 **델타를 더한 절대값**을 적는다.

    python scripts/tools/author_loki_motions.py          # 심기
    python scripts/tools/author_loki_motions.py --list   # 무엇을 심을지만 출력
"""
from __future__ import annotations
import json, math, os, sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(REPO)
DIR = "assets/converted/dragon_800"
STAGES = ["baby", "child", "adult", "aura", "e", "advent"]

D = math.radians          # 도 → 라디안 (Godot 회전값 단위)


# ── 트랙 헬퍼 ────────────────────────────────────────────────────────────────
def _rot(base: float, keys) -> list:
    """[(t, 도), …] → 절대 라디안 키. 셋업 각도에 델타를 더한다."""
    return [[t, base + D(deg), "L"] for t, deg in keys]


def _pos(base, keys) -> list:
    """[(t, dx, dy), …] → 절대 위치 키. dy 는 **Godot 기준(양수가 아래)**."""
    return [[t, [base[0] + dx, base[1] + dy], "L"] for t, dx, dy in keys]


def _scl(base, keys) -> list:
    return [[t, [base[0] * sx, base[1] * sy], "L"] for t, sx, sy in keys]


def _wave(dur, amp, cycles, phase=0.0, steps=8):
    """사인 스윙 키프레임 [(t, 도)…]. 꼬리·갈기의 지연 흔들림에 쓴다."""
    return [(round(dur * i / steps, 4),
             amp * math.sin(2 * math.pi * (cycles * i / steps + phase)))
            for i in range(steps + 1)]


# 몸통 기준 뼈 후보 — 다섯 스켈레톤이 쓰는 이름(실측): e=`bone` adult=`all` aura/child=`ctr`
# baby=`body1`. 자손 수만으로 고르면 child2 가 **`portal1`**(해츨링이 딛고 선 마법진)을 집어
# 마법진까지 함께 통통 튄다 → 이름을 먼저 보고, 없을 때만 자손 수로 떨어진다.
BODY_PREF = ("ctr", "all", "bone", "body1")
# 이름에 이게 들어간 뼈는 몸통 기준에서 제외한다(연출 요소지 몸이 아니다).
FX_BONE = ("portal", "smoke", "feather", "effect", "shadow", "bird")

## 원본 스켈레톤 높이 — 안무 진폭을 크기에 비례시킨다(포팅 카드 §1).
SKEL_H = {"baby": 122.0, "child": 210.0, "adult": 289.0, "aura": 390.0, "e": 798.0,
          "advent": 491.0}


def _body_bone(data: dict) -> str | None:
    """몸통 기준 뼈. 규약 이름 우선, 없으면 루트 아래 자손이 가장 많은 뼈(연출 뼈 제외)."""
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
    """`wait` 의 슬롯 상태를 t=0 한 장으로 굳혀 물려준다.

    저작 애니에 슬롯 트랙이 없으면 **직전 애니가 남긴 표시 상태를 그대로 쓴다.** 288 은
    `att1~3`(통짜 컷)이 동적 슬롯이라, 만약 love 가 먼저 재생되면 거대한 컷이 켜진 채로
    남을 수 있다. wait 의 첫 키를 복사해 두면 어떤 순서로 재생해도 안전하다.
    """
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


# ── 눈 감김 ──────────────────────────────────────────────────────────────────
#
# 🟦 사용자 확정 2026-08-04: **저작 모션(`love`/`attack`)은 눈을 감은 얼굴로 간다.**
# 원본 아틀라스의 eye 리전을 여섯 단계 나란히 뽑아 확인한 규약(자작 그림 아님):
#   `eye1` = 뜬 눈 · `eye2` = 반쯤 감은 눈 · `eye3` = 완전히 감은 눈(속눈썹 호)
#   단 child/adult 는 눈이 **두 개**라 슬롯이 갈린다 — 가까운 눈 슬롯의 감은 변형이 `eye4`,
#   `eye2` 슬롯은 먼 쪽 눈(항상 호 한 줄)이라 건드리지 않는다.
# 원본 `wait` 이 이 파츠들로 이미 눈을 깜빡인다(adult 0.93s·advent 1.10s 지점) → 배선 검증됨.
#
# ⚠️ 원본 `att` 포즈는 눈을 **뜨고** 있다(adult/aura/advent 전부 `eye1`). 즉 이건 원작 재현이
#    아니라 **의도적 변경**이다. 되돌리려면 `main()` 의 `close_eyes` 두 줄만 빼면 된다.
#
# 값 = (뜬 눈 스프라이트, 감은 눈 스프라이트). 이름은 `spine_export` 규약대로
# 다중 attachment 슬롯이면 `<슬롯>__<attachment>`.
EYE = {
    "baby":   ("eye1__eye1", "eye1__eye3"),
    "child":  ("eye1__eye1", "eye1__eye4"),
    "adult":  ("eye1__eye1", "eye1__eye4"),
    "aura":   ("eye1__eye1", "eye1__eye3"),
    "advent": ("eye1__eye1", "eye1__eye3"),
    # 288 은 눈 변형이 attachment 가 아니라 **슬롯 3개**로 갈려 있다(전부 본 `eye1` 에 붙음).
    # 슬롯 이름 `eye1` 이 본 이름과 충돌해 `spine_export` 가 `_slot` 접미사를 붙였다.
    "e":      ("eye1_slot", "eye3"),
}


def close_eyes(anim: dict, stage: str) -> None:
    """저작 모션 내내 눈을 감긴다 — **모션은 그대로 두고 눈 슬롯만** 바꾼다.

    표시(visible)와 색(modulate)을 **둘 다** 잡아야 한다. 288 의 감은 눈 슬롯은 셋업 색이
    alpha 0 이라(원본이 `att`/`wait` 타임라인으로만 켰다) visible 만 켜면 투명한 채로 있다.
    """
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
    """원본 `att` **정지 포즈**를 시간축에 얹어 공격 모션으로 만든다.

    드빌1 로키의 `att` 는 다섯 스켈레톤 전부 **길이 0**이다(실측: adult·transcended·advent 모두
    `dur=0.0`, 뼈는 31~45개가 전부 키됨). 즉 애니가 아니라 **한 장짜리 공격 포즈**이고, 원작
    런타임이 거기로 스냅한 것으로 보인다. 우리 렌더는 `_play_anim` 이 길이를 재서 복귀 타이밍을
    잡으므로 길이 0이면 정지 그림이 된다.

    ⇒ **포즈는 원본 그대로 쓰고 타이밍만 우리가 얹는다.** 자세를 지어내지 않으므로 288 의
    합성 모션(`make_attack_288`)보다 훨씬 원본에 가깝다.
        0.00 기본자세 → 0.06 예비(포즈 반대쪽으로 12%) → 0.18 **원본 att 포즈** →
        0.42 유지 → 0.68 기본자세 복귀
    """
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
            tgt = keys[0][1]                      # 포즈값(절대). 길이 0이라 키가 하나뿐이다.
            if kind == "rotation":
                b = float(base["rot"])
                t = float(tgt)
                # 최단경로 — 절대 라디안이라 그냥 보간하면 한 바퀴 도는 뼈가 생긴다.
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


# ── 안무 ─────────────────────────────────────────────────────────────────────
def make_love(data: dict, skel_h: float) -> dict:
    """터치 반응 — 두 번 통통 뛰며 고개를 끄덕이고 귀·방울·꼬리가 따라 흔들린다.

    로키는 **방울(bell1~6)을 달고 다니는 장난꾸러기**라(원본 파츠 이름) 방울 딸랑임을
    안무의 중심에 둔다. 파츠 의미만 쓰므로 다섯 스켈레톤 어디서도 관절이 안 꺾인다.
    """
    dur = 1.20
    su = _setup(data)
    tracks: dict[str, dict] = {}

    def put(bone, **kw):
        if bone not in su:
            return
        tracks.setdefault(bone, {}).update(kw)

    # ① 몸통 — 2회 바운스 + 착지 스쿼시
    body = _body_bone(data)
    if body and body in su:
        b = su[body]
        hop = skel_h * 0.045                    # 진폭을 스켈레톤 높이에 비례시킨다
        put(body,
            position=_pos(b["pos"], [(0.0, 0, 0), (0.16, 0, -hop), (0.34, 0, 0),
                                     (0.50, 0, -hop * 0.55), (0.66, 0, 0), (dur, 0, 0)]),
            scale=_scl(b["scale"], [(0.0, 1, 1), (0.10, 0.97, 1.05), (0.34, 1.05, 0.95),
                                    (0.46, 1.0, 1.0), (dur, 1, 1)]))

    # ② 머리 — 끄덕임 + 살짝 기울이기
    for h in _names(data, "head1"):
        put(h, rotation=_rot(su[h]["rot"],
                             [(0.0, 0), (0.14, -9), (0.32, 7), (0.52, -4), (0.78, 2), (dur, 0)]))
    # ③ 귀 — 빠른 쫑긋(좌우 반대로)
    for i, e in enumerate(_names(data, "ear")):
        s = 1 if i % 2 == 0 else -1
        put(e, rotation=_rot(su[e]["rot"],
                             [(0.0, 0), (0.10, s * 16), (0.26, s * -9), (0.44, s * 5), (dur, 0)]))
    # ④ 방울 — 딸랑딸랑(각자 조금씩 어긋나게)
    for i, bl in enumerate(_names(data, "bell")):
        put(bl, rotation=_rot(su[bl]["rot"], _wave(dur, 13 - i, 2.5, phase=i * 0.17)))
    # ⑤ 꼬리 — 마디마다 지연시켜 채찍처럼
    for i, t in enumerate(_names(data, "tail")):
        put(t, rotation=_rot(su[t]["rot"], _wave(dur, 9 + i * 3, 1.5, phase=-0.12 * i)))
    # ⑥ 갈기·연기·날개 — 몸을 늦게 따라오는 관성
    for i, m in enumerate(_names(data, "mane", "headmane", "smoke", "wing", "feather")):
        put(m, rotation=_rot(su[m]["rot"], _wave(dur, 5 + (i % 3) * 2, 1.0, phase=-0.2)))
    # ⑦ 앞다리 — 살짝 들었다 놓기
    for i, a in enumerate(_names(data, "arm", "hand")):
        s = 1 if i % 2 == 0 else -1
        put(a, rotation=_rot(su[a]["rot"],
                             [(0.0, 0), (0.18, s * 10), (0.40, s * -5), (dur, 0)]))
    return {"length": dur, "tracks": tracks, "slot_tracks": _slot_hold(data)}


def make_attack_288(data: dict, skel_h: float) -> dict:
    """288(각성)의 공격 — 원본 `att1~3` 컷 **구도**를 파츠로 재현한다.

    컷을 읽어 보면 셋 다 같은 골자다(`docs/ref/porting/DragonLoki800.md` §4):
    몸을 뒤로 당겼다가 **앞으로 낮게 파고들며 머리를 내밀고**, 앞발을 휘두르고,
    갈기·연기가 뒤로 길게 쓸린다. 그대로 4박으로 옮긴다.
      0.00~0.14 예비동작(뒤로 당김)  0.14~0.32 돌진·타격  0.32~0.46 유지  0.46~0.75 복귀
    """
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
        # 원작 컷의 전진 거리감. 288(798) 에서 34px 이 보기 좋아 그 비율을 유지한다.
        lunge = skel_h * (34.0 / 798.0)
        put(body,
            position=_pos(b["pos"], [(0.0, 0, 0), (0.14, -lunge * 0.30, 5),
                                     (0.30, lunge, -6), (0.46, lunge * 0.8, -2), (dur, 0, 0)]),
            rotation=_rot(b["rot"], [(0.0, 0), (0.14, 5), (0.30, -11), (0.46, -8), (dur, 0)]),
            scale=_scl(b["scale"], [(0.0, 1, 1), (0.14, 0.96, 1.04), (0.30, 1.06, 0.96),
                                    (0.46, 1.02, 0.99), (dur, 1, 1)]))
    # 머리 — 당겼다가 앞으로 내지른다(컷의 핵심)
    for h in _names(data, "head1"):
        put(h, rotation=_rot(su[h]["rot"],
                             [(0.0, 0), (0.14, 12), (0.30, -20), (0.46, -15), (dur, 0)]))
    # 앞발 — 후려치기
    for i, a in enumerate(_names(data, "arm", "hand")):
        s = 1 if i % 2 == 0 else -1
        put(a, rotation=_rot(su[a]["rot"],
                             [(0.0, 0), (0.14, s * -18), (0.30, s * 30), (0.48, s * 12), (dur, 0)]))
    # 갈기·연기·날개 — 돌진 반대로 길게 쓸린다
    for i, m in enumerate(_names(data, "mane", "headmane", "smoke", "wing", "feather")):
        amp = 14 + (i % 4) * 4
        put(m, rotation=_rot(su[m]["rot"],
                             [(0.0, 0), (0.14, amp * 0.4), (0.32, -amp), (0.52, -amp * 0.45),
                              (dur, 0)]))
    # 꼬리 — 반동
    for i, t in enumerate(_names(data, "tail")):
        put(t, rotation=_rot(su[t]["rot"],
                             [(0.0, 0), (0.16, 14 + i * 4), (0.34, -12 - i * 3),
                              (0.56, 5), (dur, 0)]))
    # 방울 — 타격 순간 크게 튄다
    for i, bl in enumerate(_names(data, "bell")):
        put(bl, rotation=_rot(su[bl]["rot"],
                             [(0.0, 0), (0.14, -10), (0.30, 26 - i * 2), (0.48, -12),
                              (0.62, 5), (dur, 0)]))
    # 뒷다리 — 박차기
    for i, l in enumerate(_names(data, "leg", "foot")):
        put(l, rotation=_rot(su[l]["rot"],
                             [(0.0, 0), (0.14, 10), (0.30, -14), (0.50, -4), (dur, 0)]))
    return {"length": dur, "tracks": tracks, "slot_tracks": _slot_hold(data)}


# ═════════════════════════════════════════════════════════════════════════════
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
        anims["love"] = make_love(data, h)       # 다섯 단계 전부
        added.append("love(%d본)" % len(anims["love"]["tracks"]))

        # 공격 모션 — 원본 `att` 포즈가 있으면 **그 포즈를 시간축에 얹고**(원본 우선),
        # 아예 없으면(288: att1~3 은 파츠 포즈가 아니라 통짜 컷 교체다) 파츠로 합성한다.
        atk = anims.get("attack")
        if atk is not None and float(atk.get("length", 0.0)) <= 0.001 and atk.get("tracks"):
            anims["attack"] = make_attack_from_pose(data, atk)
            added.append("attack←원본포즈(%d본)" % len(anims["attack"]["tracks"]))
        elif atk is None:
            anims["attack"] = make_attack_288(data, h)
            added.append("attack합성(%d본)" % len(anims["attack"]["tracks"]))

        # 🟦 저작 모션은 눈을 감은 얼굴로 (원본 `att` 는 뜬 눈 — 의도적 변경, `EYE` 주석 참조)
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

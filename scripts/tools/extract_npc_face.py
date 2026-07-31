"""NpcManager::setTarget 에서 **NPC 얼굴 파츠 위치**를 추출 → `data/npc_face.json`.

원작 `NpcManager` 는 몸통(`npc/<name>/body_<n>.png`, 앵커 0.5/0)에 눈·입 스프라이트를 얹는다.
그 좌표는 **libgame.so 에 NPC별·표정별로 하드코딩**돼 있다(InfoNpc 인스턴스의 필드에 대입).

    +0x150 = 눈 위치   (setNpcEye  가 읽는다 — NpcManager.c setNpcEye  본문)
    +0x15c = 입 위치   (setNpcMouse 가 읽는다 — NpcManager.c setNpcMouse 본문)
    +0x168 = 오른팔 · +0x174 = 왼팔 (셔플 대상 아님 — 여기선 추출만)

디컴프 형태(예: pino, 표정 1):

    local_330 = 0x42a40000;                        // x = 82.0
    local_32c = *(float *)(lVar12 + 4) + -67.0;    // y = bodyH - 67
    CCPoint::operator=((CCPoint *)(lVar20 + 0x150),(CCPoint *)&local_330);

⚠️ 좌표계: Cocos **포인트** 공간(픽셀 아님), 몸통 로컬, 원점 좌하단, y-up.
   `bodyH` 는 몸통 스프라이트의 contentSize.height(포인트) 다.
   → 우리 쪽 변환은 `Design.ASSET_SCALE`(4/3) 로 나눠 픽셀로 되돌린다(§9).

일부 분기는 `local_12c = local_134 * 5.0 + *(float *)(lVar12 + 4);` 처럼 **화면 밖으로 치우는**
(= 그 표정에서 그 파츠를 안 그리는) 코드다 → `null` 로 표기한다.

사용: python scripts/tools/extract_npc_face.py [--check]
"""
from __future__ import annotations

import json
import re
import struct
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SRC = REPO / "docs" / "ref" / "orig_code" / "decomp" / "NpcManager.c"
OUT = REPO / "data" / "npc_face.json"

SLOT = {0x150: "eye", 0x15C: "mouth", 0x168: "arm_r", 0x174: "arm_l"}

# ── 눈맞춤 보정(디자인 px) ────────────────────────────────────────────────
# 추출한 좌표는 **원작 값 그대로**다. 그런데 몇몇 NPC 는 우리 몸통 프레임과 원작 contentSize
# 기준이 달라 파츠가 어긋난다(몸통 그림에 이미 눈이 그려져 있으면 눈이 네 개로 보인다).
# 그런 것만 여기서 밀어 준다 — **원작 좌표는 건드리지 않는다**.
#   pong: 사용자 실측 2026-07-31 "오른쪽 30, 아래 55" → 스크린샷 재실측 세로 +50 →
#         사용자 재확인 세로 -15 → 가로 +4 → 가로 -1. 단위 = **디자인 px**.
NUDGE = {
    "pong": [35.0, 90.0],
}

# --- 디컴프 토큰 ---------------------------------------------------------
# 이름 비교: 4글자는 int32, 8글자는 int64 상수 비교, 그 외는 memcmp 리터럴
RE_NAME_INT = re.compile(r"\*\(int \*\)pbVar\d+ == (0x[0-9a-f]+)")
RE_NAME_LONG = re.compile(r"\*\(long \*\)pbVar\d+ == (0x[0-9a-f]+)")
# ⚠️ Ghidra 는 같은 비교를 **부등호로 뒤집어** 내기도 한다:
#       if (*(int *)pbVar16 != 0x676e6f70) { …다른 NPC… } else { …그 NPC 좌표… }
#    이때 그 NPC 의 블록은 **else 쪽**이다. `==` 만 받던 종전 패턴은 이 형태를 통째로 놓쳐
#    `pong`(임프상인)·`pino` 같은 NPC 가 npc_face.json 에서 빠져 있었다 — 얼굴 파츠가
#    아예 안 그려지던 원인(2026-07-31 수정).
RE_NAME_INT_NE = re.compile(r"\*\(int \*\)pbVar\d+ != (0x[0-9a-f]+)")
RE_NAME_LONG_NE = re.compile(r"\*\(long \*\)pbVar\d+ != (0x[0-9a-f]+)")
# ⚠️ 길이 인자는 10 이상이면 Ghidra 가 **16진수**로 낸다(`,0xb)` `,0xc)` …).
#    `\d+` 만 받던 종전 패턴은 그 블록들을 통째로 놓쳐, 앞선 **짧은 이름 NPC 가 뒤따르는
#    10글자 이상 NPC 들의 좌표를 전부 흡수**했다. 실제 사고: mamorudic(9자)이 ghostpirate·
#    nuri_hanbok·ghostcaptain … 의 좌표까지 자기 표정 1·3 으로 물고 있었다
#    (얼굴 파츠가 어깨에 붙어 보이던 원인). 2026-07-29 수정.
RE_NAME_MEM = re.compile(r'memcmp\(pbVar\d+,"([a-z_0-9]+)",(?:\d+|0x[0-9a-fA-F]+)\)')
# 표정 index — `switch(*(uint *)pNVar19)` + `case N:` 또는 직접 비교.
# ⚠️ Ghidra 가 `if (1 < uVar6 - 3)` 같은 범위 비교로 접어 놓은 분기는 복원되지 않는다 →
#    그런 블록은 표정을 "?" 로 남기고, 아래에서 표정 미상 풀에 넣는다.
RE_EMO_SWITCH = re.compile(r"switch\(\*\(uint \*\)pNVar\d+\)")
RE_EMO_CASE = re.compile(r"^\s*case (\d+):")
RE_EMO_EQ = re.compile(r"\*\(uint \*\)pNVar\d+ == (\d+)")
# 좌표 대입
RE_X_HEX = re.compile(r"^\s*(local_[0-9a-f]+) = (0x[0-9a-f]+|0);\s*$")
RE_Y_OFF = re.compile(r"^\s*(local_[0-9a-f]+) = \*\(float \*\)\(lVar\d+ \+ 4\) \+ (-?[\d.]+);\s*$")
RE_Y_HIDE = re.compile(r"^\s*(local_[0-9a-f]+) = local_[0-9a-f]+ \* [\d.]+ \+ \*\(float \*\)\(lVar\d+ \+ 4\);\s*$")
RE_ASSIGN = re.compile(r"CCPoint::operator=\(\(CCPoint \*\)\(lVar\d+ \+ (0x1[0-9a-f]{2})\),\(CCPoint \*\)&(local_[0-9a-f]+)\)")


def baked_face_bodies(coords: dict) -> list[str]:
    """눈·입을 **얹으면 안 되는** 몸통 프레임 목록(`"<npc>:<body번호>"`).

    🔴 2026-08-01 (사용자 신고 "표정이 얼굴에 겹쳐 보인다"): 원작 1화 첫 줄은 실제로
       `setTalker(..., body=2, state=2)` 라 **nuri 의 body_2** 를 쓴다. 그런데 그 프레임은
       팔을 든 전용 포즈이고 **눈이 이미 그려져 있다**. 거기에 눈 파츠를 또 얹으니 뜬 눈과
       감은 눈이 겹쳤다.

    원작은 이 구분을 `InfoNpc`(로컬 SQLite `info_npc`)에서 읽었는데 그 DB 는 유실이다.
    그래서 **자산에서 직접 판정**한다. 두 단계 다 필요하다:

      ① 머리 영역(상단 35%)을 body_1 과 최적 정렬 — 15개 중 13개가 **잔차 0.0**,
         즉 대체 몸통은 대개 머리를 그대로 두고 팔·소품만 바꾼 것이라 body_1 좌표가 그대로 맞는다.
      ② 정렬된 위치의 **눈 상자 어두움**(선화 픽셀 비율)을 body_1 과 비교.
         얼굴이 그려져 있으면 눈동자·속눈썹 때문에 확 뛴다.

    실측(전체 15개 대체 몸통): nuri body_2 만 0.030 → 0.134 로 걸린다.
    yulia body_5 는 머리가 조금 움직였지만(잔차 24.8) 얼굴은 비어 있어(0.079 → 0.043)
    통과한다 — ①만으로 잘랐으면 얼굴 없는 유리아가 됐을 자리다.
    """
    try:
        from PIL import Image, ImageChops
    except ImportError:
        print("[npc_face] Pillow 없음 — 몸통 얼굴 판정 생략")
        return []
    conv = REPO / "assets" / "converted"
    S = 4 / 3

    def body_img(d: Path, key: str):
        t = d / f"{key}.tres"
        if not t.exists():
            return None
        txt = t.read_text(encoding="utf-8")
        m = re.search(r"Rect2\(([\d.]+), ([\d.]+), ([\d.]+), ([\d.]+)\)", txt)
        pg = re.search(r'/([^"/]+\.png)"', txt)
        if not m or not pg:
            return None
        im = Image.open(d / pg.group(1)).convert("RGBA")
        x, y, w, h = (float(v) for v in m.groups())
        return im.crop((int(x), int(y), int(x + w), int(y + h)))

    def darkness(img, box) -> float:
        px = [p for p in img.crop(box).get_flattened_data() if p[3] > 120]
        if not px:
            return 0.0
        return sum(1 for p in px if (p[0] + p[1] + p[2]) / 3 < 100) / len(px)

    baked: list[str] = []
    for d in sorted(conv.glob("npc_*")):
        mf = d / "_manifest.json"
        if not d.is_dir() or not mf.exists():
            continue
        npc = d.name[4:]
        man = json.loads(mf.read_text(encoding="utf-8"))
        bodies = sorted((k for k in man if re.fullmatch(rf"npc_{npc}_body_\d+", k)),
                        key=lambda s: int(s.split("_")[-1]))
        per = coords.get(npc, {})
        fp = per.get("1") or per.get("?") or (list(per.values())[0] if per else None)
        if len(bodies) < 2 or not fp or not fp.get("eye"):
            continue
        b1 = body_img(d, bodies[0])
        if b1 is None:
            continue
        ex, ey = fp["eye"][0] / S, fp["eye"][1] / S
        ew = man.get(f"npc_{npc}_eye_1_1", {}).get("w", 60)
        box = (int(ex), int(ey), int(ex + ew), int(ey) + 26)
        base = darkness(b1, box)
        h1 = b1.crop((0, 0, b1.width, int(b1.height * 0.35))).convert("L")
        for bk in bodies[1:]:
            bn = body_img(d, bk)
            if bn is None:
                continue
            hn = bn.crop((0, 0, bn.width, int(bn.height * 0.35))).convert("L")
            best = (9e9, 0, 0)
            for dy in range(-16, 17, 2):
                for dx in range(-16, 17, 2):
                    a = ImageChops.offset(hn, dx, dy)
                    w = min(h1.width, a.width)
                    hh = min(h1.height, a.height)
                    diff = ImageChops.difference(h1.crop((0, 0, w, hh)), a.crop((0, 0, w, hh)))
                    s = sum(diff.get_flattened_data()) / (w * hh)
                    if s < best[0]:
                        best = (s, dx, dy)
            _, dx, dy = best
            got = darkness(bn, (box[0] - dx, box[1] - dy, box[2] - dx, box[3] - dy))
            if got > base * 1.8 + 0.05:
                baked.append("%s:%s" % (npc, bk.split("_")[-1]))
    return baked


def f32(hexstr: str) -> float:
    v = int(hexstr, 16) & 0xFFFFFFFF
    return round(struct.unpack("<f", struct.pack("<I", v))[0], 3)


def int_to_name(hexstr: str, width: int) -> str:
    """리틀엔디언 정수 상수 → 이름 문자열(4글자=int32, 8글자=int64)."""
    v = int(hexstr, 16)
    raw = struct.pack("<Q" if width == 8 else "<I", v & (2 ** (width * 8) - 1))
    return raw.decode("ascii", "replace")


def slice_set_target(text: str) -> str:
    """setTarget 본문(**가장 큰** 정의)만 잘라낸다.

    🔴 2026-07-31 수정: 종전엔 `cocos2d::NpcManager::setTarget` **텍스트의 마지막 등장**부터
    잘랐다. 그런데 이 파일에는 같은 이름의 정의가 여럿 있고(16바이트 thunk + 인라인 사본),
    마지막 등장이 **18,144바이트 본문이 아니었다.** 그래서 실제 표를 못 읽고 사본을 읽고
    있었다 — `pong`(임프상인) 이 통째로 빠져 있던 원인이다.
    이제 `/* ==== setTarget @ addr (size=N) ==== */` 마커에서 **size 가 가장 큰 것**을 고른다.
    """
    marks = [(m.start(), m.group(1), int(m.group(2)))
             for m in re.finditer(r"/\* ==== (\w+) @ [0-9a-f]+ \(size=(\d+)\) ==== \*/", text)]
    best = None
    for i, (pos, name, size) in enumerate(marks):
        if name != "setTarget":
            continue
        end = marks[i + 1][0] if i + 1 < len(marks) else len(text)
        if best is None or size > best[2]:
            best = (pos, end, size)
    if best is None:
        raise SystemExit("setTarget 정의를 찾지 못했다")
    body = text[best[0]:best[1]]
    # ⚠️ Ghidra 주석 안에도 중괄호가 있다(`/* try { // ... */`) → else/깊이 추적이 망가진다.
    #    주석을 **같은 길이의 공백**으로 지운다(줄 번호·컬럼 보존).
    body = re.sub(r"/\*.*?\*/", lambda m: " " * len(m.group(0)), body, flags=re.S)
    body = re.sub(r"//[^\n]*", lambda m: " " * len(m.group(0)), body)
    return body


def main() -> int:
    body = slice_set_target(SRC.read_text(encoding="utf-8", errors="replace"))
    lines = body.splitlines()

    # local 변수명 → 마지막으로 대입된 x(hex) / y(offset from bodyH)
    xs: dict[str, float] = {}
    ys: dict[str, float | None] = {}
    cur_name: str | None = None
    cur_emo: int | None = None
    out: dict[str, dict[str, dict[str, list[float] | None]]] = {}

    in_switch = False
    # `!= 이름` 으로 열린 if 를 추적한다 — 그 if 가 닫히고 나오는 `else` 블록이 그 NPC 것이다.
    #   pending[(depth)] = 이름
    pending_ne: dict[int, str] = {}
    depth = 0
    for ln in lines:
        for rx, width in ((RE_NAME_INT_NE, 4), (RE_NAME_LONG_NE, 8)):
            m = rx.search(ln)
            if m:
                nm = int_to_name(m.group(1), width)
                if nm.isalnum():
                    pending_ne[depth] = nm
        # `}` 로 닫힌 뒤 같은 깊이에서 else 를 만나면 그 이름으로 전환한다.
        if re.match(r"^\s*else\s*\{?\s*$", ln) and depth in pending_ne:
            cur_name, cur_emo, in_switch = pending_ne.pop(depth), None, False
        depth += ln.count("{") - ln.count("}")
        for rx, width in ((RE_NAME_INT, 4), (RE_NAME_LONG, 8)):
            m = rx.search(ln)
            if m:
                nm = int_to_name(m.group(1), width)
                if nm.isalnum():
                    cur_name, cur_emo, in_switch = nm, None, False
        m = RE_NAME_MEM.search(ln)
        if m:
            cur_name, cur_emo, in_switch = m.group(1), None, False
        if RE_EMO_SWITCH.search(ln):
            in_switch = True
        m = RE_EMO_CASE.match(ln)
        if m and in_switch:
            cur_emo = int(m.group(1))
        m = RE_EMO_EQ.search(ln)
        if m:
            cur_emo = int(m.group(1))

        m = RE_X_HEX.match(ln)
        if m:
            xs[m.group(1)] = f32(m.group(2))
            continue
        m = RE_Y_OFF.match(ln)
        if m:
            # local_XXX 의 y 는 x 보다 4바이트 뒤 → 이름이 다르다. 소유 CCPoint 는 (addr-4).
            ys[m.group(1)] = float(m.group(2))
            continue
        m = RE_Y_HIDE.match(ln)
        if m:
            ys[m.group(1)] = None
            continue

        m = RE_ASSIGN.search(ln)
        if m and cur_name:
            slot = SLOT.get(int(m.group(1), 16))
            pt = m.group(2)                     # CCPoint 변수(= x 필드)
            if slot is None:
                continue
            # y 필드는 같은 CCPoint 의 +4 → 디컴프 변수명은 (주소-4)... 로 나온다.
            addr = int(pt.split("_")[1], 16)
            ykey = "local_%x" % (addr - 4)
            if pt not in xs:
                continue
            y = ys.get(ykey, 0.0)
            per = out.setdefault(cur_name, {}).setdefault(str(cur_emo or "?"), {})
            per[slot] = None if y is None else [xs[pt], round(-y, 3)]

    # 정렬 + 메타
    doc = {
        "_source": "docs/ref/orig_code/decomp/NpcManager.c :: NpcManager::setTarget (libgame.so 하드코딩)",
        "_nudge_note": ("nudge = 우리 몸통 프레임 기준과 원작 contentSize 기준이 달라 어긋나는 "
                        "NPC 만 눈으로 맞춘 보정값(**디자인 px**). 원작 좌표(npc)는 손대지 않는다."),
        "nudge": NUDGE,
        "_note": (
            "몸통(body_N, 앵커 0.5/0) 로컬 **포인트** 좌표. y 는 몸통 상단에서 아래로 내려간 거리"
            "(원작 표현 bodyH - N 을 N 으로 저장). null = 그 표정에서 화면 밖으로 치움(=미표시)."
        ),
        "_slots": {"eye": "+0x150 setNpcEye", "mouth": "+0x15c setNpcMouse",
                   "arm_r": "+0x168", "arm_l": "+0x174"},
        "npc": {k: dict(sorted(v.items())) for k, v in sorted(out.items())},
        "_baked_face_note": (
            "얼굴이 이미 그려진 전용 포즈 몸통 — 눈·입을 얹으면 표정이 겹친다. "
            "원작 판정은 InfoNpc(로컬 SQLite, 유실)에 있어 자산에서 측정한다: "
            "body_1 과 머리 정렬 후 눈 상자 선화 비율이 1.8배+0.05 이상이면 '있음'. "
            "판정기 = baked_face_bodies()."
        ),
        "baked_face": baked_face_bodies(out),
    }

    if "--check" in sys.argv:
        print(json.dumps(doc["npc"], ensure_ascii=False, indent=1)[:4000])
        print("... npc 수:", len(out))
        return 0

    OUT.write_text(json.dumps(doc, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"[npc_face] {len(out)}종 → {OUT.relative_to(REPO)}")
    for k in sorted(out):
        print("  ", k, {e: sorted(s) for e, s in sorted(out[k].items())})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

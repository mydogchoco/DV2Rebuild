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

# --- 디컴프 토큰 ---------------------------------------------------------
# 이름 비교: 4글자는 int32, 8글자는 int64 상수 비교, 그 외는 memcmp 리터럴
RE_NAME_INT = re.compile(r"\*\(int \*\)pbVar\d+ == (0x[0-9a-f]+)")
RE_NAME_LONG = re.compile(r"\*\(long \*\)pbVar\d+ == (0x[0-9a-f]+)")
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


def f32(hexstr: str) -> float:
    v = int(hexstr, 16) & 0xFFFFFFFF
    return round(struct.unpack("<f", struct.pack("<I", v))[0], 3)


def int_to_name(hexstr: str, width: int) -> str:
    """리틀엔디언 정수 상수 → 이름 문자열(4글자=int32, 8글자=int64)."""
    v = int(hexstr, 16)
    raw = struct.pack("<Q" if width == 8 else "<I", v & (2 ** (width * 8) - 1))
    return raw.decode("ascii", "replace")


def slice_set_target(text: str) -> str:
    """setTarget 본문(가장 큰 정의)만 잘라낸다."""
    marks = [m.start() for m in re.finditer(r"cocos2d::NpcManager::setTarget", text)]
    if not marks:
        raise SystemExit("setTarget 정의를 찾지 못했다")
    start = marks[-1]
    end = text.find("/* ==== ", start + 10)
    return text[start:end if end > 0 else len(text)]


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
    for ln in lines:
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
        "_note": (
            "몸통(body_N, 앵커 0.5/0) 로컬 **포인트** 좌표. y 는 몸통 상단에서 아래로 내려간 거리"
            "(원작 표현 bodyH - N 을 N 으로 저장). null = 그 표정에서 화면 밖으로 치움(=미표시)."
        ),
        "_slots": {"eye": "+0x150 setNpcEye", "mouth": "+0x15c setNpcMouse",
                   "arm_r": "+0x168", "arm_l": "+0x174"},
        "npc": {k: dict(sorted(v.items())) for k, v in sorted(out.items())},
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

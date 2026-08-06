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
#   ⚠️ 2026-08-04 — `pong` 보정을 **뺐다.** 그 값은 pong 이 **arnold 의 좌표를 물고 있던**
#      상태에서 화면을 보고 맞춘 것이라, 이름 귀속을 고친 지금은 근거가 없다.
#      원작 pong = 표정 1 에 눈 (149,142) · **입 없음**(원작이 화면 밖으로 치운다).
#      임프상인 초상이 어긋나 보이면 그때 다시 실측해서 여기 적는다.
#
# 형식 두 가지 (둘 다 **디자인 px**):
#   "<npc>": [dx, dy]                          NPC 전체(모든 포즈·눈·입)
#   "<npc>": {"body_<n>": {"<슬롯>": [dx, dy]}} 포즈·슬롯별. `"*"` 는 모든 포즈/슬롯.
# 원작 좌표(`npc`)는 어느 쪽도 건드리지 않는다.
NUDGE: dict[str, object] = {
    # 유리아 **정면 포즈**(body_5 — 팔짱 낀 정면. body_1 은 3/4 측면이다)의 입만
    # 오른쪽 5 · 아래 5. 사용자 실측 2026-08-04.
    "yulia": {"body_5": {"mouth": [5.0, 5.0]}},
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
RE_NAME_MEM = re.compile(r'(\w+) = memcmp\(pbVar\d+,"([a-z_0-9]+)",(?:\d+|0x[0-9a-fA-F]+)\)')
# ⚠️ memcmp 도 **뒤집혀** 나온다. 게다가 int/long 형태와 달리 `else` 가 아니라
#    **블록이 닫힌 뒤 그냥 이어지는**(fall-through) 모양이라 `else` 만 보던 종전 코드는 못 잡았다:
#
#       iVar5 = memcmp(pbVar16,"jimon",5);
#       if (iVar5 != 0) { …dilis·aidra·mirba·annie·garon… }   ← 다른 NPC 들
#       pVVar11 = (VisibleRect *)0x0;
#       switch(*(uint *)pNVar19) { case 1: … }                 ← **여기가 jimon**
#
#    그래서 jimon(즈믄)·worldcup_dealer 가 npc_face.json 에서 통째로 빠져 있었고, 그 좌표는
#    직전 이름(garon 등)이 물고 있었다. ⇒ `if (VAR != 0) {` 의 블록이 **닫히는 순간**
#    그 이름으로 전환한다(else 형태도 같은 지점이라 둘 다 걸린다). 2026-08-01 수정.
RE_MEM_NE = re.compile(r"^\s*if \((\w+) != 0\) \{")
RE_MEM_EQ = re.compile(r"^\s*if \((\w+) == 0\) \{")
# 표정 index — `switch(*(uint *)pNVar19)` + `case N:` 또는 직접 비교.
# ⚠️ Ghidra 가 `if (1 < uVar6 - 3)` 같은 범위 비교로 접어 놓은 분기는 복원되지 않는다 →
#    그런 블록은 표정을 "?" 로 남기고, 아래에서 표정 미상 풀에 넣는다.
RE_EMO_SWITCH = re.compile(r"switch\(\*\(uint \*\)pNVar\d+\)")
RE_EMO_CASE = re.compile(r"^\s*case (\d+):")
RE_EMO_EQ = re.compile(r"\*\(uint \*\)pNVar\d+ == (\d+)")
# 🔴 2026-08-01: Ghidra 가 표정 인자를 **지역변수에 먼저 담는** NPC 가 있다.
#     uVar6 = *(uint *)pNVar19;   ← 여기서 변수 이름을 잡고
#     if (uVar6 == 2) { … }       ← 이 형태를 표정 분기로 인정한다
# 이걸 못 읽어서 nuri 가 표정별 좌표를 통째로 잃고 `"?"` 한 벌만 남았다. 그 결과
# **표정 2 = 눈을 화면 밖으로 치우고(=몸통에 이미 그려져 있다) 입만 (131,170) 에 찍는다**
# 는 원작 규칙이 사라져, 얼굴이 그려진 body_2 위에 눈이 겹쳐 보였다(사용자 신고).
RE_EMO_VAR = re.compile(r"^\s*(uVar\d+) = \*\(uint \*\)pNVar\d+;")
RE_EMO_VAR_EQ = re.compile(r"\((uVar\d+) == (\d+)\)")
# 🔴 2026-08-04 (사용자 신고 "아놀드의 눈이 화내는 표정에서만 제자리"): 표정을 **비트마스크
#    집합**으로 가르는 NPC 가 있다. Ghidra 가 switch 를 이렇게 낮춘다:
#        uVar3 = 1 << (ulong)(uVar6 & 0x1f);   ← uVar6 = 표정
#        if ((uVar3 & 0x34) != 0) { … }        ← 표정 {2,4,5}
#        if ((uVar3 & 0xc2) == 0) { … } else { … }   ← else 쪽이 표정 {1,6,7}
#    한 벌이 아니라 **여러 표정**이라 `cur_emo` 하나로는 못 담는다 → 집합으로 쓴다.
#    arnold 실측: {2,4,5}·{1,6,7} 은 눈 y=-53, 표정 3 만 -36. 종전엔 표정 3 값 하나가
#    `"?"` 로 저장돼 **나머지 여섯 표정의 눈이 17pt(화면 ~23px) 위로 떠 있었다.**
RE_EMO_SHIFT = re.compile(r"^\s*(uVar\d+) = 1 << \(ulong\)\((uVar\d+) & 0x1f\);")
RE_EMO_MASK = re.compile(r"\((uVar\d+) & (0x[0-9a-f]+)\) (!=|==) 0\)")
## ⚠️ `if (uVar6 != 1) break;` 뒤에 이어지는 갈래(eden 의 표정 1)는 **아직 못 읽는다.**
##    그 형태를 표정 분기로 인정해 봤더니 eden 은 그대로였고 pino 의 기본 갈래가 깨졌다
##    (표정 가드가 아니라 이름 블록 경계가 어긋난 게 원인이라 여기서 고칠 문제가 아니다).
##    ⇒ eden 표정 1 좌표는 부정확한 채로 남는다(원작 값 = 눈 278/97 · 입 249/147).
# 좌표 대입
RE_X_HEX = re.compile(r"^\s*(local_[0-9a-f]+) = (0x[0-9a-f]+|0);\s*$")
RE_Y_OFF = re.compile(r"^\s*(local_[0-9a-f]+) = \*\(float \*\)\(lVar\d+ \+ 4\) \+ (-?[\d.]+);\s*$")
# ⚠️ 배수를 담는 변수는 `local_134` 만이 아니다 — Ghidra 가 한 번 `fVar29 = local_134;` 로
#    옮겨 담고 `fVar29 * 5.0` 을 쓰는 갈래가 있다(ghostpiratehead 표정 1 = 눈·입 **둘 다** 치움).
#    `local_` 만 받던 종전 패턴은 그 눈을 "치움(null)" 이 아니라 y=0 좌표로 읽었다.
RE_Y_HIDE = re.compile(r"^\s*(local_[0-9a-f]+) = (?:local_[0-9a-f]+|fVar\d+) \* [\d.]+ \+ \*\(float \*\)\(lVar\d+ \+ 4\);\s*$")
# ⚠️ 줄바꿈을 합치고 나면 닫는 괄호 앞에 공백이 남는다(`&local_488 );`) → `\s*` 필수.
RE_ASSIGN = re.compile(r"CCPoint::operator=\(\(CCPoint \*\)\(lVar\d+ \+ (0x1[0-9a-f]{2})\),\(CCPoint \*\)&(local_[0-9a-f]+)\s*\)")


def join_wrapped(lines: list[str]) -> list[str]:
    """줄바꿈된 `CCPoint::operator=(…)` 문장을 한 줄로 합친다.

    🔴 2026-08-01 (사용자 신고 "입 파츠가 없는 경우가 있다"): Ghidra 는 긴 대입을 이렇게 접는다.

        pVVar11 = (VisibleRect *)
                  CCPoint::operator=((CCPoint *)(lVar20 + 0x15c),(CCPoint *)&local_488
                                    );

    `RE_ASSIGN` 은 `&local_NNN)` 까지 한 줄에 있어야 맞으므로 이 형태를 통째로 놓쳤다.
    **하필 접히는 쪽이 대개 두 번째 대입 = 입(+0x15c)** 이라, 그 표정만 눈은 있고 입이 없었다
    (실측: dieros 표정 4). 브레이스를 그대로 안고 합치므로 깊이 계산에는 영향이 없다.
    """
    ## 접히는 형태가 둘이라 **문장 끝(`;`)** 을 기준으로 삼는다. 닫는 괄호(`);`)를 찾으면
    ## 되겠거니 했다가 `… &local_128)` + 다음 줄 `;` 형태에서 버퍼가 뒷줄을 계속 삼켰다.
    out: list[str] = []
    buf = ""
    held = 0
    for ln in lines:
        if buf:
            buf += " " + ln.strip()
            held += 1
            if buf.rstrip().endswith(";") or held > 4:
                out.append(buf)
                buf, held = "", 0
            continue
        if "CCPoint::operator=(" in ln and not ln.rstrip().endswith(";"):
            buf, held = ln.rstrip(), 0
            continue
        out.append(ln)
    if buf:
        out.append(buf)
    return out


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
    lines = join_wrapped(body.splitlines())

    # local 변수명 → 마지막으로 대입된 x(hex) / y(offset from bodyH)
    xs: dict[str, float] = {}
    ys: dict[str, float | None] = {}
    cur_name: str | None = None
    cur_emo: int | None = None
    out: dict[str, dict[str, dict[str, list[float] | None]]] = {}

    in_switch = False
    emo_var: str | None = None       # 표정 인자를 담은 지역변수(`uVar6 = *(uint *)pNVar19`)
    emo_depth: int | None = None     # 그 표정 if 블록이 열린 깊이
    # `!= 이름` 으로 열린 if 를 추적한다 — 그 if 가 닫히고 나오는 `else` 블록이 그 NPC 것이다.
    #   pending[(depth)] = 이름
    pending_ne: dict[int, str] = {}
    # `iVarN = memcmp(…,"name",…)` 의 결과 변수 → 이름. 바로 다음 줄의 `if (iVarN != 0) {` 를
    # 만나면 (블록 안 깊이, 이름) 으로 옮겨 담았다가 **그 블록이 닫힐 때** 그 이름으로 전환한다.
    mem_var: tuple[str, str] | None = None
    ne_after: list[tuple[int, str]] = []
    depth = 0
    shift_var: str | None = None      # `uVar3 = 1 << (uVar6 & 0x1f)` 의 좌변
    mask_emos: list[int] | None = None
    mask_depth: int | None = None
    mask_else: tuple[int, list[int], str | None] | None = None  # (깊이, 표정 집합, 소유 NPC)
    def _else_follows(i: int) -> bool:
        """`lines[i]` 의 `{` 블록이 닫힌 직후 `else` 가 오는가.

        🔴 int/long `!=` 는 두 모양이 섞여 있다 — `else` 형(pong)과 fall-through 형(florence).
           런타임 깊이 추적만으로 가르려다 서로를 가로채는 사고를 네 번 냈다.
           **앞을 미리 읽어** 확정한다: else 가 있으면 그 else 가 그 NPC, 없으면 fall-through.
        """
        d = 0
        for j in range(i, min(i + 4000, len(lines))):
            d += lines[j].count("{") - lines[j].count("}")
            if j > i and d <= 0:
                for k in range(j, min(j + 4, len(lines))):
                    if lines[k].strip():
                        return bool(re.match(r"^\s*else\s*\{?\s*$", lines[k]))
                return False
        return False

    for _li, ln in enumerate(lines):
        ne_here: str | None = None
        for rx, width in ((RE_NAME_INT_NE, 4), (RE_NAME_LONG_NE, 8)):
            m = rx.search(ln)
            if m:
                nm = int_to_name(m.group(1), width)
                if nm.isalnum():
                    pending_ne[depth] = nm
                    if not _else_follows(_li):
                        ne_here = nm
        # `}` 로 닫힌 뒤 같은 깊이에서 else 를 만나면 그 이름으로 전환한다.
        # ⚠️ **이름 전환이 표정 마스크보다 우선**이다. 반대로 놓았더니 arnold 가 남긴
        #    마스크가 pong 의 `else` 를 가로채 pong 이 통째로 사라졌다(2026-08-04).
        _is_else = bool(re.match(r"^\s*else\s*\{?\s*$", ln))
        # 🔴 표정 마스크의 else 와 이름 전환의 else 가 **같은 깊이에서 겹친다.**
        #    깊이만으로 가르면 서로를 가로챈다(arnold 의 `{1,6,7}` 이 날아가거나,
        #    반대로 arnold 가 남긴 마스크가 pong 의 else 를 먹어 pong 이 사라진다).
        #    ⇒ 마스크에 **소유 NPC** 를 같이 달아 두고, 그 NPC 안에 있을 때만 마스크가 이긴다.
        if _is_else and mask_else is not None and depth == mask_else[0]                 and cur_name == mask_else[2]:
            mask_emos, mask_depth = mask_else[1], depth + 1
            mask_else = None
        elif _is_else and depth in pending_ne:
            _nm = pending_ne.pop(depth)
            cur_name, cur_emo, in_switch = _nm, None, False
            emo_var, emo_depth = None, None
            shift_var, mask_emos, mask_depth, mask_else = None, None, None, None
            # `else` 가 있으면 **그 else 가 그 NPC** 다 — 블록이 닫힌 뒤로 이어지는
            # fall-through 가 아니다. 예약을 취소하지 않으면 이름이 다음 NPC 로 밀린다.
            ne_after[:] = [e for e in ne_after if not (e[1] == _nm and e[0] == depth + 1)]
        depth += ln.count("{") - ln.count("}")
        # 🔴 int/long `!=` 도 memcmp 처럼 **fall-through** 로 나온다(2026-08-04):
        #       if (*(long *)pbVar16 != <"florence">) { …다른 NPC들… }
        #       ← 블록이 닫힌 **뒤** 이어지는 코드가 florence 것이다(else 가 아니다)
        #    `else` 형태만 보던 종전 코드는 이걸 통째로 놓쳐 florence 가 npc_face.json 에서
        #    빠졌고, 그래서 초상에 **얼굴 파츠가 하나도 안 붙었다**(사용자 신고).
        if ne_here is not None and ln.count("{") > ln.count("}"):
            ne_after.append((depth, ne_here))
        # 뒤집힌 memcmp/int 블록이 닫혔다 → 이제부터가 그 NPC 다.
        while ne_after and depth < ne_after[-1][0]:
            cur_name, cur_emo, in_switch = ne_after.pop()[1], None, False
            emo_var, emo_depth = None, None
            shift_var, mask_emos, mask_depth, mask_else = None, None, None, None
        # 비트마스크 표정 집합 — 블록이 닫히면 원상복귀, `else` 는 여집합이 아니라
        # **그 마스크 자체**(`(uVar3 & M) == 0` 의 else = M 에 든 표정들)다.
        if mask_depth is not None and depth < mask_depth:
            mask_emos, mask_depth = None, None
        # 예약해 둔 else 를 그 깊이를 벗어날 때까지 안 만났으면 버린다 —
        # 남겨 두면 **다른 NPC 의 else** 를 가로챈다(pong 이 통째로 사라지던 원인).
        if mask_else is not None and depth < mask_else[0]:
            mask_else = None
        m = RE_EMO_SHIFT.match(ln)
        if m and emo_var == m.group(2):
            shift_var = m.group(1)
        if mask_else is not None and re.match(r"^\s*else\s*\{?\s*$", ln.rstrip()) \
                and depth == mask_else[0] + 1:
            mask_emos, mask_depth = mask_else[1], depth
            mask_else = None
        m = RE_EMO_MASK.search(ln)
        if m and shift_var == m.group(1):
            bits = [i for i in range(32) if int(m.group(2), 16) >> i & 1]
            if m.group(3) == "!=":
                mask_emos, mask_depth = bits, depth
            else:
                mask_else = (depth - 1, bits, cur_name)   # else 쪽이 그 표정 집합
        for rx, width in ((RE_NAME_INT, 4), (RE_NAME_LONG, 8)):
            m = rx.search(ln)
            if m:
                nm = int_to_name(m.group(1), width)
                if nm.isalnum():
                    cur_name, cur_emo, in_switch = nm, None, False
                    emo_var, emo_depth = None, None
                    shift_var, mask_emos, mask_depth, mask_else = None, None, None, None
        m = RE_NAME_MEM.search(ln)
        if m:
            mem_var = (m.group(1), m.group(2))
            cur_name, cur_emo, in_switch = m.group(2), None, False
            emo_var, emo_depth = None, None
            # ⚠️ 마스크 상태도 같이 비운다 — 안 그러면 앞 NPC 가 남긴 `mask_else` 가
            #    뒤 NPC 의 `else` 를 가로챈다(eden·pong 표정이 사라지던 원인).
            shift_var, mask_emos, mask_depth, mask_else = None, None, None, None
        elif mem_var is not None:
            m = RE_MEM_NE.match(ln)
            if m and m.group(1) == mem_var[0]:
                ne_after.append((depth, mem_var[1]))   # depth = 이 블록 **안**
                mem_var = None
            elif RE_MEM_EQ.match(ln):
                mem_var = None                          # 정상 형태 — 이미 cur_name 에 들어갔다
        if RE_EMO_SWITCH.search(ln):
            in_switch = True
        m = RE_EMO_CASE.match(ln)
        if m and in_switch:
            cur_emo = int(m.group(1))
        m = RE_EMO_EQ.search(ln)
        if m:
            cur_emo = int(m.group(1))
        # 표정 인자를 담은 지역변수를 기억해 뒀다가 `if (uVarN == K)` 를 표정 분기로 읽는다.
        m = RE_EMO_VAR.match(ln)
        if m:
            emo_var = m.group(1)
        # 표정 분기가 닫히면 "?"(그 외 표정 공통) 로 복귀한다 — 안 그러면 뒤따르는
        # 기본 블록이 그 표정 것으로 잘못 실린다. `depth` 는 이 줄의 `{`/`}` 까지 반영된
        # 값이라, 블록 **안**에서는 여는 줄과 같고 닫힌 뒤에만 작아진다.
        if emo_depth is not None and depth < emo_depth:
            cur_emo, emo_depth = None, None
        m = RE_EMO_VAR_EQ.search(ln)
        if m and m.group(1) == emo_var:
            cur_emo, emo_depth = int(m.group(2)), depth

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
            val = None if y is None else [xs[pt], round(-y, 3)]
            # 표정 집합(비트마스크 분기)이면 **그 표정 전부에** 같은 좌표를 싣는다.
            keys = [str(e) for e in mask_emos] if mask_emos else [str(cur_emo or "?")]
            for kk in keys:
                out.setdefault(cur_name, {}).setdefault(kk, {})[slot] = val

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
    }

    # 오리지널 캐릭터(원작에 없는 NPC — 선대군 등)의 파츠 좌표는 각 반입 빌더가
    # `assets/converted/npc_*/_face.json` 사이드카로 남긴다(예: build_sundaegun_npc.py).
    # 여기서 병합해야 이 추출기를 재실행해도 그 캐릭터들이 지워지지 않는다.
    for side_fp in sorted((REPO / "assets" / "converted").glob("npc_*/_face.json")):
        doc["npc"].update(json.loads(side_fp.read_text(encoding="utf-8")))

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

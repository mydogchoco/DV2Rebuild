#!/usr/bin/env python3
"""프롤로그(시나리오 0) 대사의 **화자**를 libgame.so 에서 직접 채굴한다.

## 왜 디컴프가 아니라 바이너리인가

화자를 배정하는 함수는 `cocos2d::Scenario1::setNext(CCObject*)` 인데,
**Ghidra 가 이 함수를 312 바이트로 잘못 끊는다** — ELF 심볼 테이블상 실제 크기는 **77,940 바이트**다
(`--max` 를 90000 으로 올려 재디컴파일해도 똑같이 312 로 나온다 = 함수 경계 인식 실패,
`[skip>8000]` 마커도 안 붙어서 겉보기엔 정상이다). 그래서 `docs/ref/orig_code/decomp/Scenario1.c`
에는 프롤로그가 통째로 없다.

`parse_scenario_flow.py` 의 `--switch` 경로(= `setNext` 를 case 로 읽는 길)도 쓸 수 없다.
그쪽 주석대로 Ghidra 가 본문이 같은 case 라벨을 합쳐 버려 스텝별 화자가 소실된다(81화 오배정 실측).

⇒ **명령어 수준에서 직접 읽는다.** 다행히 패턴이 아주 단순하다.

## 원작 패턴 (실측)

원작은 대사 함수를 부르기 전에 **멤버 두 개에 문자열을 써 둔다**(1~78화도 같다 —
`story.gd::setTalk` 주석 참조):

    this+0x1d8 = 화자      ("NPC_nuri")
    this+0x1f0 = 대사 키   ("PrologueTalk5")

AArch64 로는 이렇게 나온다:

    adrp x1, 0x210e000
    add  x0, x24, #0x1d8      ← 화자 필드
    add  x1, x1, #0x338       ← "NPC_nuri"
    bl   std::string::assign
    adrp x1, 0x2111000
    add  x0, x24, #0x1f0      ← 대사 키 필드
    add  x1, x1, #0x2ca       ← "PrologueTalk5"
    movz w2, #13
    bl   std::string::assign

그래서 함수 전체를 선형으로 훑으며 `add x0, xN, #0x1d8 / #0x1f0` 과 그 직전 `adrp+add` 로
완성된 문자열 포인터를 짝지으면 (화자, 대사키) 쌍이 그대로 떨어진다.

## 안전장치 (지어내지 않기)

- 화자는 `NPC_` 로 시작하는 문자열만 인정한다(한 번은 `Tutorial_34` 가 화자 칸에 섞여 나왔다).
- 화자는 **한 대사에만** 적용하고 바로 비운다(다음 대사로 흘러가지 않게).
- 대사 키가 없는 화자, 화자가 없는 대사는 그냥 버린다 — 화자가 안 잡힌 줄은
  **초상 없이** 지나간다(원작 `setUserTalk` = 주인공 지문이 그렇다).

    python scripts/tools/extract_prologue_speakers.py           # 표 출력 + CSV 갱신
    python scripts/tools/extract_prologue_speakers.py --dry     # 출력만
"""
from __future__ import annotations

import csv
import re
import struct
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO = Path(__file__).resolve().parents[2]
SO = REPO / "libgame.so"
SHEET = REPO / "docs" / "input" / "sheets" / "prologue_speakers.csv"
STRINGS = REPO / "DV2" / "string" / "stringsData_KR.xml"

SPK_OFF, TALK_OFF = 0x1D8, 0x1F0
NUL = bytes([0])
FN_SYM = "_ZN7cocos2d9Scenario17setNextEPNS_8CCObjectE"


def elf_func(data: bytes, want: str) -> tuple[int, int]:
    """심볼 테이블에서 함수의 (vaddr, size). Ghidra 가 못 믿을 때 여기가 진실이다."""
    e_shoff = struct.unpack_from("<Q", data, 0x28)[0]
    e_shent = struct.unpack_from("<H", data, 0x3A)[0]
    e_shnum = struct.unpack_from("<H", data, 0x3C)[0]
    e_shstrndx = struct.unpack_from("<H", data, 0x3E)[0]
    secs = []
    for i in range(e_shnum):
        o = e_shoff + i * e_shent
        nm, typ, fl, addr, off, size, link, info, al, ent = struct.unpack_from("<IIQQQQIIQQ", data, o)
        secs.append(dict(nm=nm, off=off, size=size, link=link, ent=ent))
    sh = secs[e_shstrndx]

    def sname(n: int) -> str:
        return data[sh["off"] + n: data.index(b"\0", sh["off"] + n)].decode()

    for s in secs:
        if sname(s["nm"]) != ".dynsym":
            continue
        st = secs[s["link"]]
        for i in range(s["size"] // s["ent"]):
            o = s["off"] + i * s["ent"]
            stn = struct.unpack_from("<I", data, o)[0]
            val, sz = struct.unpack_from("<QQ", data, o + 8)
            if not stn:
                continue
            nm = data[st["off"] + stn: data.index(b"\0", st["off"] + stn)].decode("utf-8", "replace")
            if nm == want:
                return val, sz
    raise SystemExit("심볼을 못 찾았다: " + want)


def mine(data: bytes, lo: int, size: int) -> list[tuple[str, str]]:
    """`add x0, xN, #0x1d8/#0x1f0`(필드) 와 x1 에 실린 문자열을 짝짓는다.

    정산 시점은 **BL 이거나 다음 필드 표시**다 — 꼬리 병합된 경로에는 그 자리에 `bl` 이 없어
    BL 만 기다리면 놓친다(실측: `PrologueTalk25`/`NPC_prologuemonster` 쌍).
    """
    def cstr(a: int) -> str:
        try:
            return data[a: data.index(NUL, a)].decode("utf-8", "replace")
        except ValueError:
            return ""

    adrp: dict[int, int] = {}
    strp: dict[int, tuple[int, str]] = {}
    field: tuple[int, int] | None = None
    speaker: str | None = None
    out: list[tuple[str, str]] = []

    def apply(off: int, s: str) -> None:
        nonlocal speaker
        if off == SPK_OFF:
            speaker = s if s.startswith("NPC_") else None
        elif off == TALK_OFF and s.startswith("PrologueTalk"):
            if speaker:
                out.append((s, speaker))
            speaker = None                       # 한 대사에만 적용

    def settle() -> None:
        nonlocal field
        if field is None:
            return
        st = strp.get(1)
        if st and abs(st[0] - field[0]) <= 32:
            apply(field[1], st[1])
        field = None

    for pc in range(lo, lo + size, 4):
        w = struct.unpack_from("<I", data, pc)[0]
        if (w & 0x9F000000) == 0x90000000:                    # ADRP
            rd = w & 0x1F
            imm = (((w >> 5) & 0x7FFFF) << 2) | ((w >> 29) & 3)
            if imm & (1 << 20):
                imm -= 1 << 21
            adrp[rd] = (pc & ~0xFFF) + (imm << 12)
        elif (w & 0xFFC00000) == 0x91000000:                  # ADD Xd, Xn, #imm
            rd, rn, imm = w & 0x1F, (w >> 5) & 0x1F, (w >> 10) & 0xFFF
            # ⚠️ **필드 판정이 먼저다.** `this` 를 담는 레지스터(x24 등)가 .text 어딘가에서
            #    adrp 대상이었으면 `rn in adrp` 가 참이 되어 필드 분기가 영영 안 걸린다
            #    (실측: 함수 하나만 훑을 땐 안 걸리던 함정이 .text 전체에서 터졌다 — 화자 0건).
            if rd == 0 and imm in (SPK_OFF, TALK_OFF) and rn != 0:
                settle()                                      # 이전 것부터 정산
                field = (pc, imm)
            elif rn in adrp:
                t = cstr(adrp[rn] + imm)
                if t and t.isprintable() and len(t) < 64:
                    strp[rd] = (pc, t)
        elif (w & 0xFC000000) == 0x94000000:                  # BL
            settle()
    settle()
    return out


def text_range(data: bytes) -> tuple[int, int]:
    e_shoff = struct.unpack_from("<Q", data, 0x28)[0]
    e_shent = struct.unpack_from("<H", data, 0x3A)[0]
    e_shnum = struct.unpack_from("<H", data, 0x3C)[0]
    e_shstrndx = struct.unpack_from("<H", data, 0x3E)[0]
    secs = []
    for i in range(e_shnum):
        o = e_shoff + i * e_shent
        nm, typ, fl, addr, off, size, link, info, al, ent = struct.unpack_from("<IIQQQQIIQQ", data, o)
        secs.append((nm, addr, size))
    sh_nm, sh_addr, sh_size = secs[e_shstrndx]
    sh_off = struct.unpack_from("<Q", data, e_shoff + e_shstrndx * e_shent + 0x18)[0]
    for nm, addr, size in secs:
        e = data.index(NUL, sh_off + nm)
        if data[sh_off + nm:e].decode() == ".text":
            return addr, size
    raise SystemExit(".text 를 못 찾았다")


def load_texts() -> dict[str, str]:
    t = STRINGS.read_text(encoding="utf-8", errors="replace")
    return {k: v.replace("&#10;", " / ").strip()
            for k, v in re.findall(r"<(PrologueTalk[0-9_]+)>(.*?)</\1>", t, re.S)}


def main() -> int:
    data = SO.read_bytes()
    lo, size = elf_func(data, FN_SYM)
    print("Scenario1::setNext  vaddr=%08x size=%d (Ghidra 는 312 로 끊는다)" % (lo, size))
    # ⚠️ `setNext` 만 보면 안 된다 — 마을 습격 대사(22/23)는 `ScenarioLayer` 의 **람다**가 낸다
    #    (`__func<__bind<ScenarioLayer…>>`). 패턴이 충분히 특이하고 `PrologueTalk` 로만 인정하므로
    #    .text 전체를 훑어도 오탐이 없다.
    tlo, tsz = text_range(data)
    pairs = mine(data, tlo, tsz)
    found: dict[str, set[str]] = {}
    for talk, spk in pairs:
        found.setdefault(talk, set()).add(spk)
    texts = load_texts()

    def order(t: str) -> tuple[int, str]:
        return int(t.replace("PrologueTalk", "").split("_")[0]), t

    print("\n%-18s %-14s %s" % ("대사키", "화자", "대사"))
    rows = []
    conflict = 0
    for i in range(0, 40):
        for suffix in ("", "_1"):
            key = "PrologueTalk%d%s" % (i, suffix)
            if key not in texts:
                continue
            spks = sorted(found.get(key, []))
            if len(spks) > 1:
                conflict += 1
            npc = spks[0].removeprefix("NPC_") if len(spks) == 1 else ""
            rows.append((i, key, npc, texts[key]))
            print("%-18s %-14s %s" % (key, npc or "(없음)", texts[key][:44]))
    got = sum(1 for r in rows if r[2])
    print("\n화자 확보 %d / 대사 %d" % (got, len(rows)) + ("  ⚠️충돌 %d" % conflict if conflict else ""))
    if "--dry" not in sys.argv:
        SHEET.parent.mkdir(parents=True, exist_ok=True)
        with SHEET.open("w", encoding="utf-8-sig", newline="") as f:
            w = csv.writer(f)
            w.writerow(["idx", "talk_key", "speaker", "basis", "text"])
            for i, key, npc, text in rows:
                w.writerow([i, key, npc,
                            "libgame.so Scenario1::setNext 채굴(this+0x1d8)" if npc else "", text])
        print("→ %s" % SHEET.relative_to(REPO))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

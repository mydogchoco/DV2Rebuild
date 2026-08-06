"""각성기 효과음 배선을 원작 바이너리에서 **실측**한다.

## 왜 (2026-08-06)

`UltimateLayer.c` 에는 `playEffect` 가 **한 건도 없다**. 소리는 안무 시퀀스 중간의
`CCCallFunc(std::function)` 람다 안에서 울린다 — 디컴프 C 에는 `local_e0 = &PTR_FUN_02825828`
같은 대입만 남아서, 그대로 읽으면 "각성기에 효과음이 없다"고 오판하게 된다.

종전 `UltimateFx.SFX` 표는 그래서 **문자열 전수 검색으로 이름만 주워** 만든 것이었고,
`effect_light`·`effect_fire1`·`effect_aqua1` 은 실은 **파티클 plist 이름**이었다
(`AdventureScene.c`: `"particle/scene/adventure/effect_light.plist"`). mp3 가 없으니
`Bgm.sfx` 가 조용히 건너뛰어 **소리가 아예 안 났다**.

## 어떻게 캔다 (4단)

1. `UltimateLayer.c` 에서 `&PTR_FUN_<addr>` 을 함수별로 모은다.
2. `PTR_FUN_<addr>` = `std::function` 의 vtable. **ELF 재배치 테이블**에서 그 슬롯의
   addend 를 읽어 실제 함수 주소를 얻는다(파일 바이트는 0 — 로드 시 채워지므로).
   ⚠️ Ghidra 주소 = 파일 VA + 0x100000 ([[dv2-rodata-constants-readable]]).
   슬롯 +0x18 이 invoke(= 람다 본문)다.
3. 그 본문을 디스어셈블해 `adrp`+`add`(또는 `ldr`) 로 잡는 `.rodata` 주소를 찾고,
   `libgame.so` 에서 NUL 종료 문자열을 읽는다 → `music/effect_*.mp3`.
4. 시각은 `docs/ref/design/ultimate_layer_sequences.md`(resolve_actions.py 산출)의
   같은 람다 앞에 쌓인 `CCDelayTime` 합. 여기서는 **소리 이름과 소속 함수**까지만 낸다.

## 쓰는 법

    python scripts/tools/ultimate_sfx.py                # 함수별 효과음 표
    python scripts/tools/ultimate_sfx.py --el light     # 한 속성만
    python scripts/tools/ultimate_sfx.py --have         # 우리 덤프에 mp3 가 있는지 함께
"""
from __future__ import annotations
import argparse, re, struct, sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO = Path(__file__).resolve().parents[2]
SO = REPO / "libgame.so"
DECOMP = REPO / "docs/ref/orig_code/decomp/UltimateLayer.c"
MUSIC = REPO / "DV2/music"
GHIDRA_BASE = 0x100000          # Ghidra 주소 − 이 값 = 파일 VA
VT_INVOKE = 0x18                # std::function vtable 의 invoke 슬롯


def load_relocs(blob: bytes) -> dict[int, int]:
    """r_offset → addend. 람다 vtable 값이 여기 산다(파일 바이트는 0)."""
    e_shoff, = struct.unpack_from("<Q", blob, 0x28)
    e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", blob, 0x3A)
    secs = []
    for i in range(e_shnum):
        o = e_shoff + i * e_shentsize
        nm, _typ, _fl, _ad, off, size, *_ = struct.unpack_from("<IIQQQQIIQQ", blob, o)
        secs.append({"n": nm, "off": off, "size": size})
    st = secs[e_shstrndx]
    sb = blob[st["off"]:st["off"] + st["size"]]
    out: dict[int, int] = {}
    for s in secs:
        name = sb[s["n"]:sb.index(b"\0", s["n"])].decode()
        if name not in (".rela.dyn", ".rela.plt"):
            continue
        for o in range(s["off"], s["off"] + s["size"], 24):
            r_off, _r_info, r_add = struct.unpack_from("<QQq", blob, o)
            out[r_off] = r_add
    return out


def cstr(blob: bytes, ghidra_addr: int, limit: int = 96) -> str:
    o = ghidra_addr - GHIDRA_BASE
    if not (0 <= o < len(blob)):
        return ""
    b = blob[o:o + limit]
    return b.split(b"\0")[0].decode("utf-8", "replace")


def lambdas_by_func(src: str) -> dict[str, list[int]]:
    """디컴프 C 를 함수 단위로 갈라 `&PTR_FUN_xxxx` 를 모은다."""
    out: dict[str, list[int]] = {}
    cur = "?"
    for line in src.splitlines():
        # ⚠️ Ghidra 는 반환형이 **앞 줄로 빠진** 함수의 헤더를 한 칸 들여쓴 채 클래스명부터 쓴다
        #    (` cocos2d::UltimateLayer::calculateDamage(...)`). 종전 `^\w[...]*?cocos2d::` 는
        #    그 `^\w` 가 'c' 를 먼저 먹어 **그런 헤더를 통째로 놓쳤고**, 그 안의 람다가 앞 함수
        #    몫으로 잘못 붙었다(2026-08-06: damaged 48건이 actionWind_C/createAndAdd 로 밀려 있었다).
        #    본문의 호출문(`  cocos2d::UltimateLayer::initLight(this);`)과는 **`;` 유무**로 가른다.
        m = None if ";" in line else re.search(r"cocos2d::UltimateLayer::(\w+)\s*\(", line)
        if m:
            cur = m.group(1)
        for a in re.findall(r"&PTR_FUN_([0-9a-f]{6,8})", line):
            out.setdefault(cur, []).append(int(a, 16))
    return out


def strings_in(blob: bytes, body: int, count: int = 64) -> list[str]:
    """람다 본문에서 `adrp`(+`add`/`ldr`)로 잡히는 `music/*.mp3` 경로를 뽑는다.

    ARM64 세 명령만 직접 디코드한다 — `disasm.py` 를 람다마다 띄우면 171회 × 프로세스라
    2분이 넘는다(2026-08-06 실측). 여기서 필요한 건 주소 계산뿐이다.
    """
    page: dict[int, int] = {}                 # 레지스터 → 현재 담긴 주소
    found: list[str] = []
    off = body - GHIDRA_BASE
    for i in range(count):
        w = int.from_bytes(blob[off + i * 4:off + i * 4 + 4], "little")
        # ⚠️ `ret` 에서 멈추지 않는다. vtable +0x18 은 **복사 생성자**(5명령 + ret)이고
        #   람다 본문은 그 뒤에 이어 놓인다 — 끊으면 아무것도 못 찾는다(2026-08-06 실측).
        if (w & 0x9F000000) == 0x90000000:    # adrp Xd, page
            immlo = (w >> 29) & 3
            immhi = (w >> 5) & 0x7FFFF
            imm = (immhi << 2 | immlo)
            if imm & (1 << 20):
                imm -= 1 << 21
            page[w & 31] = ((body + i * 4) & ~0xFFF) + (imm << 12)
        elif (w & 0xFF800000) == 0x91000000:  # add Xd, Xn, #imm
            rn = (w >> 5) & 31
            if rn in page:
                addr = page[rn] + ((w >> 10) & 0xFFF)
                page[w & 31] = addr
                s = cstr(blob, addr)
                if s.startswith("music/") and s not in found:
                    found.append(s)
        elif (w & 0xFFC00000) == 0xF9400000:  # ldr Xt, [Xn, #imm]
            rn = (w >> 5) & 31
            if rn in page:
                # ⚠️ `music/` 로 시작하는 것만 받는다 — 긴 문자열은 16+8바이트로 나눠 싣기 때문에
                #   중간 오프셋을 그대로 읽으면 `bang.mp3` 같은 **꼬리 토막**이 잡힌다.
                s = cstr(blob, page[rn] + (((w >> 10) & 0xFFF) << 3))
                if s.startswith("music/") and s not in found:
                    found.append(s)
    return found


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--el", default=None, help="속성 이름(fire/aqua/… )으로 함수 필터")
    ap.add_argument("--have", action="store_true", help="DV2/music 에 mp3 가 있는지 표시")
    a = ap.parse_args()

    blob = SO.read_bytes()
    rel = load_relocs(blob)
    src = DECOMP.read_text(encoding="utf-8", errors="replace")
    by_fn = lambdas_by_func(src)

    total = hit = 0
    for fn in sorted(by_fn):
        if a.el and a.el.lower() not in fn.lower():
            continue
        rows = []
        for g in dict.fromkeys(by_fn[fn]):          # 순서 유지 + 중복 제거
            va = g - GHIDRA_BASE + VT_INVOKE
            if va not in rel:
                continue
            total += 1
            body = rel[va] + GHIDRA_BASE
            for s in strings_in(blob, body):
                hit += 1
                mark = ""
                if a.have:
                    stem = Path(s).stem
                    mark = "  ✔" if (MUSIC / (stem + ".mp3")).exists() else "  ✗없음"
                rows.append("    PTR_FUN_%08x → %08x  %s%s" % (g, body, s, mark))
        if rows:
            print("== UltimateLayer::%s" % fn)
            print("\n".join(rows))
    print("\n람다 %d개 중 효과음 %d건." % (total, hit))


if __name__ == "__main__":
    main()

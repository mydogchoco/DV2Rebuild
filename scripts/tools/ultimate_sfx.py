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


# ── 재생 **시각** — 같은 람다 앞에 쌓인 `CCDelayTime` 합 ──────────────────────
#
# 출처는 `docs/ref/design/ultimate_layer_sequences.md`(= `resolve_actions.py` 가 디컴프에서
# 기계 복원한 액션 트리)다. 거기 `CCCallFunc → lambda@PTR_FUN_x` 가 그대로 찍혀 있으므로,
# 그 노드까지의 경과시간을 트리로 계산하면 **추측 없이** 시각이 나온다.
#
# 시간 규칙(Cocos 액션 의미 그대로):
#   CCSequence = 자식 합 · CCSpawn = 자식 최대 · CCEase*/CCRepeat* = 자식 그대로
#   시간 있는 액션(Move/Scale/Fade/Rotate/Jump/Bezier/Tint/Blink/Delay) = **첫 인자**
#   Show/Hide/Place/CallFunc/RemoveSelf/Flip 등 = 0
# `*(this + 0x228)` 은 **속성 공통 지연**이라 수로 접지 않고 `D` 계수로 남긴다
#   (`run<El>` 에만 붙고 `action<El>_C` 에는 안 붙는다 — 이 표가 그 사실의 근거이기도 하다).
SEQ_MD = REPO / "docs/ref/design/ultimate_layer_sequences.md"
ZERO_ACTS = ("CCShow", "CCHide", "CCPlace", "CCCallFunc", "CCRemoveSelf", "CCFlip",
             "CCToggleVisibility", "CCReuseGrid", "CCStopGrid")
TIMED = re.compile(r"^CC\w+\((.*)$")


def _first_arg(inner: str) -> str:
    """`0.5, 0.15)` → `0.5` — 괄호 깊이를 세며 첫 인자만 끊는다."""
    depth, out = 0, []
    for ch in inner:
        if ch in "([":
            depth += 1
        elif ch in ")]":
            if depth == 0:
                break
            depth -= 1
        elif ch == "," and depth == 0:
            break
        out.append(ch)
    return "".join(out).strip()


def _dur(label: str) -> tuple[float, float] | None:
    """리프 액션의 지속시간 → (D 계수, 초). 못 읽으면 None(= 이후 시각을 '?' 로 만든다)."""
    name = label.split("(")[0].split()[0]
    if name.startswith(ZERO_ACTS):
        return (0.0, 0.0)
    m = TIMED.match(label)
    if not m:
        return (0.0, 0.0)                      # 인자 없는 액션
    arg = _first_arg(m.group(1))
    d = 1.0 if "0x228" in arg else 0.0
    if d:
        arg = re.sub(r"\*\(this \+ 0x228\)", "0", arg)
    try:                                       # `1.45` · `0 + 1.45` · `0` 만 받는다
        return (d, float(eval(arg, {"__builtins__": {}}, {})))
    except Exception:
        return None                            # `(float)(iVar5 % 0xb) * 0.025 + 1.75` 등


def parse_tree(lines: list[str]) -> list[tuple[int, str]]:
    """`  - CCDelayTime(1.25)` → (깊이, 라벨). 깊이는 2칸 = 1단."""
    out = []
    for ln in lines:
        m = re.match(r"^(\s*)- (.*?)\s*(\?)?$", ln)
        if m:
            out.append((len(m.group(1)) // 2, m.group(2)))
    return out


def walk(nodes: list[tuple[int, str]], i: int, base: tuple[float, float],
         hits: dict[int, tuple[float, float] | None]) -> tuple[int, tuple[float, float] | None]:
    """nodes[i] 서브트리를 훑으며 람다 노드의 시각을 hits 에 적는다. → (다음 인덱스, 지속시간)"""
    depth, label = nodes[i]
    kids: list[int] = []
    j = i + 1
    while j < len(nodes) and nodes[j][0] > depth:
        if nodes[j][0] == depth + 1:
            kids.append(j)
        j += 1
    m = re.search(r"lambda@PTR_FUN_([0-9a-f]+)", label)
    if m:
        # ⚠️ **덮어쓰지 않는다** — 같은 람다가 여러 runAction 에 등장한다(땅 `02824aa8` 이 그렇다).
        #    덮어쓰면 마지막 등장만 남아 "고정 시각"으로 보이고, 루프 안의 미지 시각이 조용히
        #    사라진다(2026-08-06 실측).
        got = hits.setdefault(int(m.group(1), 16), [])
        if base not in got:
            got.append(base)
    if not kids:                                          # 리프
        return j, _dur(label)
    if label.startswith("CCSequence"):
        acc: tuple[float, float] | None = base
        for k in kids:
            _, d = walk(nodes, k, acc, hits)
            if acc is None or d is None:
                acc = None                                # 한 번 모르면 뒤는 전부 모른다
            else:
                acc = (acc[0] + d[0], acc[1] + d[1])
        tot = None if acc is None or base is None else (acc[0] - base[0], acc[1] - base[1])
        return j, tot
    # CCSpawn = 자식이 **동시에** 시작 / CCEase*·CCRepeat* = 자식 그대로
    best: tuple[float, float] | None = (0.0, 0.0)
    for k in kids:
        _, d = walk(nodes, k, base, hits)
        if d is None or best is None:
            best = None
        elif label.startswith("CCSpawn"):
            best = max(best, d, key=lambda t: t[0] * 10.0 + t[1])
        else:
            best = d
    return j, best


def lambda_times() -> dict[str, dict[int, list]]:
    """함수명 → {람다 주소: [(D 계수, 초) | None, …]} — 등장이 여럿이면 전부 담는다."""
    out: dict[str, dict[int, list]] = {}
    fn = None
    buf: list[str] = []

    def flush() -> None:
        if fn is None:
            return
        nodes = parse_tree(buf)
        hits = out.setdefault(fn, {})
        i = 0
        while i < len(nodes):
            if nodes[i][0] == 0:
                i, _ = walk(nodes, i, (0.0, 0.0), hits)
            else:
                i += 1

    for ln in SEQ_MD.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^## UltimateLayer::(\w+)", ln)
        if m:
            flush()
            fn, buf = m.group(1), []
        else:
            buf.append(ln)
    flush()
    return out


def fmt_time(t: tuple[float, float] | None) -> str:
    if t is None:
        return "     ?"
    return ("D*%g + %.4g" % t).replace("D*0 + ", "").replace("D*1 + ", "D + ").rjust(11)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--el", default=None, help="속성 이름(fire/aqua/… )으로 함수 필터")
    ap.add_argument("--have", action="store_true", help="DV2/music 에 mp3 가 있는지 표시")
    ap.add_argument("--times", action="store_true",
                    help="재생 시각까지(액션 트리에서 계산 — D = 속성 공통 지연 0x228)")
    a = ap.parse_args()

    blob = SO.read_bytes()
    rel = load_relocs(blob)
    src = DECOMP.read_text(encoding="utf-8", errors="replace")
    by_fn = lambdas_by_func(src)

    times = lambda_times() if a.times else {}

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
                when, key = "", (1, 0.0)
                if a.times:
                    ts = times.get(fn, {}).get(g)
                    when = "  @ %s" % (" / ".join(fmt_time(t).strip() for t in ts).rjust(11)
                                       if ts else "(트리에 없음)")
                    first = ts[0] if ts else None
                    key = (0, first[0] * 100.0 + first[1]) if first else (2, 0.0)
                rows.append((key, "    PTR_FUN_%08x → %08x%s  %s%s" % (g, body, when, s, mark)))
        if rows:
            print("== UltimateLayer::%s" % fn)
            print("\n".join(r for _, r in sorted(rows, key=lambda x: x[0])))
    print("\n람다 %d개 중 효과음 %d건." % (total, hit))


if __name__ == "__main__":
    main()

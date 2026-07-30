"""switch 형 회차 클래스(`Scenario1`~`Scenario8`) 연출 추출 — **점프 테이블 수준**.

## 왜 별도 도구인가

82~101화(`Scenario_zimon`/`_mamorudic`/`_Kadeath`)는 `initScenarioData` 가 `std::function`
벡터로 스텝을 push 해서 스텝 하나 = 함수 하나였다(→ `extract_scenario_flow.py`).
1~81화(`Scenario1~8`)는 구조가 다르다. `setNext(CCObject*)` 하나가 **두 겹의 점프 테이블**을 탄다:

    ① 회차 분기   sn = mScenarioManager()->0x168
                  cmp sn,#N ; b.hi <default> ; br <sn 테이블>     (Scenario1~7)
                  ※ Scenario8 은 회차가 3개뿐이라 `cmp sn,#0x4f` 체인으로 갈린다
    ② 스텝 분기   step = this->0x158 ; index = step - 1
                  cmp index,#M ; b.hi <default> ; br <스텝 테이블>

각 스텝 case 블록은 스택 슬롯 4개(npc/state/pos/emoticon)에 값을 쓴 뒤 **꼬리의 단일
`setNpcTalk`** 으로 합류한다. 대사만 넘기는 스텝은 `setUserTalk` 로 간다.
테이블 **밖**의 마지막 스텝 하나는 `default` 분기에 있다(`step == <상수>` → `setUserTalk`).
이걸 빼먹으면 회차마다 정확히 1줄씩 모자란다.

## 왜 디컴프 C 로는 안 되나 (2026-07-31 실측)

- Ghidra 가 본문이 같은 case 라벨을 합쳐 출력한다(`Scenario8`: 라벨 119개 → 주소 63개).
- switch 블록의 **텍스트 순서와 회차 가드 순서가 다르다** — 80화와 81화를 서로 바꿔 잡고도
  대사 수가 우연히 맞아 검증을 통과했다. 수량 검증만으론 부족하다.
- ⚠️ **Ghidra 가 `setNext` 의 함수 꼬리를 짧게 잡는다.** `Scenario1::setNext` 는 size=312 로
  보이지만 실제 코드는 0x156904c 까지 뻗는다. `getBody()` 를 믿으면 대사 호출도 case 블록도
  범위 밖이 된다 ⇒ **점프 테이블 타깃으로 범위를 넓혀 가며** 실제 구간을 찾는다.

## 산출

`data/scenario_flow_switch.json` — `parse_scenario_flow.py` 가 읽어 합친다(대사 수 검증 통과분만).

사용:
    python scripts/tools/extract_switch_flow.py --classes Scenario8
    python scripts/tools/extract_switch_flow.py --all
"""
from __future__ import annotations
import json, os, re, sys
from pathlib import Path

os.environ.setdefault("GHIDRA_INSTALL_DIR", r"C:\Users\mydog\ghidra\ghidra_12.1.2_PUBLIC")
os.environ.setdefault("JAVA_HOME", r"C:\Program Files\Eclipse Adoptium\jdk-21.0.11.10-hotspot")

REPO = Path(__file__).resolve().parents[2]
SO_PATH = REPO / "lib" / "arm64-v8a" / "libgame.so"
if not SO_PATH.exists():
    SO_PATH = REPO / "libgame.so"
PROJECT_DIR = Path(os.environ["GHIDRA_INSTALL_DIR"]).parent / "dv2_project"
PROJECT_NAME = "dv2"
OUT = REPO / "data" / "scenario_flow_switch.json"

CLASSES = [f"Scenario{i}" for i in range(1, 9)]
## 시나리오 매니저 멤버 오프셋 — 0x168 = 회차(sn) · 0x158 = 레이어의 스텝 번호.
OFF_SN, OFF_STEP = 0x168, 0x158
## 한 case 블록에서 따라갈 최대 명령 수 / 범위 탐색 상한.
MAX_STEP_INSNS, MAX_SCAN = 400, 300000


def parse_args(argv):
    classes = []
    if "--all" in argv:
        classes += CLASSES
    if "--classes" in argv:
        classes += [c.strip() for c in argv[argv.index("--classes") + 1].split(",") if c.strip()]
    return classes or CLASSES


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    classes = parse_args(sys.argv[1:])
    import pyghidra
    pyghidra.start()

    with pyghidra.open_program(str(SO_PATH), project_location=str(PROJECT_DIR),
                               project_name=PROJECT_NAME, analyze=False) as flat:
        prog = flat.getCurrentProgram()
        fm = prog.getFunctionManager()
        listing = prog.getListing()
        af = prog.getAddressFactory().getDefaultAddressSpace()
        mem = prog.getMemory()

        def at(off: int):
            return listing.getInstructionAt(af.getAddress(off))

        def text(i) -> str:
            """`sub x1,x29,#0xd0` 형태로 정규화. ⚠️ `getDefaultOperandRepresentation` 은 `#` 을
            빼고 주므로 쓰면 안 된다 — 실제 명령 문자열을 쓴다."""
            return re.sub(r",\s+", ",", re.sub(r"\s+", " ", str(i).strip()))

        def read_table(br_ins):
            """`br` 앞 16개 명령에서 점프 테이블 정보를 읽는다."""
            seq, cur = [], br_ins
            for _ in range(16):
                cur = listing.getInstructionBefore(cur.getAddress())
                if cur is None:
                    break
                seq.append(cur)
            seq.reverse()
            tbl = base = count = dflt = kind = step_ld = None
            page = shift = 0
            for s in seq:
                t = text(s)
                m = re.fullmatch(r"b\.hi (0x[0-9a-f]+)", t)
                if m:
                    dflt = int(m.group(1), 0)
                m = re.fullmatch(r"adrp (x\d+),(0x[0-9a-f]+)", t)
                if m:
                    page = int(m.group(2), 0)
                m = re.fullmatch(r"add (x\d+),\1,#(0x[0-9a-f]+|\d+)", t)
                if m and page:
                    tbl = page + int(m.group(2), 0)
                m = re.fullmatch(r"adr (x\d+),(0x[0-9a-f]+)", t)
                if m:
                    base = int(m.group(2), 0)
                m = re.fullmatch(r"cmp (w\d+),#(0x[0-9a-f]+|\d+)", t)
                if m:
                    count = int(m.group(2), 0) + 1
                m = re.fullmatch(r"ldr (w\d+),\[x\d+,#(0x[0-9a-f]+)\]", t)
                if m:
                    off = int(m.group(2), 0)
                    if off == OFF_SN:
                        kind = "sn"
                    elif off == OFF_STEP:
                        kind = "step"
                        step_ld = s.getAddress().getOffset()
                # `sub w8,w9,#0x1` → 인덱스 보정(스텝 번호는 1부터)
                m = re.fullmatch(r"sub (w\d+),(w\d+),#(0x[0-9a-f]+|\d+)", t)
                if m:
                    shift = int(m.group(3), 0)
            if tbl and base and count and kind:
                return {"kind": kind, "tbl": tbl, "base": base, "count": count, "dflt": dflt,
                        "shift": shift, "step_ld": step_ld,
                        "at": br_ins.getAddress().getOffset()}
            return None

        def rostr(addr: int) -> str | None:
            """그 주소가 짧은 ASCII C 문자열이면 돌려준다(NPC 폴더 이름 후보)."""
            try:
                out = []
                for k in range(24):
                    b = mem.getByte(af.getAddress(addr + k)) & 0xFF
                    if b == 0:
                        break
                    if not (0x20 <= b < 0x7F):
                        return None
                    out.append(chr(b))
                else:
                    return None
            except Exception:
                return None
            sv = "".join(out)
            return sv if 2 <= len(sv) <= 20 and re.fullmatch(r"[A-Za-z_0-9]+", sv) else None

        def entry_target(t: dict, idx: int) -> int:
            return t["base"] + (mem.getShort(af.getAddress(t["tbl"] + idx * 2)) & 0xFFFF) * 4

        def discover(entry: int):
            """실제 코드 범위와 점프 테이블 전부를 찾는다(꼬리가 짧게 잡히는 문제 회피)."""
            hi, cur, n = entry, at(entry), 0
            tables = []
            while cur is not None and n < MAX_SCAN:
                a = cur.getAddress().getOffset()
                if a > hi + 0x800:
                    break
                hi = max(hi, a)
                if cur.getMnemonicString() == "br":
                    t = read_table(cur)
                    if t:
                        tables.append(t)
                        for i in range(t["count"]):
                            hi = max(hi, entry_target(t, i))
                        if t["dflt"]:
                            hi = max(hi, t["dflt"])
                cur = listing.getInstructionAfter(cur.getAddress())
                n += 1
            return entry, hi + 0x400, tables

        funcs = {}
        # 다른 Scenario 클래스 코드로 넘어가지 않도록 하드 상한을 둔다
        # (Ghidra 가 꼬리를 짧게 잡아 범위를 넓히다 보면 이웃 클래스까지 삼킨다).
        scenario_entries = []
        for f in fm.getFunctions(True):
            q = "::" + f.getName(True)
            if "::Scenario" in q:
                scenario_entries.append(f.getEntryPoint().getOffset())
            for c in classes:
                if f"::{c}::setNext" in q and f.getBody().getNumAddresses() > 40:
                    funcs[c] = f
        scenario_entries.sort()

        out: dict[str, list[dict]] = {}
        for cls in classes:
            fn = funcs.get(cls)
            if fn is None:
                print(f"  {cls}: setNext 없음"); continue
            entry = fn.getEntryPoint().getOffset()
            cap = next((e for e in scenario_entries if e > entry + 0x40), 1 << 62)
            lo, hi, tables = discover(entry)
            if hi > cap:
                hi = cap
                tables = [t for t in tables if t["at"] < cap]

            # ── 대사 호출 위치(범위 기반) ────────────────────────────────────
            npc_talk_addr, user_talk_addrs, talker_addrs = None, set(), set()
            for i in iter_range(listing, af, lo, hi):
                if i.getMnemonicString() != "bl":
                    continue
                fl = i.getFlows()
                callee = fm.getFunctionAt(fl[0]) if fl else None
                if callee is None:
                    continue
                nm = callee.getName()
                if "setNpcTalk" in nm:
                    npc_talk_addr = i.getAddress().getOffset()
                elif "setUserTalk" in nm:
                    user_talk_addrs.add(i.getAddress().getOffset())
                elif nm == "setTalker":
                    talker_addrs.add(i.getAddress().getOffset())
            if npc_talk_addr is None and not talker_addrs:
                names = {}
                for i in iter_range(listing, af, lo, hi):
                    if i.getMnemonicString() != "bl":
                        continue
                    fl = i.getFlows()
                    cal = fm.getFunctionAt(fl[0]) if fl else None
                    nm = cal.getName() if cal else "?"
                    names[nm] = names.get(nm, 0) + 1
                top = sorted(names.items(), key=lambda kv: -kv[1])[:12]
                print(f"  {cls}: 범위 {lo:#x}~{hi:#x} 에 setNpcTalk 없음 — 호출 상위 {top}")
                continue

            slots: dict[str, str] = {}
            cur = at(npc_talk_addr) if npc_talk_addr is not None else None
            for _ in range(24 if cur is not None else 0):
                cur = listing.getInstructionBefore(cur.getAddress())
                if cur is None:
                    break
                m = re.fullmatch(r"(sub|add) (x[1-4]),(x29|sp),#(0x[0-9a-f]+|\d+)", text(cur))
                if m:
                    sign = -1 if m.group(1) == "sub" else 1
                    key = {"x1": "npc", "x2": "state", "x3": "pos", "x4": "emoticon"}[m.group(2)]
                    slots.setdefault(key, f"{m.group(3)}{sign * int(m.group(4), 0):+d}")
            if npc_talk_addr is not None and len(slots) < 4:
                print(f"  {cls}: 꼬리 인자 슬롯 {slots} — 건너뜀"); continue

            # ── 회차 블록 시작 주소(있으면) ─────────────────────────────────
            sn_blocks: dict[int, int] = {}
            for t in tables:
                if t["kind"] == "sn":
                    for i in range(t["count"]):
                        sn_blocks[i + t["shift"]] = entry_target(t, i)

            def episode_of(step_tbl: dict) -> int | None:
                """스텝 테이블이 속한 회차. ① sn 테이블이 있으면 그 블록 범위로,
                ② 없으면(Scenario8) 앞선 `cmp w,#sn` 가드로 판정한다."""
                if sn_blocks:
                    a = step_tbl["at"]
                    cand = [(st, sn) for sn, st in sn_blocks.items() if st <= a]
                    return max(cand)[1] if cand else None
                # ⚠️ 회차 가드는 **그 스텝 로드로 오는 분기** 앞의 cmp 다.
                #    "0x168 에서 읽은 뒤 첫 cmp" 같은 근사는 틀린다 —
                #    가드가 `cmp 0x51; b.eq <ep81>; cmp 0x4f; b.ne <끝>` 처럼 연쇄라
                #    세 스위치가 모두 0x51 로 읽혔다.
                sld = step_tbl.get("step_ld")
                if sld is None:
                    return None
                def cmp_before(ins, depth=4):
                    c = ins
                    for _ in range(depth):
                        c = listing.getInstructionBefore(c.getAddress())
                        if c is None:
                            return None
                        m = re.fullmatch(r"cmp (w\d+),#(0x[0-9a-f]+|\d+)", text(c))
                        if m:
                            return int(m.group(2), 0)
                    return None
                for src in prog.getReferenceManager().getReferencesTo(af.getAddress(sld)):
                    b = listing.getInstructionAt(src.getFromAddress())
                    if b is not None:
                        v = cmp_before(b)
                        if v is not None:
                            return v
                v = cmp_before(at(sld))          # 분기 없이 흘러들어오는 경우
                return v
                return None

            body = Range(lo, hi)
            for t in tables:
                if t["kind"] != "step":
                    continue
                sn = episode_of(t)
                if sn is None:
                    print(f"  {cls}: 스텝 테이블 {t['tbl']:#x} 회차 판별 실패"); continue
                flow: list[dict] = []
                for idx in range(t["count"]):
                    flow.extend(walk_case(listing, af, fm, body, entry_target(t, idx), slots,
                                          npc_talk_addr, user_talk_addrs, text,
                                          talker_addrs, rostr))
                if t["dflt"] and default_is_user_talk(listing, af, body, t["dflt"], user_talk_addrs):
                    flow.append({"op": "setUserTalk"})
                out[str(sn)] = flow
                talk = sum(1 for o in flow if o["op"] in ("setNpcTalk", "setUserTalk", "setTalker"))
                print(f"  {cls} ep{sn}: 스텝 {t['count']} · 대사 {talk}")

        OUT.write_text(json.dumps({
            "_re_basis": ("원작 Scenario1~8::setNext 의 두 겹 점프 테이블(회차→스텝)을 디스어셈블 "
                          "수준에서 읽어 스텝별 npc/state/pos/emoticon 을 복원. "
                          "도구 = scripts/tools/extract_switch_flow.py"),
            "flows": {k: out[k] for k in sorted(out, key=int)},
        }, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"-> {OUT}  회차 {len(out)}")


class Range:
    def __init__(self, lo: int, hi: int):
        self.lo, self.hi = lo, hi

    def contains(self, addr) -> bool:
        return self.lo <= addr.getOffset() <= self.hi


def iter_range(listing, af, lo: int, hi: int):
    """[lo, hi] 구간 명령 순회 — Ghidra 함수 경계를 믿을 수 없어 주소 범위로 훑는다."""
    cur = listing.getInstructionAt(af.getAddress(lo))
    n = 0
    while cur is not None and n < MAX_SCAN:
        if cur.getAddress().getOffset() > hi:
            return
        yield cur
        cur = listing.getInstructionAfter(cur.getAddress())
        n += 1


def default_is_user_talk(listing, af, body, dflt: int, user_talk_addrs: set) -> bool:
    """default 블록이 `setUserTalk` 로 이어지는가(조건 분기 타깃까지 한 겹 들여다본다)."""
    cur = listing.getInstructionAt(af.getAddress(dflt))
    for _ in range(12):
        if cur is None or not body.contains(cur.getAddress()):
            return False
        if cur.getAddress().getOffset() in user_talk_addrs:
            return True
        for fl in cur.getFlows():
            probe = listing.getInstructionAt(fl)
            for _ in range(6):
                if probe is None or not body.contains(probe.getAddress()):
                    break
                if probe.getAddress().getOffset() in user_talk_addrs:
                    return True
                probe = listing.getInstructionAfter(probe.getAddress())
        cur = listing.getInstructionAfter(cur.getAddress())
    return False


def walk_case(listing, af, fm, body, tgt: int, slots: dict[str, str],
              npc_talk_addr: int, user_talk_addrs: set, text,
              talker_addrs: set | None = None, rostr=None) -> list[dict]:
    """case 블록을 따라가며 슬롯 대입을 모으고, 어떤 대사 호출로 합류하는지 판정."""
    regs: dict[str, int] = {}
    slotval: dict[str, int] = {}
    xptr: dict[str, str] = {}
    pages: dict[str, int] = {}
    last_str = None
    store: dict[str, int] = {}
    ops: list[dict] = []
    cur = listing.getInstructionAt(af.getAddress(tgt))
    seen = set()
    for _ in range(MAX_STEP_INSNS):
        if cur is None or not body.contains(cur.getAddress()):
            break
        a = cur.getAddress().getOffset()
        if a in seen:
            break
        seen.add(a)
        t = text(cur)
        m = re.fullmatch(r"(mov|movz) (w\d+),#(0x[0-9a-f]+|\d+)", t)
        if m:
            regs[m.group(2)] = int(m.group(3), 0)
        m = re.fullmatch(r"orr (w\d+),wzr,#(0x[0-9a-f]+|\d+)", t)
        if m:
            regs[m.group(1)] = int(m.group(2), 0)
        # 슬롯 저장 — 4개 대사 슬롯뿐 아니라 전부 기억한다(배경 번호도 슬롯으로 넘어간다)
        m = re.fullmatch(r"(str|stur) (w\d+|wzr),\[(x29|sp),#(-?0x[0-9a-f]+|-?\d+)\]", t)
        if m:
            key = f"{m.group(3)}{int(m.group(4), 0):+d}"
            val = 0 if m.group(2) == "wzr" else regs.get(m.group(2))
            if val is not None:
                slotval[key] = val
                for name, sl in slots.items():
                    if sl == key:
                        store[name] = val
        # 포인터 인자 준비
        m = re.fullmatch(r"(add|sub) (x\d+),(x29|sp),#(0x[0-9a-f]+|\d+)", t)
        if m:
            sign = -1 if m.group(1) == "sub" else 1
            xptr[m.group(2)] = f"{m.group(3)}{sign * int(m.group(4), 0):+d}"
        # .rodata 문자열 포인터 조립(`adrp x8,PAGE` + `add x8,x8,#OFF`) — 1~78화의
        # `ScenarioLayer::setTalker` 는 NPC 를 **이름 문자열**로 받는다.
        m = re.fullmatch(r"adrp (x\d+),(0x[0-9a-f]+)", t)
        if m:
            pages[m.group(1)] = int(m.group(2), 0)
        m = re.fullmatch(r"add (x\d+),,#(0x[0-9a-f]+|\d+)", t)
        if m and m.group(1) in pages:
            cand = pages[m.group(1)] + int(m.group(2), 0)
            if rostr:
                sv = rostr(cand)
                if sv:
                    last_str = sv
        if cur.getMnemonicString() == "bl":
            if a == npc_talk_addr:
                ops.append({"op": "setNpcTalk", **store})
                return ops
            if a in user_talk_addrs:
                ops.append({"op": "setUserTalk"})
                return ops
            if talker_addrs and a in talker_addrs:
                ops.append({"op": "setTalker", "npc_name": last_str})
                return ops
            fl = cur.getFlows()
            callee = fm.getFunctionAt(fl[0]) if fl else None
            if callee is not None:
                nm = callee.getName()
                if "changeBackGround" in nm:
                    # ⚠️ 2번째 인자는 `BackGruundName*` = 스택 슬롯 포인터다(정수 아님)
                    ops.append({"op": "changeBackGround", "bg": slotval.get(xptr.get("x1", ""))})
                elif "drawIllust" in nm:
                    ops.append({"op": "drawIllust", "illust": regs.get("w1"), "kind": regs.get("w2")})
                elif "setOutTalker" in nm:
                    ops.append({"op": "setOutTalker"})
        if cur.getMnemonicString() == "b":
            fl = cur.getFlows()
            if not fl:
                break
            cur = listing.getInstructionAt(fl[0])
            continue
        if cur.getMnemonicString() == "ret":
            break
        cur = listing.getInstructionAfter(cur.getAddress())
    return ops


if __name__ == "__main__":
    main()

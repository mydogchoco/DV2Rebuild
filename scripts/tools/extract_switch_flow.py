"""switch 형 회차 클래스(`Scenario1`~`Scenario8`) 연출 추출 — **점프 테이블 수준**.

## 왜 별도 도구인가

82~101화(`Scenario_zimon`/`_mamorudic`/`_Kadeath`)는 `initScenarioData` 가 `std::function`
벡터로 스텝을 push 해서 스텝 하나 = 함수 하나였다(→ `extract_scenario_flow.py`).
1~81화(`Scenario1~8`)는 구조가 다르다. `setNext(CCObject*)` 하나가

    step = this->0x158 ;  index = step - 1
    if (index > N) goto default
    target = <base> + table[index] * 4      // table = u16 배열(.rodata)
    br target

로 **점프 테이블**을 타고, 각 case 블록이 스택 슬롯 4개(npc/state/pos/emoticon)에 값을 쓴 뒤
함수 꼬리의 단일 `setNpcTalk` 으로 합류한다. 대사만 넘기는 스텝은 `setUserTalk` 로 간다.

디컴프한 C 로는 복원이 안 된다(2026-07-31 실측):
  · Ghidra 가 본문이 같은 case 라벨을 합쳐 출력한다(라벨 119개 → 주소 63개)
  · switch 블록의 **텍스트 순서와 회차 가드 순서가 일치하지 않는다** — 80화(48스텝)와
    81화(52스텝)를 서로 바꿔 잡고 있었고, 그 상태로도 대사 수가 우연히 맞아 검증을 통과했다.
⇒ 그래서 **디스어셈블 + 점프 테이블**을 직접 읽는다. 회차↔스텝↔값이 주소로 확정된다.

## 산출

`data/scenario_flow_switch.json` — `parse_scenario_flow.py` 가 읽어 합친다.
각 회차: `[{op, npc?, state?, pos?, emoticon?, bg?, illust?}]` (스텝 순서).

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
## 한 case 블록에서 따라갈 최대 명령 수(무한 루프 방지).
MAX_STEP_INSNS = 400


def parse_args(argv):
    classes = []
    if "--all" in argv:
        classes += CLASSES
    if "--classes" in argv:
        classes += [c.strip() for c in argv[argv.index("--classes") + 1].split(",") if c.strip()]
    return classes or CLASSES


def imm(op: str) -> int | None:
    """`#0x22` · `#-0xd0` · `0x1652974` → 정수."""
    m = re.fullmatch(r"#?(-?)(0x[0-9a-fA-F]+|\d+)", op.strip())
    if not m:
        return None
    v = int(m.group(2), 0)
    return -v if m.group(1) else v


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

        def ins_at(off: int):
            return listing.getInstructionAt(af.getAddress(off))

        def text(i) -> str:
            """`sub x1,x29,#0xd0` 형태로 정규화. ⚠️ `getDefaultOperandRepresentation` 은
            `#` 을 빼고 주므로 쓰면 안 된다 — 실제 명령 문자열을 쓴다."""
            return re.sub(r",\s+", ",", re.sub(r"\s+", " ", str(i).strip()))

        funcs = {}
        for f in fm.getFunctions(True):
            q = "::" + f.getName(True)
            for c in classes:
                if f"::{c}::setNext" in q and f.getBody().getNumAddresses() > 100:
                    funcs[c] = f

        out: dict[str, list[dict]] = {}
        for cls, fn in funcs.items():
            body = fn.getBody()
            # ── ① 대사 호출 위치 파악 ─────────────────────────────────────────
            npc_talk_addr = user_talk_addrs = None
            user_talk_addrs = set()
            it = listing.getInstructions(body, True)
            while it.hasNext():
                i = it.next()
                if i.getMnemonicString() != "bl":
                    continue
                fl = i.getFlows()
                if not fl:
                    continue
                callee = fm.getFunctionAt(fl[0])
                if callee is None:
                    continue
                if "setNpcTalk" in callee.getName():
                    npc_talk_addr = i.getAddress().getOffset()
                elif "setUserTalk" in callee.getName():
                    user_talk_addrs.add(i.getAddress().getOffset())
            if npc_talk_addr is None:
                print(f"  {cls}: setNpcTalk 호출 없음 — 건너뜀"); continue

            # 꼬리 호출의 인자 슬롯: x1=npc x2=state x3=pos x4=emoticon
            slots: dict[str, str] = {}
            cur = ins_at(npc_talk_addr)
            for _ in range(24):
                cur = listing.getInstructionBefore(cur.getAddress())
                if cur is None or not body.contains(cur.getAddress()):
                    break
                t = text(cur)
                m = re.fullmatch(r"(sub|add) (x[1-4]),(x29|sp),#(0x[0-9a-f]+|\d+)", t)
                if m:
                    sign = -1 if m.group(1) == "sub" else 1
                    key = {"x1": "npc", "x2": "state", "x3": "pos", "x4": "emoticon"}[m.group(2)]
                    slots.setdefault(key, f"{m.group(3)}{sign * int(m.group(4), 0):+d}")
            if len(slots) < 4:
                print(f"  {cls}: 꼬리 인자 슬롯 {slots} — 건너뜀"); continue

            # ── ② 점프 테이블 3종(회차별) ────────────────────────────────────
            tables = []
            it = listing.getInstructions(body, True)
            while it.hasNext():
                i = it.next()
                if i.getMnemonicString() != "br":
                    continue
                seq, cur = [], i
                for _ in range(14):
                    cur = listing.getInstructionBefore(cur.getAddress())
                    if cur is None:
                        break
                    seq.append(cur)
                seq.reverse()
                tbl = base = count = step_ld = dflt = None
                page = 0
                for s in seq:
                    t = text(s)
                    # 경계 초과 분기 = default 블록. 테이블 밖 **마지막 스텝**이 여기 있다
                    # (원작: `if (step != 0x31) <가상함수> else setUserTalk`).
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
                    if re.fullmatch(r"ldr (w\d+),\[x\d+,#0x158\]", t):
                        step_ld = s.getAddress().getOffset()
                if tbl and base and count and step_ld:
                    tables.append((step_ld, tbl, base, count, dflt))

            # 각 테이블의 회차 = 그 `ldr [.,#0x158]` 로 오는 분기 앞의 `cmp wN,#sn`
            def episode_of(step_ld: int) -> int | None:
                for src in prog.getReferenceManager().getReferencesTo(af.getAddress(step_ld)):
                    b = listing.getInstructionAt(src.getFromAddress())
                    if b is None:
                        continue
                    c = b
                    for _ in range(4):
                        c = listing.getInstructionBefore(c.getAddress())
                        if c is None:
                            break
                        m = re.fullmatch(r"cmp (w\d+),#(0x[0-9a-f]+|\d+)", text(c))
                        if m:
                            return int(m.group(2), 0)
                # 분기 없이 흘러들어오는 경우: 바로 앞 명령들에서 찾는다
                c = listing.getInstructionAt(af.getAddress(step_ld))
                for _ in range(4):
                    c = listing.getInstructionBefore(c.getAddress())
                    if c is None:
                        break
                    m = re.fullmatch(r"cmp (w\d+),#(0x[0-9a-f]+|\d+)", text(c))
                    if m:
                        return int(m.group(2), 0)
                return None

            for step_ld, tbl, base, count, dflt in tables:
                sn = episode_of(step_ld)
                if sn is None:
                    print(f"  {cls}: 테이블 {tbl:#x} 회차 판별 실패"); continue
                flow: list[dict] = []
                for idx in range(count):
                    entry = mem.getShort(af.getAddress(tbl + idx * 2)) & 0xFFFF
                    tgt = base + entry * 4
                    flow.extend(walk_case(listing, af, fm, body, tgt, slots,
                                          npc_talk_addr, user_talk_addrs, text))
                # 테이블 밖 마지막 스텝(default 분기) — 원작은 여기서 `step == <상수>` 일 때만
                # setUserTalk 로 간다. 조건 분기 뒤라 직진 추적으로는 안 잡히므로 따로 훑는다.
                if dflt and default_is_user_talk(listing, af, body, dflt, user_talk_addrs):
                    flow.append({"op": "setUserTalk"})
                out[str(sn)] = flow
                talk = sum(1 for o in flow if o["op"] in ("setNpcTalk", "setUserTalk"))
                print(f"  {cls} ep{sn}: 스텝 {count} · 대사 {talk}")

        OUT.write_text(json.dumps({
            "_re_basis": ("원작 Scenario1~8::setNext 의 점프 테이블을 디스어셈블 수준에서 읽어 "
                          "스텝별 npc/state/pos/emoticon 을 복원. 도구 = extract_switch_flow.py"),
            "flows": {k: out[k] for k in sorted(out, key=int)},
        }, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"-> {OUT}  회차 {len(out)}")


def default_is_user_talk(listing, af, body, dflt: int, user_talk_addrs: set) -> bool:
    """default 블록이 `setUserTalk` 로 이어지는가(조건 분기 타깃까지 훑는다)."""
    cur = listing.getInstructionAt(af.getAddress(dflt))
    for _ in range(12):
        if cur is None or not body.contains(cur.getAddress()):
            return False
        if cur.getAddress().getOffset() in user_talk_addrs:
            return True
        for fl in cur.getFlows():          # 조건 분기 타깃도 한 칸 들여다본다
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
              npc_talk_addr: int, user_talk_addrs: set, text) -> list[dict]:
    """case 블록을 따라가며 슬롯 대입을 모으고, 어떤 대사 호출로 합류하는지 판정."""
    regs: dict[str, int] = {}
    slotval: dict[str, int] = {}
    xptr: dict[str, str] = {}
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
        # 상수 적재
        m = re.fullmatch(r"(mov|movz) (w\d+),#(0x[0-9a-f]+|\d+)", t)
        if m:
            regs[m.group(2)] = int(m.group(3), 0)
        m = re.fullmatch(r"orr (w\d+),wzr,#(0x[0-9a-f]+|\d+)", t)
        if m:
            regs[m.group(1)] = int(m.group(2), 0)
        # 슬롯 저장 — 4개 대사 슬롯뿐 아니라 **전부** 기억한다(배경 번호도 슬롯으로 넘어간다)
        m = re.fullmatch(r"(str|stur) (w\d+|wzr),\[(x29|sp),#(-?0x[0-9a-f]+|-?\d+)\]", t)
        if m:
            key = f"{m.group(3)}{int(m.group(4), 0):+d}"
            val = 0 if m.group(2) == "wzr" else regs.get(m.group(2))
            if val is not None:
                slotval[key] = val
                for name, sl in slots.items():
                    if sl == key:
                        store[name] = val
        # 포인터 인자 준비 — `add x1,sp,#0x1d8` / `sub x1,x29,#0xd0`
        m = re.fullmatch(r"(add|sub) (x\d+),(x29|sp),#(0x[0-9a-f]+|\d+)", t)
        if m:
            sign = -1 if m.group(1) == "sub" else 1
            xptr[m.group(2)] = f"{m.group(3)}{sign * int(m.group(4), 0):+d}"
        # 호출
        if cur.getMnemonicString() == "bl":
            if a == npc_talk_addr:
                ops.append({"op": "setNpcTalk", **store})
                return ops
            if a in user_talk_addrs:
                ops.append({"op": "setUserTalk"})
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
        # 흐름
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

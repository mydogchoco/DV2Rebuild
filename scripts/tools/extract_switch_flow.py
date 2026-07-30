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
            """`br` 앞 명령들에서 점프 테이블 정보를 읽는다.

            ⚠️ 조회창은 **넉넉히** 잡아야 한다. `Scenario1` 은 `ldr [.,#0x158]` 와 `br` 사이에
            레지스터 준비 명령이 20개나 끼어 있어, 16칸만 보면 스텝 테이블을 통째로 놓친다
            (그래서 "1~78화엔 스텝 분기가 없다"고 오판했었다).
            창 안에서는 **정방향**으로 읽고, 기준이 되는 `ldr` 뒤에 처음 나오는
            cmp/b.hi/adrp+add/adr 만 취한다(뒤쪽의 다른 스위치 값이 섞이지 않게).
            """
            win, cur = [], br_ins
            for _ in range(48):
                cur = listing.getInstructionBefore(cur.getAddress())
                if cur is None:
                    break
                win.append(cur)
            win.reverse()
            kind = step_ld = None
            start = 0
            for idx, s2 in enumerate(win):
                m = re.fullmatch(r"ldr (w\d+),\[x\d+,#(0x[0-9a-f]+)\]", text(s2))
                if not m:
                    continue
                off = int(m.group(2), 0)
                if off == OFF_SN:
                    kind, start = "sn", idx
                elif off == OFF_STEP:
                    kind, start, step_ld = "step", idx, s2.getAddress().getOffset()
            if kind is None:
                return None
            tbl = base = count = dflt = None
            page = shift = 0
            for s2 in win[start:]:
                t = text(s2)
                if dflt is None:
                    m = re.fullmatch(r"b\.hi (0x[0-9a-f]+)", t)
                    if m:
                        dflt = int(m.group(1), 0)
                m = re.fullmatch(r"adrp (x\d+),(0x[0-9a-f]+)", t)
                if m:
                    page = int(m.group(2), 0)
                if tbl is None:
                    m = re.fullmatch(r"add (x\d+),\1,#(0x[0-9a-f]+|\d+)", t)
                    if m and page:      # `\1` 역참조라 그룹은 (레지스터, 즉값) 둘뿐이다
                        tbl = page + int(m.group(2), 0)
                if base is None:
                    m = re.fullmatch(r"adr (x\d+),(0x[0-9a-f]+)", t)
                    if m:
                        base = int(m.group(2), 0)
                if count is None:
                    m = re.fullmatch(r"cmp (w\d+),#(0x[0-9a-f]+|\d+)", t)
                    if m:
                        count = int(m.group(2), 0) + 1
                m = re.fullmatch(r"sub (w\d+),(w\d+),#(0x[0-9a-f]+|\d+)", t)
                if m:
                    shift = int(m.group(3), 0)
            if tbl and base and count:
                return {"kind": kind, "tbl": tbl, "base": base, "count": count, "dflt": dflt,
                        "shift": shift, "step_ld": step_ld,
                        "at": br_ins.getAddress().getOffset()}
            return None

        def rostr(addr: int):
            """그 주소가 짧은 ASCII C 문자열이면 돌려준다(NPC 폴더 이름 후보).
            1~78화의 `ScenarioLayer::setTalker` 는 NPC 를 **이름 문자열**로 받는다."""
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

        def discover(entry: int, body_end: int, cap: int):
            """실제 코드 범위와 점프 테이블 전부를 찾는다(꼬리가 짧게 잡히는 문제 회피).

            ⚠️ 종료 조건은 **테이블 근거로 넓힌 도달 범위**로 판단한다. 예전에는 `hi` 를 매
            명령마다 갱신해서 조건이 영원히 거짓이 됐고, 그대로 바이너리 끝까지 훑었다
            (Scenario8 를 스캔하는데 0x178xxxx 의 남의 함수 `br` 을 읽고 있었다).
            """
            reach = max(body_end, entry + 0x400)
            tables = []
            cur, n = at(entry), 0
            while cur is not None and n < MAX_SCAN:
                a = cur.getAddress().getOffset()
                if a > min(reach + 0x800, cap):
                    break
                if cur.getMnemonicString() == "br":
                    t = read_table(cur)
                    if t:
                        tables.append(t)
                        for i in range(t["count"]):
                            reach = max(reach, entry_target(t, i))
                        if t["dflt"]:
                            reach = max(reach, t["dflt"])
                cur = listing.getInstructionAfter(cur.getAddress())
                n += 1
            return entry, min(reach + 0x400, cap), tables

        funcs = {}
        # 다른 Scenario 클래스 코드로 넘어가지 않도록 하드 상한을 둔다
        # (Ghidra 가 꼬리를 짧게 잡아 범위를 넓히다 보면 이웃 클래스까지 삼킨다).
        scenario_entries = []
        for f in fm.getFunctions(True):
            q = "::" + f.getName(True)
            if "::Scenario" in q:
                cls_name = f.getName(True).rsplit("::", 2)[-2] if "::" in f.getName(True) else ""
                scenario_entries.append((f.getEntryPoint().getOffset(), cls_name))
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
            # 이웃 Scenario 클래스로 넘어가지 않도록 하드 상한. Ghidra 가 setNext 를 여러 조각으로
            # 쪼개 놓아서 **같은 클래스의 다른 진입점**은 상한에서 뺀다.
            # ⚠️ 같은 클래스의 다른 조각(Ghidra 가 setNext 를 쪼갠 것)은 상한이 아니다.
            #    종전에는 이걸 남으로 봐서 범위를 entry+0x100 수준으로 잘랐고,
            #    그 바람에 스텝 테이블이 통째로 범위 밖이 됐다.
            cap = next((e for e, c in scenario_entries
                        if e > entry + 0x40 and c != cls), entry + 0x40000)
            body_end = entry + fn.getBody().getNumAddresses()
            lo, hi, tables = discover(entry, body_end, cap)

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

            def table_from_block(start: int):
                """회차 블록 시작에서 **제어 흐름을 따라가** 그 회차의 스텝 테이블을 찾는다.

                ⚠️ 주소 근접("가장 가까운 앞선 블록 시작")으로 귀속하면 틀린다 —
                   컴파일러가 회차 코드를 뒤섞어 배치해서, 같은 표가 여러 회차로 붙었다
                   (Scenario7 에서 ep63/68/61/76/69 가 전부 같은 표로 나왔다).
                   블록에서 실제로 **도달하는** 표만이 그 회차의 것이다.
                """
                # ⚠️ 예산이 짧으면 도달 전에 끊긴다 — Scenario1 은 회차 블록 시작에서
                #    스텝 분기까지 550명령쯤 간다.
                seen: set[int] = set()
                stack = [start]
                while stack:
                    a0 = stack.pop()
                    if a0 in seen:
                        continue
                    cur2 = at(a0)
                    for _ in range(4000):
                        if cur2 is None:
                            break
                        a1 = cur2.getAddress().getOffset()
                        if a1 in seen or not (lo <= a1 <= hi):
                            break
                        seen.add(a1)
                        mn = cur2.getMnemonicString()
                        if mn == "br":
                            t2 = read_table(cur2)
                            if t2 and t2["kind"] == "step":
                                return t2
                            break        # 다른 스위치 — 이 경로는 여기서 끝, 다른 경로 계속
                        if mn == "ret":
                            break
                        if mn == "b":                      # 무조건 분기 — 따라간다
                            fl2 = cur2.getFlows()
                            if not fl2:
                                break
                            cur2 = listing.getInstructionAt(fl2[0])
                            continue
                        if mn.startswith("b.") or mn.startswith("cb") or mn.startswith("tb"):
                            for f2 in cur2.getFlows():     # 조건 분기 — 타깃도 훑는다
                                stack.append(f2.getOffset())
                        cur2 = listing.getInstructionAfter(cur2.getAddress())
                return None

            def episode_of(step_tbl: dict) -> int | None:
                """스텝 테이블이 속한 회차 — sn 테이블이 없을 때(Scenario8)의 폴백."""
                if sn_blocks:
                    return None
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
            # 회차 → 스텝 테이블. sn 테이블이 있으면 **블록에서 도달하는 표**로 묶고,
            # 없으면(Scenario8) 표에서 가드를 거꾸로 찾는다.
            #
            # 🔴 **Scenario1~7 은 이 모델로 안 된다(2026-07-31 실측).**
            #    Scenario1 실측: sn 테이블이 **4개**(각 10엔트리) 나오고 스텝 테이블은 **1개뿐**인데
            #    그 크기가 82다. 회차 9개에 표 하나 ⇒ "회차 하나 = 스텝 표 하나"가 아니라
            #    **한 표를 회차들이 공유하고 case 블록 안에서 다시 sn 으로 갈린다.**
            #    그래서 회차 귀속을 어떻게 하든 같은 표가 여러 회차로 붙거나(주소 근접),
            #    아무 회차도 못 찾는다(도달성). 제대로 하려면 case 블록 **안의 sn 분기**까지
            #    따라가야 한다 — 다음 작업 지점.
            #    Scenario8 은 회차가 3개뿐이라 표도 3개로 갈려 있어 이 모델이 통한다.
            pairs: list[tuple[int, dict]] = []
            if sn_blocks:
                for sn0 in sorted(sn_blocks):
                    t0 = table_from_block(sn_blocks[sn0])
                    if t0 is not None:
                        pairs.append((sn0, t0))
            else:
                for t0 in tables:
                    if t0["kind"] != "step":
                        continue
                    sn0 = episode_of(t0)
                    if sn0 is None:
                        print(f"  {cls}: 스텝 테이블 {t0['tbl']:#x} 회차 판별 실패"); continue
                    pairs.append((sn0, t0))

            for sn, t in pairs:
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

        # ⚠️ 단일 클래스로 돌려도 **기존 산출물을 지우지 않는다** — 종전에는
        #    `--classes Scenario1` 한 번에 79~81 화가 통째로 날아갔다.
        if OUT.exists():
            try:
                prev = json.loads(OUT.read_text(encoding="utf-8")).get("flows", {})
            except Exception:
                prev = {}
            for k, v in prev.items():
                out.setdefault(k, v)
        OUT.write_text(json.dumps({
            "_re_basis": ("원작 Scenario1~8::setNext 의 두 겹 점프 테이블(회차→스텝)을 디스어셈블 "
                          "수준에서 읽어 스텝별 npc/state/pos/emoticon 을 복원. "
                          "도구 = scripts/tools/extract_switch_flow.py"),
            "flows": {k: out[k] for k in sorted(out, key=int)},
        }, ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"-> {OUT}  회차 {len(out)}")


def _same_class(fn, addr_off: int, fm) -> bool:
    """`addr_off` 의 함수가 `fn` 과 같은 클래스인가(Ghidra 가 쪼갠 조각 구분용)."""
    try:
        other = fm.getFunctionAt(fn.getEntryPoint().getNewAddress(addr_off))
    except Exception:
        return False
    if other is None:
        return False
    a = fn.getName(True).rsplit("::", 1)[0]
    b = other.getName(True).rsplit("::", 1)[0]
    return a == b


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
    xstr: dict[str, str] = {}
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
        m = re.fullmatch(r"add (x\d+),\1,#(0x[0-9a-f]+|\d+)", t)
        if m and m.group(1) in pages:      # `` 역참조 → 그룹은 (레지스터, 즉값)
            cand = pages[m.group(1)] + int(m.group(2), 0)
            if rostr:
                sv = rostr(cand)
                if sv:
                    last_str = sv
                    xstr[m.group(1)] = sv
        # 레지스터 간 복사(문자열 포인터가 x2 로 옮겨진다)
        m = re.fullmatch(r"mov (x\d+),(x\d+)", t)
        if m and m.group(2) in xstr:
            xstr[m.group(1)] = xstr[m.group(2)]
        if cur.getMnemonicString() == "bl":
            if a == npc_talk_addr:
                ops.append({"op": "setNpcTalk", **store})
                return ops
            if a in user_talk_addrs:
                ops.append({"op": "setUserTalk"})
                return ops
            if talker_addrs and a in talker_addrs:
                # AAPCS: x0=this · w1=bool · x2=이름 문자열 · w3=body · w4=state
                # (원작 `ScenarioLayer::setTalker(bool, string, int body, int state, float×4, …)`)
                ops.append({"op": "setTalker",
                            "npc_name": xstr.get("x2", last_str),
                            "body": regs.get("w3"), "state": regs.get("w4")})
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

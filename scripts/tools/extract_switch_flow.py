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

## 대사 함수가 **셋**이다 (2026-07-31 확정)

    ScenarioSupport::setNpcTalk(NPC_NAME*, Character_State*, …)   번호로 받는다
    ScenarioSupport::setUserTalk(bool)                            주인공 지문
    ScenarioLayer::setTalker(bool, string, int body, int state…)  이름 문자열을 인자로
    ScenarioLayer::setTalk(bool)                                  ← 이름을 **멤버에 써 두고** 부른다
        adrp/add x1=<이름> ; add x0,this,#0x1f0 ; assign ; setTalk(this, true)

넷째(`setTalk`)를 이름 정확일치로 거르다 놓쳐서 Scenario7 68~78화가 통째로 "대사 0" 이었다.

사용:
    python scripts/tools/extract_switch_flow.py --classes Scenario8
    python scripts/tools/extract_switch_flow.py --all
    python scripts/tools/extract_switch_flow.py --classes Scenario7 --debug-tables  # 검출된 표
    python scripts/tools/extract_switch_flow.py --classes Scenario7 --debug-eps     # 회차별 귀속
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
## 대사를 띄우는 `ScenarioLayer` 메서드 — 원작에 **다섯 가지**가 있다(전수 열거:
##   `grep -oh "==== [A-Za-z_]*[Tt]alk[A-Za-z_]* @" decomp/ScenarioLayer.c`).
## 공통 규약: 부르기 전에 문자열 두 개를 멤버에 써 둔다.
##     this+0x1d8 = 화자 이름 · this+0x1f0 = 대사 문자열 키(`ScenarioTalk<회차>_<줄>`)
## ⚠️ 이름으로 하나씩 쫓다가 `setTalk`(68~78화) → `setReorderTalker`(1~9화) 순으로
##    두 번 놓쳤다. 이제 **멤버 대입**을 기준으로 잡고 이 집합은 보조로만 쓴다.
TALK_FNS = {"setTalk", "setTalker", "setReorderTalker", "setMoveTalker",
            "setTalkForNotClick", "setTalkForTalker"}
OFF_NAME, OFF_KEY = 0x1d8, 0x1f0

## 한 case 블록에서 따라갈 최대 명령 수 / 범위 탐색 상한.
MAX_STEP_INSNS, MAX_SCAN = 400, 300000


## 미해석 구간을 건너뛰지 않는 명령 순회 — `main()` 이 Ghidra 핸들을 채운다.
##
## 🔴 모듈 수준 헬퍼(`iter_range`/`walk_case`/`default_is_user_talk`)도 **반드시** 이 경로를
##    써야 한다. Ghidra 가 `setNext` 를 짧게 잡아 회차 case 블록을 미해석 바이트로 남기는데,
##    `listing.getInstructionAfter` 는 그 구간을 조용히 건너뛴다 ⇒ case 블록 본문(대사 호출
##    포함)이 통째로 안 보인다. `main()` 안만 고치고 여기를 안 고치면 표는 읽히는데
##    **본문이 비어** "스텝 0 · 대사 0" 이 된다.
NAV: dict = {}


def nav_at(off: int):
    fn = NAV.get("at")
    return fn(off) if fn is not None else None


def nav_after(ins):
    return nav_at(ins.getAddress().getOffset() + ins.getLength())


def nav_before(ins):
    return nav_at(ins.getAddress().getOffset() - 4)   # ARM64 고정폭 4바이트


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
            """그 주소의 명령. **없으면 강제로 해석한다.**

            🔴 1~78화가 안 나오던 진짜 원인이 여기였다(2026-07-31 확정).
               Ghidra 는 `Scenario1::setNext` 를 size=312 로 잡아 그 뒤 **회차 case 블록 전부를
               미해석 바이트로 남긴다.** `getInstructionAfter` 는 미해석 구간을 **조용히
               건너뛰므로**, 걸어가 보면 스텝 분기(`ldr [.,#0x158]` → 점프 테이블)가
               통째로 안 보인다 ⇒ "스텝 분기가 없다"는 오판.
               실제로는 회차 블록마다 표준형 스텝 스위치가 멀쩡히 있다:
                   ldr x8,[sp,#0x50] ; ldr w8,[x8,#0x158] ; sub w8,w8,#1
                   cmp w8,#N ; b.hi <default> ; ldrh w11,[x9,x8,LSL #1] ; br x10
               (ARM64 는 4바이트 고정·정렬이라 강제 해석이 안전하다.)
            """
            a0 = af.getAddress(off)
            ins = listing.getInstructionAt(a0)
            if ins is None:
                try:
                    flat.disassemble(a0)
                except Exception:                       # noqa: BLE001 — 데이터 구간이면 실패해도 됨
                    return None
                ins = listing.getInstructionAt(a0)
            return ins

        NAV["at"] = at

        def after(ins):
            """다음 명령 — **주소를 직접 더해** 미해석 구간을 건너뛰지 않게 한다."""
            return at(ins.getAddress().getOffset() + ins.getLength())

        def before(ins):
            """앞 명령 — ARM64 고정폭이므로 4바이트 앞을 강제 해석해서 본다."""
            return at(ins.getAddress().getOffset() - 4)

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
            for _ in range(96):
                cur = before(cur)
                if cur is None:
                    break
                win.append(cur)
            win.reverse()
            rev = list(reversed(win))     # br 바로 앞부터 거슬러 올라간다
            # ── ① 엔트리 로드에서 **레지스터를 확정**한다 ────────────────────────
            #     ldrh w11,[x9, x8, LSL #0x1]   → 표 레지스터 x9 · 인덱스 레지스터 w8 · 폭 2
            #
            # 🔴 이 앵커가 없으면 조회가 통째로 어긋난다(2026-07-31 실측). 종전에는 `br` 에서
            #    거슬러 첫 `add xN,xN,#imm` 을 adrp 짝으로 삼았는데, 그 자리에 있는 건
            #    **스택 셋업**(`add x24,x24,#0x570`)이다 — 짝 `adrp x24` 가 없으니 tbl 이
            #    None 이 되고 표가 통째로 버려졌다. 그래서 Scenario3~7 의 회차(sn) 표가
            #    한 개도 안 잡혔다. 표 레지스터는 엔트리 로드가 정확히 알려 준다.
            width, tbl_reg, idx_reg = 2, None, None
            for s2 in rev:
                m = re.fullmatch(r"ldr(b|h|sw) w\d+,\[(x\d+),[xw](\d+).*", text(s2))
                if m:
                    width = {"b": 1, "h": 2, "sw": 4}[m.group(1)]
                    tbl_reg, idx_reg = m.group(2), "w" + m.group(3)
                    break
            if tbl_reg is None:
                return None
            # ── ② 표 주소 = adrp/add 쌍(그 레지스터의 것만) · 기준 주소 = adr ─────
            tbl = base = count = dflt = None
            add_imm = None
            cmp_at = None
            shift = 0
            for k, s2 in enumerate(rev):
                t = text(s2)
                if dflt is None:
                    m = re.fullmatch(r"b\.hi (0x[0-9a-f]+)", t)
                    if m:
                        dflt = int(m.group(1), 0)
                if base is None:
                    m = re.fullmatch(r"adr (x\d+),(0x[0-9a-f]+)", t)
                    if m:
                        base = int(m.group(2), 0)
                if add_imm is None:
                    m = re.fullmatch(rf"add {tbl_reg},{tbl_reg},#(0x[0-9a-f]+|\d+)", t)
                    if m:
                        add_imm = int(m.group(1), 0)
                if tbl is None and add_imm is not None:
                    m = re.fullmatch(rf"adrp {tbl_reg},(0x[0-9a-f]+)", t)
                    if m:
                        tbl = int(m.group(1), 0) + add_imm
                if count is None:
                    m = re.fullmatch(rf"cmp {idx_reg},#(0x[0-9a-f]+|\d+)", t)
                    if m:
                        count, cmp_at = int(m.group(1), 0) + 1, k
            # ── ③ 시프트(`sub idx,src,#imm`)와 그 원본 레지스터 ──────────────────
            src_reg = idx_reg
            if cmp_at is not None:
                for s2 in rev[cmp_at + 1:cmp_at + 6]:
                    m = re.fullmatch(rf"sub {idx_reg},(w\d+),#(0x[0-9a-f]+|\d+)", text(s2))
                    if m:
                        src_reg, shift = m.group(1), int(m.group(2), 0)
                        break
            # ── ④ 종류 = **그 원본 레지스터를 채운** `ldr wN,[x?,#0x158|0x168]` ──
            #     위치(창 안 마지막)로 정하면 안 된다 — 미해석 구간을 강제 해석하면서
            #     창에 남의 스텝 로드가 더 보이자 sn 표가 전부 step 으로 뒤집혔다.
            kind, step_ld = None, None
            for s2 in rev:
                m = re.fullmatch(rf"ldr {src_reg},\[x\d+,#(0x[0-9a-f]+)\]", text(s2))
                if not m:
                    continue
                off = int(m.group(1), 0)
                if off not in (OFF_SN, OFF_STEP):
                    continue
                kind = "sn" if off == OFF_SN else "step"
                step_ld = s2.getAddress().getOffset() if off == OFF_STEP else None
                break
            if kind is None:
                return None
            if tbl and base and count:
                return {"kind": kind, "tbl": tbl, "base": base, "count": count, "dflt": dflt,
                        "shift": shift, "step_ld": step_ld, "width": width,
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
            """테이블 엔트리 → 타깃 주소. **엔트리 폭은 표마다 다르다**(`ldrb`/`ldrh`/`ldrsw`)."""
            w = t.get("width", 2)
            a = af.getAddress(t["tbl"] + idx * w)
            if w == 1:
                v = mem.getByte(a) & 0xFF
            elif w == 4:
                v = mem.getInt(a)
            else:
                v = mem.getShort(a) & 0xFFFF
            return t["base"] + v * 4

        def discover(entry: int, body_end: int, cap: int):
            """실제 코드 범위와 점프 테이블 전부를 찾는다(꼬리가 짧게 잡히는 문제 회피).

            ⚠️ 종료 조건은 **테이블 근거로 넓힌 도달 범위**로 판단한다. 예전에는 `hi` 를 매
            명령마다 갱신해서 조건이 영원히 거짓이 됐고, 그대로 바이너리 끝까지 훑었다
            (Scenario8 를 스캔하는데 0x178xxxx 의 남의 함수 `br` 을 읽고 있었다).
            """
            reach = max(body_end, entry + 0x400)
            tables = []
            seen_br: set[int] = set()
            # 🔴 **고정점까지 반복**한다. 한 번만 훑으면 `a > reach + 0x800` 에서 멈추는데,
            #    그 시점의 reach 는 그때까지 본 표만 반영한다 — 뒤쪽 회차의 case 블록이
            #    범위 밖으로 잘리고, 그 블록 안의 대사 호출 주소도 talker_addrs 에 안 들어가
            #    walk_case 가 **아무 대사도 못 알아본다**(Scenario7 68~78화가 전부 "대사 0"
            #    이었던 이유). 새 표가 안 나올 때까지 넓혀 가며 다시 훑는다.
            for _ in range(8):
                grew = False
                cur, n = at(entry), 0
                while cur is not None and n < MAX_SCAN:
                    a = cur.getAddress().getOffset()
                    if a > min(reach + 0x800, cap):
                        break
                    if cur.getMnemonicString() == "br" and a not in seen_br:
                        t = read_table(cur)
                        if t:
                            seen_br.add(a)
                            tables.append(t)
                            for i in range(t["count"]):
                                tgt = entry_target(t, i)
                                if tgt > reach:
                                    reach, grew = tgt, True
                            if t["dflt"] and t["dflt"] > reach:
                                reach, grew = t["dflt"], True
                    cur = after(cur)
                    n += 1
                if not grew:
                    break
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
            # 🔴 `setNpcTalk` 호출 지점은 **여럿이다.** 종전에는 단일 변수라 마지막 하나만
            #    남았고, 다른 지점으로 합류하는 스텝은 대사로 인식되지 않았다 —
            #    회차마다 대사가 절반쯤 빠지던 원인(ep63 25/46 · ep59 10/22).
            npc_talk_addrs: set[int] = set()
            npc_talk_addr = None
            user_talk_addrs, talker_addrs, talk_addrs = set(), set(), set()
            for i in iter_range(at, after, lo, hi):
                if i.getMnemonicString() != "bl":
                    continue
                fl = i.getFlows()
                callee = fm.getFunctionAt(fl[0]) if fl else None
                if callee is None:
                    continue
                nm = callee.getName()
                if "setNpcTalk" in nm:
                    npc_talk_addrs.add(i.getAddress().getOffset())
                    npc_talk_addr = i.getAddress().getOffset()
                elif "setUserTalk" in nm:
                    user_talk_addrs.add(i.getAddress().getOffset())
                elif nm in TALK_FNS:
                    # 🔴 `setTalk` 는 `setTalker` 와 **다른 함수**이고, 넘기는 문자열도 다르다.
                    #    이름 정확일치만 보다가 놓쳐서 Scenario7 68~78화가 "대사 0" 이었다.
                    #
                    #      adrp/add x1=<대사 키> ; add x0,this,#0x1f0
                    #      → basic_string::assign(this+0x1f0, 키)
                    #      → ScenarioLayer::setTalk(this, true)
                    #
                    #    ⚠️ 그 문자열은 NPC 이름이 아니라 **대사 문자열 키**(`ScenarioTalk60_1`)다.
                    #       화자로 쓰면 이름칸에 키가 찍힌다 — 별도 op 로 뺀다.
                    #       대신 이 경로는 **줄 번호가 확정**된다(순서 추정이 필요 없다).
                    talk_addrs.add(i.getAddress().getOffset())
            if npc_talk_addr is None and not talker_addrs and not talk_addrs:
                names = {}
                for i in iter_range(at, after, lo, hi):
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
                cur = before(cur)
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
                            cur2 = at(fl2[0].getOffset())
                            continue
                        if mn.startswith("b.") or mn.startswith("cb") or mn.startswith("tb"):
                            for f2 in cur2.getFlows():     # 조건 분기 — 타깃도 훑는다
                                stack.append(f2.getOffset())
                        cur2 = after(cur2)
                return None

            def chain_from_block(start: int) -> dict[int, int]:
                """회차 블록에서 **스텝 비교 체인**을 따라 `{스텝번호: 블록주소}` 를 만든다.

                스텝이 적은 회차는 컴파일러가 점프 테이블 대신 비교 체인으로 낮춘다
                (실측: Scenario7 20회차 중 표가 잡히는 건 63·78 둘뿐).
                두 형태를 다 받는다:
                    cmp step,#N ; b.eq <스텝블록>      → 그 타깃이 스텝 본문
                    cmp step,#N ; b.ne <다음비교>      → 폴스루가 스텝 본문
                """
                out2: dict[int, int] = {}
                stepreg: str | None = None
                last: tuple[str, int] | None = None
                cur3 = at(start)
                seen3: set[int] = set()
                for _ in range(3000):
                    if cur3 is None:
                        break
                    a3 = cur3.getAddress().getOffset()
                    if a3 in seen3 or not (lo <= a3 <= hi):
                        break
                    seen3.add(a3)
                    t3 = text(cur3)
                    m3 = re.fullmatch(r"ldr (w\d+),\[x\d+,#0x158\]", t3)
                    if m3:
                        stepreg = m3.group(1)
                        last = None
                        cur3 = after(cur3)
                        continue
                    m3 = re.fullmatch(r"cmp (w\d+),#(0x[0-9a-f]+|\d+)", t3)
                    if m3:
                        last = (m3.group(1), int(m3.group(2), 0))
                        cur3 = after(cur3)
                        continue
                    m3 = re.fullmatch(r"b\.(eq|ne) (0x[0-9a-f]+)", t3)
                    if m3 and last and stepreg and last[0] == stepreg:
                        tgt3 = int(m3.group(2), 0)
                        nxt = after(cur3)
                        nxa = nxt.getAddress().getOffset() if nxt is not None else None
                        if m3.group(1) == "eq":
                            out2.setdefault(last[1], tgt3)
                            cur3 = nxt                      # 체인은 폴스루로 이어진다
                        else:
                            if nxa is not None:
                                out2.setdefault(last[1], nxa)
                            cur3 = at(tgt3)                 # 다음 비교로 점프
                        last = None
                        continue
                    if cur3.getMnemonicString() in ("br", "ret"):
                        break
                    if cur3.getMnemonicString() == "b":     # 무조건 분기는 따라간다
                        fl3 = cur3.getFlows()
                        cur3 = at(fl3[0].getOffset()) if fl3 else None
                        continue
                    cur3 = after(cur3)
                return out2

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
                        c = before(c)
                        if c is None:
                            return None
                        m = re.fullmatch(r"cmp (w\d+),#(0x[0-9a-f]+|\d+)", text(c))
                        if m:
                            return int(m.group(2), 0)
                    return None
                for src in prog.getReferenceManager().getReferencesTo(af.getAddress(sld)):
                    b = at(src.getFromAddress().getOffset())
                    if b is not None:
                        v = cmp_before(b)
                        if v is not None:
                            return v
                v = cmp_before(at(sld))          # 분기 없이 흘러들어오는 경우
                return v
                return None

            if "--debug-tables" in sys.argv:
                print(f"  [{cls}] 범위 {lo:#x}~{hi:#x} · 표 {len(tables)}")
                for t0 in tables:
                    print(f"     br@{t0['at']:#x} {t0['kind']:4} tbl={t0['tbl']:#x} "
                          f"n={t0['count']} shift={t0['shift']} w={t0.get('width')}")
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
            step_tables = [t0 for t0 in tables if t0["kind"] == "step"]
            if sn_blocks:
                # 🔴 회차 블록마다 **자기 스텝 분기**가 있다(2026-07-31 디스어셈블 확인).
                #    Scenario7 진입부: `ldr w9,[x0,#0x168]` → `sub w8,w9,#0x3b`(sn-59)
                #    → `cmp w8,#0x13`(20개) → 회차 테이블 0x2244360 → 회차 블록.
                #    그 블록 안에서 다시 `ldr [.,#0x158]` 스텝 분기를 탄다.
                #    ⇒ "표 공유" 가정은 폐기. 블록에서 **도달하는** 표만 그 회차의 것이다.
                for sn0 in sorted(sn_blocks):
                    t0 = table_from_block(sn_blocks[sn0])
                    if t0 is not None:
                        pairs.append((sn0, t0))
                        continue
                    ch = chain_from_block(sn_blocks[sn0])
                    if ch:
                        pairs.append((sn0, {"kind": "chain", "steps": ch, "dflt": None}))
                    else:
                        print(f"  {cls} ep{sn0}: 스텝 분기 못 찾음")
            else:
                for t0 in tables:
                    if t0["kind"] != "step":
                        continue
                    sn0 = episode_of(t0)
                    if sn0 is None:
                        print(f"  {cls}: 스텝 테이블 {t0['tbl']:#x} 회차 판별 실패"); continue
                    pairs.append((sn0, t0))

            TALK_OPS = ("setNpcTalk", "setUserTalk", "setTalker", "setTalk")
            for sn, tt in pairs:
                cands = tt if isinstance(tt, list) else [tt]
                best: list[dict] = []
                best_t = None
                for t in cands:
                    f0: list[dict] = []
                    if t.get("kind") == "chain":
                        addrs = [t["steps"][k] for k in sorted(t["steps"])]
                    else:
                        addrs = [entry_target(t, i) for i in range(t["count"])]
                    for a4 in addrs:
                        n0 = len(f0)
                        f0.extend(walk_case(at, after, fm, body, a4, slots,
                                            npc_talk_addrs, user_talk_addrs, text,
                                            talker_addrs=talker_addrs, rostr=rostr,
                                            talk_addrs=talk_addrs, want_sn=None))
                        if f"--dump-ep={sn}" in sys.argv:
                            print(f"     [step] {a4:#x} -> {f0[n0:] or '(없음)'}")
                    if sum(1 for o in f0 if o["op"] in TALK_OPS) >                        sum(1 for o in best if o["op"] in TALK_OPS):
                        best, best_t = f0, t
                flow, t = best, (best_t or cands[0])
                if t.get("dflt") and default_is_user_talk(at, after, body, t["dflt"], user_talk_addrs):
                    flow.append({"op": "setUserTalk"})
                out[str(sn)] = flow
                talk = sum(1 for o in flow if o["op"] in TALK_OPS)
                nstep = len(t["steps"]) if t.get("kind") == "chain" else t["count"]
                if "--debug-eps" in sys.argv:
                    a0 = (t["steps"][sorted(t["steps"])[0]] if t.get("kind") == "chain"
                          else entry_target(t, 0))
                    print(f"     [dbg] ep{sn} tbl={t.get('tbl', 0):#x} 첫타깃={a0:#x} "
                          f"범위={lo:#x}~{hi:#x} in={lo <= a0 <= hi}")
                print(f"  {cls} ep{sn}: 스텝 {nstep} · 대사 {talk}"
                      f"{' (체인)' if t.get('kind') == 'chain' else ''}")

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


def iter_range(_at, _after, lo: int, hi: int):
    """[lo, hi] 구간 명령 순회 — Ghidra 함수 경계를 믿을 수 없어 주소 범위로 훑는다."""
    cur = nav_at(lo)
    n = 0
    while cur is not None and n < MAX_SCAN:
        if cur.getAddress().getOffset() > hi:
            return
        yield cur
        cur = nav_after(cur)
        n += 1


def default_is_user_talk(_at, _after, body, dflt: int, user_talk_addrs: set) -> bool:
    """default 블록이 `setUserTalk` 로 이어지는가(조건 분기 타깃까지 한 겹 들여다본다)."""
    cur = nav_at(dflt)
    for _ in range(12):
        if cur is None or not body.contains(cur.getAddress()):
            return False
        if cur.getAddress().getOffset() in user_talk_addrs:
            return True
        for fl in cur.getFlows():
            probe = nav_at(fl.getOffset())
            for _ in range(6):
                if probe is None or not body.contains(probe.getAddress()):
                    break
                if probe.getAddress().getOffset() in user_talk_addrs:
                    return True
                probe = nav_after(probe)
        cur = nav_after(cur)
    return False


def walk_case(_at, _after, fm, body, tgt: int, slots: dict[str, str],
              npc_talk_addrs: set, user_talk_addrs: set, text,
              talker_addrs: set | None = None, rostr=None,
              talk_addrs: set | None = None,
              want_sn: int | None = None) -> list[dict]:
    """case 블록을 따라가며 슬롯 대입을 모으고, 어떤 대사 호출로 합류하는지 판정.

    ## 조건 분기 (2026-07-31)

    🔴 종전에는 **폴스루만** 따라갔다. 대사 호출이 taken 쪽에 있으면 그 스텝은 통째로
       빠졌고, 그게 1~78화 부족분(중앙값 6줄)의 정체였다.
       이제 조건 분기를 만나면 **타깃을 대기열에 넣고** 폴스루를 계속 간다.
       주 경로가 대사 없이 끝나면 대기열에서 꺼내 이어 간다(BFS).

    ⚠️ 대사 op 은 **하나만** 낸다(스텝 하나 = 대사 한 줄). 첫 대사 호출에서 즉시 끝낸다.
       배경/삽화 같은 부수 op 은 **주 경로에서만** 모은다 — 갈래마다 모으면 중복된다.

    `want_sn` 을 주면 블록 안의 회차 분기(`cmp <sn레지스터>,#K`)에서 그 회차 경로만 탄다.
    """
    TALK_SIDE = ("changeBackGround", "drawIllust", "setOutTalker")

    def snapshot(regs, slotval, xptr, pages, xstr, last_str, store, snreg):
        return (dict(regs), dict(slotval), dict(xptr), dict(pages), dict(xstr),
                last_str, dict(store), snreg)

    ops: list[dict] = []
    # (시작주소, 상태, 주경로여부)
    queue: list[tuple[int, tuple, bool]] = [
        (tgt, ({}, {}, {}, {}, {}, None, {}, None), True)]
    seen_starts: set[int] = set()
    budget = MAX_STEP_INSNS * 4          # 갈래를 다 합친 총 예산

    while queue and budget > 0:
        start, st, primary = queue.pop(0)
        if start in seen_starts:
            continue
        seen_starts.add(start)
        regs, slotval, xptr, pages, xstr, last_str, store, snreg = (
            dict(st[0]), dict(st[1]), dict(st[2]), dict(st[3]), dict(st[4]),
            st[5], dict(st[6]), st[7])
        last_cmp: tuple[str, int] | None = None
        pend_slot: int | None = None          # 직전 `add x0,this,#0x1d8|0x1f0`
        talk_name = talk_key = None
        cur = nav_at(start)
        seen: set[int] = set()
        for _ in range(MAX_STEP_INSNS):
            budget -= 1
            if cur is None or budget <= 0 or not body.contains(cur.getAddress()):
                break
            a = cur.getAddress().getOffset()
            if a in seen:
                break
            seen.add(a)
            t = text(cur)
            # 회차 레지스터 추적 — `ldr wN,[x?,#0x168]`
            m = re.fullmatch(r"ldr (w\d+),\[x\d+,#0x168\]", t)
            if m:
                snreg = m.group(1)
            m = re.fullmatch(r"cmp (w\d+),#(0x[0-9a-f]+|\d+)", t)
            if m:
                last_cmp = (m.group(1), int(m.group(2), 0))
            # 회차 분기 — 원하는 회차 경로만 따라간다
            if (want_sn is not None and snreg is not None and last_cmp is not None
                    and last_cmp[0] == snreg and re.fullmatch(r"b\.(eq|ne) 0x[0-9a-f]+", t)):
                eq = last_cmp[1] == want_sn
                taken = (t.startswith("b.eq") and eq) or (t.startswith("b.ne") and not eq)
                last_cmp = None
                if taken:
                    fl3 = cur.getFlows()
                    if not fl3:
                        break
                    cur = nav_at(fl3[0].getOffset())
                    continue
                cur = nav_after(cur)
                continue
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
            # 대사 문자열을 멤버에 써 두는 규약 — `add x0,this,#0x1d8|0x1f0` 다음의
            # `basic_string::assign(x0, x1=<문자열>)` 이 화자 이름/대사 키를 정한다.
            m = re.fullmatch(r"add x0,x\d+,#(0x1d8|0x1f0)", t)
            if m:
                pend_slot = int(m.group(1), 0)
            # 포인터 인자 준비
            m = re.fullmatch(r"(add|sub) (x\d+),(x29|sp),#(0x[0-9a-f]+|\d+)", t)
            if m:
                sign = -1 if m.group(1) == "sub" else 1
                xptr[m.group(2)] = f"{m.group(3)}{sign * int(m.group(4), 0):+d}"
            # .rodata 문자열 포인터 조립(`adrp x8,PAGE` + `add x8,x8,#OFF`)
            m = re.fullmatch(r"adrp (x\d+),(0x[0-9a-f]+)", t)
            if m:
                pages[m.group(1)] = int(m.group(2), 0)
            # ⚠ 역참조 \1 은 히어독 편집으로 **두 번** 사라졌다(제어문자로 치환돼 매치가 조용히 죽는다).
            #   그래서 여기서는 역참조 대신 **두 그룹을 잡아 같은지 비교**한다.
            m = re.fullmatch(r"add (x\d+),(x\d+),#(0x[0-9a-f]+|\d+)", t)
            if m and m.group(1) == m.group(2) and m.group(1) in pages:
                cand = pages[m.group(1)] + int(m.group(3), 0)
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
                if pend_slot is not None:
                    sv = xstr.get("x1")
                    if sv:
                        if pend_slot == OFF_NAME:
                            talk_name = sv
                        else:
                            talk_key = sv
                    pend_slot = None
                if a in npc_talk_addrs:
                    ops.append({"op": "setNpcTalk", **store})
                    return ops
                if a in user_talk_addrs:
                    ops.append({"op": "setUserTalk"})
                    return ops
                if talk_addrs and a in talk_addrs:
                    # 대사 키는 멤버(this+0x1f0)에 써 둔 것이 정답이다 —
                    # `last_str` 을 쓰면 직전에 스친 아무 문자열이나 집힌다.
                    ops.append({"op": "setTalk", "key": talk_key or last_str,
                                # 원작이 멤버에 쓰는 값은 문자열 리소스 키(`NPC_nuri`)다 —
                                # 우리 `npc_names` 는 폴더명(`nuri`) 이 키라 접두를 뗀다.
                                "npc_name": (talk_name[4:] if talk_name
                                             and talk_name.startswith("NPC_") else talk_name),
                                "body": regs.get("w3"), "state": regs.get("w4")})
                    return ops
                if talker_addrs and a in talker_addrs:
                    # AAPCS: x0=this · w1=bool · x2=이름 문자열 · w3=body · w4=state
                    ops.append({"op": "setTalker",
                                "npc_name": xstr.get("x2", last_str),
                                "body": regs.get("w3"), "state": regs.get("w4")})
                    return ops
                fl = cur.getFlows()
                callee = fm.getFunctionAt(fl[0]) if fl else None
                if callee is not None and primary:
                    nm = callee.getName()
                    if "changeBackGround" in nm:
                        # ⚠️ 2번째 인자는 `BackGruundName*` = 스택 슬롯 포인터다(정수 아님)
                        ops.append({"op": "changeBackGround",
                                    "bg": slotval.get(xptr.get("x1", ""))})
                    elif "drawIllust" in nm:
                        ops.append({"op": "drawIllust",
                                    "illust": regs.get("w1"), "kind": regs.get("w2")})
                    elif "setOutTalker" in nm:
                        ops.append({"op": "setOutTalker"})
            mn = cur.getMnemonicString()
            if mn == "b":
                fl = cur.getFlows()
                if not fl:
                    break
                cur = nav_at(fl[0].getOffset())
                continue
            if mn == "ret":
                break
            # 조건 분기 — 타깃을 대기열에 넣고 폴스루를 계속 간다
            if mn.startswith("b.") or mn.startswith("cb") or mn.startswith("tb"):
                for f2 in cur.getFlows():
                    o2 = f2.getOffset()
                    if o2 != a + cur.getLength() and o2 not in seen_starts:
                        queue.append((o2, snapshot(regs, slotval, xptr, pages,
                                                   xstr, last_str, store, snreg), False))
            cur = nav_after(cur)
    return ops


if __name__ == "__main__":
    main()

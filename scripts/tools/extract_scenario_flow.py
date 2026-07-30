"""시나리오 연출 스크립트 추출 — 원작 `Scenario*::initScenarioData` 의 std::function 스텝 복원.

## 왜 필요한가 (2026-07-31 채굴 결론)

종전 판단 "화자·표정·배경·트리거 = `ScenarioScript`(서버 JSON) 유실" 은 **102화 이상에만** 맞다.
`ScenarioManager::makeScenarioLayer(sn)` 이 회차를 클래스로 가르는데(디컴프 확인):

    sn<10 Scenario1 · <20 Scenario2 · <30 Scenario3 · <40 Scenario4 · <50 Scenario5
    · <59 Scenario6 · <79 Scenario7 · 79~81 Scenario8
    · 82~86 Scenario_zimon · 87~91 Scenario_mamorudic · 92~101 Scenario_Kadeath
    · 102+ ScenarioCommon   ← 이것만 ScenarioManager::getScriptArr(서버 script)를 읽는다

즉 1~101화의 연출은 **클라 코드에 박혀 있다.** 각 회차 클래스의 `initScenarioData` 가
`vector<std::function<void()>>` 에 스텝을 push 하고, 스텝 본문(람다)이
`ScenarioSupport::setNpcTalk(NPC_NAME, Character_State, Character_Pos, TalkEmoticon, …)` ·
`changeBackGround(BackGruundName)` · `drawIllust` · `showMonster` 를 **리터럴 인자로** 부른다.

람다는 익명 함수라 클래스 단위 디컴프(`batch_decompile.py`)에 안 잡힌다 —
`initScenarioData` 가 참조하는 주소를 따라가야 나온다. 이 도구가 그 일을 한다.

## 무엇을 하나

1. `initScenarioData`(없으면 `setNext`)를 찾아 **참조(코드/데이터) 전수**를 수집
2. 데이터 참조는 그 자리에서 포인터를 읽어 함수인지 확인(Ghidra 가 재배치를 적용해 준다)
3. 그렇게 모은 함수(=람다 본문)를 전부 디컴프해 `docs/ref/orig_code/decomp/lambda/<Class>.c` 로 저장

파싱(→ JSON)은 `parse_scenario_flow.py` 가 이 산출물을 읽어서 한다. 덤프와 해석을 나눈 이유는
Ghidra 세션이 비싸서 한 번 뜬 덤프를 여러 번 다시 해석하게 하기 위해서다.

사용:
    python scripts/tools/extract_scenario_flow.py --classes Scenario_zimon
    python scripts/tools/extract_scenario_flow.py --all            # 회차 클래스 12종
    python scripts/tools/extract_scenario_flow.py --all --force
"""
from __future__ import annotations
import os, sys
from pathlib import Path

os.environ.setdefault("GHIDRA_INSTALL_DIR", r"C:\Users\mydog\ghidra\ghidra_12.1.2_PUBLIC")
os.environ.setdefault("JAVA_HOME", r"C:\Program Files\Eclipse Adoptium\jdk-21.0.11.10-hotspot")

REPO_ROOT = Path(__file__).resolve().parents[2]
SO_PATH = REPO_ROOT / "lib" / "arm64-v8a" / "libgame.so"
if not SO_PATH.exists():
    SO_PATH = REPO_ROOT / "libgame.so"
PROJECT_DIR = Path(os.environ["GHIDRA_INSTALL_DIR"]).parent / "dv2_project"
PROJECT_NAME = "dv2"
OUT_DIR = REPO_ROOT / "docs" / "ref" / "orig_code" / "decomp" / "lambda"

## 회차 → 클래스 (원작 `ScenarioManager::makeScenarioLayer`, ScenarioManager.c @014ddce4).
## ScenarioCommon 은 서버 script 소비라 제외한다(뽑아도 회차 데이터가 없다).
EPISODE_CLASSES = [
    "Scenario1", "Scenario2", "Scenario3", "Scenario4", "Scenario5",
    "Scenario6", "Scenario7", "Scenario8",
    "Scenario_zimon", "Scenario_mamorudic", "Scenario_Kadeath", "Scenario_raon",
]
## 스텝 본문을 담는 함수. 이 이름들에서 시작해 참조를 따라간다.
ROOT_METHODS = ("initScenarioData", "setNext", "init", "setPlay", "setSubQuest")
## 데이터 참조에서 포인터를 몇 칸까지 훑을지. std::function vtable/객체가 연속 배치돼 있어
## 한 참조에서 여러 슬롯이 나온다. 넉넉히 잡고 함수인 것만 취한다.
PTR_WINDOW = 24


def parse_args(argv):
    classes, force = [], False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--classes":
            classes += [c.strip() for c in argv[i + 1].split(",") if c.strip()]; i += 2
        elif a == "--all":
            classes += EPISODE_CLASSES; i += 1
        elif a == "--force":
            force = True; i += 1
        else:
            classes.append(a); i += 1
    seen, uniq = set(), []
    for c in classes:
        if c not in seen:
            seen.add(c); uniq.append(c)
    return uniq, force


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    classes, force = parse_args(sys.argv[1:])
    if not classes:
        print("클래스 목록이 비었음. --classes Scenario_zimon 또는 --all"); return
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    todo = [c for c in classes if force or not (OUT_DIR / f"{c}.c").exists()]
    print(f"[flow] 대상 {len(classes)} · 처리 {len(todo)} (스킵 {len(classes)-len(todo)})")
    if not todo:
        print("모두 완료됨."); return

    import pyghidra
    pyghidra.start()
    from ghidra.app.decompiler import DecompInterface, DecompileOptions
    from ghidra.util.task import ConsoleTaskMonitor

    with pyghidra.open_program(
        str(SO_PATH), project_location=str(PROJECT_DIR),
        project_name=PROJECT_NAME, analyze=False,
    ) as flat:
        program = flat.getCurrentProgram()
        fm = program.getFunctionManager()
        mem = program.getMemory()
        af = program.getAddressFactory().getDefaultAddressSpace()
        decomp = DecompInterface()
        opts = DecompileOptions(); opts.setMaxPayloadMBytes(200)
        decomp.setOptions(opts); decomp.openProgram(program)
        monitor = ConsoleTaskMonitor()

        # 클래스 → 루트 메서드 (전체 순회 1회로 그룹화)
        roots = {c: [] for c in todo}
        for f in fm.getFunctions(True):
            qual = f.getName(True)
            for c in todo:
                if f"::{c}::" in "::" + qual and f.getName() in ROOT_METHODS:
                    roots[c].append(f)

        def func_at(addr_long):
            """주소가 실제 함수면 그 Function 을 준다(아니면 None)."""
            try:
                a = af.getAddress(addr_long)
            except Exception:  # noqa: BLE001
                return None
            fn = fm.getFunctionAt(a)
            if fn is not None:
                return fn
            fn = fm.getFunctionContaining(a)
            # 함수 중간을 가리키는 포인터는 스텝 본문이 아니다
            return fn if fn is not None and fn.getEntryPoint().equals(a) else None

        for c in todo:
            rs = roots[c]
            if not rs:
                print(f"  {c}: 루트 메서드 없음 — 건너뜀"); continue
            found, seen_addr = [], set()
            # 루트가 내보내는 참조 전수
            rm = program.getReferenceManager()
            for r in rs:
                for addr in r.getBody().getAddresses(True):
                    for ref in rm.getReferencesFrom(addr):
                        ta = ref.getToAddress()
                        if ta is None:
                            continue
                        # ① 직접 호출되는 함수
                        fn = fm.getFunctionAt(ta)
                        if fn is not None and fn.getEntryPoint().toString() not in seen_addr:
                            # 루트 자신·원작 API 는 이미 클래스 덤프에 있다 → 익명 함수만
                            if fn.getName().startswith("FUN_"):
                                seen_addr.add(fn.getEntryPoint().toString()); found.append(fn)
                            continue
                        # ② 데이터 참조 → 그 자리에서 포인터 창을 훑는다
                        base = ta.getOffset()
                        for k in range(PTR_WINDOW):
                            try:
                                p = mem.getLong(af.getAddress(base + 8 * k))
                            except Exception:  # noqa: BLE001
                                break
                            if p == 0:
                                continue
                            fn2 = func_at(p & 0xFFFFFFFFFFFF)
                            if fn2 is None:
                                continue
                            key = fn2.getEntryPoint().toString()
                            if key in seen_addr:
                                continue
                            seen_addr.add(key); found.append(fn2)

            chunks = [f"/* 시나리오 연출 스텝 덤프 — {c} (루트 {len(rs)}개, 스텝후보 {len(found)}개) */\n"
                      f"/* 생성: scripts/tools/extract_scenario_flow.py */\n"]
            ok = 0
            for fn in sorted(found, key=lambda x: x.getEntryPoint().getOffset()):
                addr = fn.getEntryPoint().toString()
                size = fn.getBody().getNumAddresses()
                try:
                    res = decomp.decompileFunction(fn, 180, monitor)
                    code = (res.getDecompiledFunction().getC()
                            if res and res.decompileCompleted()
                            else f"/* 실패: {fn.getName()} @ {addr} */")
                except Exception as e:  # noqa: BLE001
                    code = f"/* 예외: {fn.getName()} @ {addr} — {e} */"
                chunks.append(f"\n/* ==== step {fn.getName()} @ {addr} (size={size}) ==== */\n{code}\n")
                ok += 1
            (OUT_DIR / f"{c}.c").write_text("\n".join(chunks), encoding="utf-8")
            print(f"  {c}: 루트 {len(rs)} · 스텝 {ok}개 디컴프")

    print(f"-> {OUT_DIR}")


if __name__ == "__main__":
    main()

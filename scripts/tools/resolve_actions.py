"""디컴프 C 에서 **Cocos 액션 트리(CCSequence/CCSpawn 조립 순서)** 를 복원한다.

## 왜 필요한가 (2026-08-05)

`UltimateLayer::run<El>` 처럼 안무를 만드는 함수는 액션을 **지역변수에 하나씩 담았다가**
마지막에 `CCSequence::create(a,b,c,0)` 로 잇는다. Ghidra 산출물에서는

    pCVar10 = (CCFiniteTimeAction *)CCDelayTime::create(4.25);
    uVar11  = CCFadeTo::create(1.0,0xff);
    ...
    pCVar16 = (CCAction *)CCSequence::create(pCVar10,uVar11,uVar12,uVar13,uVar15,0);
    CCNode::runAction(pCVar9,pCVar16);

처럼 **순서는 인자 목록에 그대로 있는데** 변수가 재사용돼 사람 눈으로 따라가기 어렵다.
이 도구가 그 데이터플로를 풀어 트리로 편다. (ASM CFG 를 읽을 필요가 없다 —
순서 정보는 C 단계에서 이미 온전하다. `asm_cfg.py` 는 **점프테이블 분기**용이지
이런 선형 조립용이 아니다.)

## 쓰는 법

    python scripts/tools/resolve_actions.py UltimateLayer --fn runFire
    python scripts/tools/resolve_actions.py UltimateLayer --fn "run.*" --md docs/ref/design/x.md
    python scripts/tools/resolve_actions.py UltimateLayer --list

## 읽는 법 / 한계

- `runAction(대상, 액션)` 마다 트리를 하나 낸다. 들여쓰기 = 중첩.
- `?` 표시 = 그 변수의 **최근 대입과 사용 사이에 분기(`if`/`}`/`goto`/`LAB_`)가 끼어 있다**
  → 다른 분기에서 다른 값이 들어올 수 있으니 사람이 확인해야 한다. 표시가 없으면 직선 코드다.
- `[loop]` = `do {` 안에서 조립된다(반복 실행).
- `CCCallFunc*` 는 바로 앞 `operator_new(0x28)` std::function 블록과 묶어
  **호출 대상 + 바인딩된 float 인자**까지 복원한다.
- 간접 호출(`(**(code**)(*(long*)x+0x160))(x, act)`)도 runAction 후보로 잡는다.
"""
from __future__ import annotations
import argparse, re, struct, sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO = Path(__file__).resolve().parents[2]
DECOMP = REPO / "docs" / "ref" / "orig_code" / "decomp"

HDR = re.compile(r"^/\* ==== (\w+) @ ([0-9a-f]+) \(size=(\d+)\) ==== \*/")
CAST = re.compile(r"\((?:unsigned |signed |const )?\w+(?:::\w+)* *\*+\)")
# 액션 팩토리 — 이 목록에 없는 create 는 "값"으로만 취급한다
FACTORY = re.compile(
    r"\b(CC(?:Sequence|Spawn|DelayTime|MoveTo|MoveBy|JumpTo|JumpBy|ScaleTo|ScaleBy|"
    r"RotateTo|RotateBy|FadeTo|FadeIn|FadeOut|TintTo|TintBy|BezierTo|BezierBy|"
    r"Blink|Hide|Show|Place|ToggleVisibility|RemoveSelf|FlipX|FlipY|Animate|"
    r"Repeat|RepeatForever|CallFunc|CallFuncN|CallFuncND|Follow|Speed|"
    r"Ease(?:In|Out|InOut|SineIn|SineOut|SineInOut|ExponentialIn|ExponentialOut|"
    r"ExponentialInOut|Elastic|ElasticIn|ElasticOut|ElasticInOut|Bounce|BounceIn|"
    r"BounceOut|BounceInOut|BackIn|BackOut|BackInOut|RateAction)|"
    r"ActionInterval|Progress\w*|OrbitCamera|CardinalSpline\w*|CatmullRom\w*))::create\b"
)
ASSIGN = re.compile(r"^\s*([A-Za-z_]\w*)\s*=\s*(.+);\s*$")
RUNACTION = re.compile(r"\bCCNode::runAction\s*\(\s*([^,]+?)\s*,\s*([A-Za-z_]\w*)\s*\)")
# (**(code **)(*(long *)node + 0x160))(node, action)  = 가상 runAction
VRUN = re.compile(r"\(\*\*\(code \*\*\)\(\*\(long \*\)(\w+) \+ (0x[0-9a-f]+|\d+)\)\)\(\w+,(\w+)\)")
NEWFN = re.compile(r"^\s*(\w+)\s*=\s*(?:\([^)]*\))?\s*operator_new\(0x28\)")
FNPTR = re.compile(r"=\s*(?:\([^)]*\))?\s*((?:\w+::)*[A-Za-z_]\w*)\s*;")
NOTFN = re.compile(r"^(?:local_\w+|[a-z]{0,2}[A-Z]?[A-Za-z]*Var\d+|[a-z]?[A-Z]?\w*Stack_\w+|"
                   r"this|this_\d+|param_\d+|PTR_\w+|DAT_\w+|NULL)$")
# std::function 을 지역 버퍼에 직접 지은 경우(작은객체 최적화) — operator_new 가 없다
INPLACE = re.compile(r"=\s*(?:\([^)]*\))?\s*&PTR_FUN_[0-9a-f]+\s*;")
HEX32 = re.compile(r"\b0x([0-9a-f]{8})\b")
BRANCHY = re.compile(r"^\s*(\}|if\s*\(|else|goto |do \{|while |LAB_\w+:|switch)")


def f32(h: str) -> str:
    v = struct.unpack("<f", struct.pack("<I", int(h, 16)))[0]
    if abs(v) < 1e-6 or abs(v) > 1e7:
        return "0x" + h
    return f"{v:g}"


def load_fn(cls: str, name: str) -> list[str] | None:
    """같은 이름이 여러 개면 **본체가 가장 큰 것**(스텁 16바이트 배제)을 고른다."""
    path = DECOMP / f"{cls}.c"
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    cuts: list[tuple[int, str, int]] = []
    for i, ln in enumerate(lines):
        m = HDR.match(ln)
        if m:
            cuts.append((i, m.group(1), int(m.group(3))))
    best = None
    for k, (i, nm, size) in enumerate(cuts):
        if nm != name:
            continue
        end = cuts[k + 1][0] if k + 1 < len(cuts) else len(lines)
        if best is None or size > best[0]:
            best = (size, lines[i:end])
    return best[1] if best else None


def list_fns(cls: str) -> list[tuple[str, int]]:
    path = DECOMP / f"{cls}.c"
    out: dict[str, int] = {}
    for ln in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = HDR.match(ln)
        if m:
            out[m.group(1)] = max(out.get(m.group(1), 0), int(m.group(3)))
    return sorted(out.items())


class Env:
    """선형 스캔으로 변수 → 액션 노드를 묶는다."""

    def __init__(self) -> None:
        self.val: dict[str, dict] = {}
        self.pending_fn: dict | None = None  # 직전 operator_new(0x28) 블록

    def put(self, var: str, node: dict) -> None:
        self.val[var] = node


def statements(body: list[str]) -> list[tuple[int, str, bool, int]]:
    """(줄번호, 문장, 분기직후인가, 루프깊이) 목록. 여러 줄 문장을 합친다."""
    out: list[tuple[int, str, bool, int]] = []
    buf, start = "", 0
    branchy, depth = False, 0
    pend = False
    in_comment = False
    for i, raw in enumerate(body):
        # ⚠️ Ghidra 는 여러 줄짜리 /* try/catch */ 주석을 뿌린다. 상태기계로 지우지 않으면
        # 주석 꼬리가 문장 버퍼에 들어가 **다음 대입문을 통째로 삼킨다**(runFire 3번째 시퀀스 사고)
        ln = ""
        rest = raw
        while rest:
            if in_comment:
                k = rest.find("*/")
                if k < 0:
                    rest = ""
                else:
                    rest = rest[k + 2:]
                    in_comment = False
            else:
                k = rest.find("/*")
                if k < 0:
                    ln += rest
                    rest = ""
                else:
                    ln += rest[:k]
                    rest = rest[k + 2:]
                    in_comment = True
        s = ln.strip()
        if not s:
            continue
        if BRANCHY.match(ln):
            pend = True
            if s.startswith("do {"):
                depth += 1
            elif s.startswith("}") and "while" in s:
                depth = max(0, depth - 1)
        if not buf:
            start = i
        buf += " " + s
        if s.endswith(";") or s.endswith("{") or s.endswith("}"):
            out.append((start, buf.strip(), pend, depth))
            if buf.strip().endswith(";"):
                pend = False
            buf = ""
    return out


def split_args(s: str) -> list[str]:
    args, d, cur = [], 0, ""
    for ch in s:
        if ch == "(":
            d += 1
        elif ch == ")":
            d -= 1
        if ch == "," and d == 0:
            args.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        args.append(cur.strip())
    return args


def parse(body: list[str]) -> tuple[list[dict], Env]:
    env = Env()
    roots: list[dict] = []
    for lineno, st, branchy, depth in statements(body):
        # ── std::function 블록 시작
        ip = INPLACE.search(st)
        if NEWFN.match(st) or ip:
            if env.pending_fn is None:
                env.pending_fn = {"fn": None, "args": [], "vt": None}
            if ip:
                # 람다는 멤버 함수 포인터가 없다 — **std::function 구현 vtable 주소가 곧 신원**이다
                env.pending_fn["vt"] = re.search(r"PTR_FUN_[0-9a-f]+", st).group(0)
            continue
        if env.pending_fn is not None and "::create(" not in st:
            # 블록은 `::create(` 를 만날 때까지 이어진다 — 중간의 `uStack_d0 = 0;` 같은
            # 잡다한 멤버 초기화로 끊기면 호출 대상을 놓친다
            fm = FNPTR.search(st)
            if fm and not NOTFN.match(fm.group(1)) and "operator_new" not in st:
                env.pending_fn["fn"] = fm.group(1)
            else:
                hm = HEX32.search(st)
                if hm and "=" in st:
                    env.pending_fn["args"].append(f32(hm.group(1)))
            continue

        m = ASSIGN.match(st)
        if m:
            var, rhs = m.group(1), CAST.sub("", m.group(2)).strip()
            fm = FACTORY.search(rhs)
            if fm:
                kind = fm.group(1)
                inner = rhs[fm.end():].lstrip()
                assert inner.startswith("(")
                # 괄호 균형으로 인자 구간 확보
                d, j = 0, 0
                for j, ch in enumerate(inner):
                    d += (ch == "(") - (ch == ")")
                    if d == 0:
                        break
                raw = split_args(inner[1:j])
                # ⚠️ `uVar20 = CCSpawn::create(x, uVar20, 0)` 처럼 **자기 자신을 감싸는** 조립이
                # 흔하다 → 대입 **직전**의 환경을 노드에 붙여 둬야 자기참조가 풀린다
                node = {"kind": kind, "raw": raw, "line": lineno, "branchy": branchy,
                        "loop": depth, "fn": None, "env": dict(env.val)}
                if kind.startswith("CCCallFunc") and env.pending_fn:
                    node["fn"] = env.pending_fn
                    env.pending_fn = None
                env.put(var, node)
                continue
            env.pending_fn = None
            continue

        # ⚠️ 변수는 재사용된다 — **그 시점의 환경을 스냅샷**해 둬야 한다
        for target, act in RUNACTION.findall(st):
            roots.append({"target": CAST.sub("", target).strip(), "act": act,
                          "line": lineno, "env": dict(env.val)})
        for tgt, slot, act in VRUN.findall(st):
            if slot in ("0x160", "0x168"):  # runAction 계열 가상 슬롯
                roots.append({"target": tgt, "act": act, "line": lineno, "env": dict(env.val)})
    return roots, env


def render(var: str, env: dict, depth: int = 0, seen: set | None = None) -> list[str]:
    seen = seen or set()
    node = env.get(var)
    pad = "  " * depth
    if node is None:
        return [f"{pad}- <{var}>"]
    if id(node) in seen or depth > 24:
        return [f"{pad}- {node['kind']} (순환)"]
    seen = seen | {id(node)}
    env = node.get("env", env)  # 대입 직전 환경으로 자식을 푼다
    flag = ""
    if node["branchy"]:
        flag += " ?"
    if node["loop"]:
        flag += " [loop]"
    kind = node["kind"]
    out: list[str] = []
    if kind in ("CCSequence", "CCSpawn"):
        out.append(f"{pad}- {kind}{flag}")
        for a in node["raw"]:
            if a in ("0", "(CCFiniteTimeAction *)0x0"):
                continue
            out += render(a, env, depth + 1, seen)
    elif kind.startswith("CCCallFunc"):
        fn = node["fn"] or {}
        tgt = fn.get("fn") or (f"lambda@{fn['vt']}" if fn.get("vt") else "?")
        args = ("(" + ", ".join(fn.get("args", [])) + ")") if fn.get("args") else ""
        out.append(f"{pad}- {kind} → {tgt}{args}{flag}")
    elif kind in ("CCRepeat", "CCRepeatForever") or kind.startswith("CCEase") or kind == "CCSpeed":
        extra = ", ".join(node["raw"][1:])
        out.append(f"{pad}- {kind}({extra}){flag}" if extra else f"{pad}- {kind}{flag}")
        out += render(node["raw"][0], env, depth + 1, seen)
    else:
        out.append(f"{pad}- {kind}({', '.join(node['raw'])}){flag}")
    return out


def dump(cls: str, name: str) -> list[str]:
    body = load_fn(cls, name)
    if body is None:
        return [f"## {name} — 디컴프에 없음"]
    roots, env = parse(body)
    out = [f"## {cls}::{name}  (runAction {len(roots)}건)", ""]
    for r in roots:
        out.append(f"### runAction → {r['target']}   (L{r['line']})")
        out += render(r["act"], r["env"], 0)
        out.append("")
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("cls")
    ap.add_argument("--fn", default=None, help="함수명 정규식")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--md", default=None)
    a = ap.parse_args()

    if a.list or not a.fn:
        for nm, sz in list_fns(a.cls):
            print(f"{sz:>7}  {nm}")
        return
    pat = re.compile(f"^(?:{a.fn})$")
    names = [nm for nm, _ in list_fns(a.cls) if pat.match(nm)]
    lines: list[str] = [f"# {a.cls} 액션 트리 — `resolve_actions.py` 기계 복원", ""]
    for nm in names:
        lines += dump(a.cls, nm)
    txt = "\n".join(lines)
    if a.md:
        p = REPO / a.md
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(txt + "\n", encoding="utf-8")
        print(f"[write] {a.md}  ({len(names)} 함수)")
    else:
        print(txt)


if __name__ == "__main__":
    main()

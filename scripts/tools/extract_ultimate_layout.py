"""`UltimateLayer::init<El>` 의 **스프라이트 배치**를 기계로 뽑는다.

## 왜 (2026-08-05)

각성기 연출의 "무엇을 어디에 어떤 크기·회전·z 로 놓는가"는 전부 `init<El>` / `init<El>_C` 에 있다.
`resolve_actions.py` 가 **시간축**(CCSequence)을 풀었다면 이 도구는 **공간축**을 푼다.

원작 한 덩이는 이런 꼴이다:

    pcVar7 = FUN_01001244("skill/ultimate/fire/fire_explosion1.png");
    plVar8 = CCSprite::createWithSpriteFrameName(pcVar7);
    CCPoint::CCPoint(local_b0, 0.5, 0.0);
    (*(*plVar8 + 0xf0))(plVar8, local_b0);            // setAnchorPoint(0.5, 0)
    this_00 = this + lVar6*8 + 0x2d8;                 // 앵커표 i 번째
    (*(*plVar8 + 0x90))(plVar8, this_00);             // setPosition(anchor[i])
    (*(*plVar8 + 0x58))(0.5, plVar8);                 // setScaleX(0.5)
    (*(*plVar8 + 0x68))(0,   plVar8);                 // setScaleY(0)
    (*(*batch + 0x198))(batch, plVar8, z, tag);       // addChild(z, tag)

⇒ 프레임·앵커·좌표·배율·회전·가시성·z·tag 가 전부 리터럴로 남아 있다.

## 슬롯표 (cocos2d-x 2.x CCNode — `docs/ref/porting/UltimateLayer.md` §9-4 에서 확정)

    0x30 setZOrder   0x40 getZOrder   0x58 setScaleX  0x60 getScaleX
    0x68 setScaleY   0x70 getScaleY   0x78 setScale   0x88 setScale(x,y)
    0x90 setPosition 0x98 getPosition 0xb0/0xb8 posX  0xc0/0xc8 posY
    0xf0 setAnchorPoint  0x110 getContentSize  0x118 setVisible
    0x128 setRotation    0x130 getRotation     0x190 addChild(n,z)
    0x198 addChild(n,z,tag)   0x320 setOpacity

## 쓰는 법

    python scripts/tools/extract_ultimate_layout.py                 # 전 속성 → md + json
    python scripts/tools/extract_ultimate_layout.py --el fire       # 한 속성만 화면에

산출: `docs/ref/design/ultimate_layer_layout.md` · `data/recipes/ultimate_layout.json`

## 한계

- 표현식은 **원작 그대로의 문자열**로 낸다(`fVar18 * 0.5`, `rand() % 3` 등). 사람이 읽고
  옮기라는 뜻이지 자동 평가용이 아니다 — 지역변수 이름이 남으면 그 줄을 직접 봐야 한다.
- `CCPoint::operator+/-/*` 는 Ghidra 가 반환 슬롯을 별도 지역변수로 잡아 이름이 끊긴다.
  그래서 **직전 두 항을 합친 식**으로 기록하고 `~` 를 붙여 추정임을 표시한다.
"""
from __future__ import annotations
import argparse, json, re, struct, sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO = Path(__file__).resolve().parents[2]
SRC = REPO / "docs" / "ref" / "orig_code" / "decomp" / "UltimateLayer.c"
ELEMENTS = ["fire", "aqua", "earth", "wind", "light", "dark", "holy", "chaos", "shadow"]

SLOT = {
    "0x30": "setZOrder", "0x58": "setScaleX", "0x68": "setScaleY", "0x78": "setScale",
    "0x88": "setScaleXY", "0x90": "setPosition", "0xf0": "setAnchorPoint",
    "0x118": "setVisible", "0x128": "setRotation", "0x190": "addChild", "400": "addChild",
    "0x198": "addChildTag", "0x320": "setOpacity", "800": "setOpacity",
}
CAST = re.compile(r"\((?:unsigned |signed |const )?\w+(?:::\w+)* *\*+\)")
HDR = re.compile(r"^/\* ==== (\w+) @ ([0-9a-f]+) \(size=(\d+)\) ==== \*/")
FRAME = re.compile(r'FUN_\w+\("([^"]+)"\)')
MAKE = re.compile(r"^(\w+)\s*=\s*(?:\([^)]*\))?\s*CCSprite::create(?:WithSpriteFrameName)?\((\w+)\)")
PT = re.compile(r"CCPoint::CCPoint\(\s*(?:\([^)]*\))?\s*&?(\w+)\s*,\s*(.+)\)\s*;?$")
# (**(code **)(*plVar8 + 0xf0))(plVar8,local_b0);      ← this 가 1번째
# (**(code **)(*plVar8 + 0x58))(0.5,plVar8);           ← this 가 뒤 (Ghidra 인자 밀림)
# ⚠️ `pretty()` 가 `(code **)` · `(long *)` 같은 캐스트를 먼저 지우므로 **지운 뒤 모양**으로 맞춘다.
#   원본  (**(code **)(*plVar8 + 0xf0))(plVar8,local_b0);
#   지운뒤 (**(*plVar8 + 0xf0))(plVar8,local_b0);
VCALL = re.compile(r"\(\*\*\(\*+([\w()+ *]+?) \+ (0x[0-9a-f]+|\d+)\)\)\((.*)\)\s*;?$")
LOOP = re.compile(r"^\}\s*while\s*\((.+)\)\s*;")
# 배치노드(CCSpriteBatchNode) 를 통한 addChild — 수신자가 이중 역참조라 모양이 다르다
BATCHCALL = re.compile(r"\(\*\*\(\*\*\((this \+ 0x[0-9a-f]+)\) \+ (0x[0-9a-f]+)\)\)\((.*)\)\s*;?$")


def f32(h: str) -> str:
    v = struct.unpack("<f", struct.pack("<I", int(h, 16)))[0]
    return f"{v:g}" if 1e-6 < abs(v) < 1e7 else h


def pretty(s: str) -> str:
    s = CAST.sub("", s)
    s = re.sub(r"0x[34][0-9a-f]{7}\b", lambda m: f32(m.group(0)), s)
    s = re.sub(r"\s+", " ", s).strip()
    # 여러 줄을 이을 때 `))` 와 `(` 사이에 공백이 생긴다 — 호출 모양을 되붙인다
    return re.sub(r"\)\s+\(", ")(", s)


def load_fn(name: str, lines: list[str], cuts: list[tuple[int, str, int]]) -> list[str] | None:
    best = None
    for k, (i, nm, size) in enumerate(cuts):
        if nm != name:
            continue
        end = cuts[k + 1][0] if k + 1 < len(cuts) else len(lines)
        if best is None or size > best[0]:
            best = (size, lines[i:end])
    return best[1] if best else None


def statements(body: list[str]) -> list[tuple[str, int]]:
    """(문장, 루프깊이). Ghidra 다중행 주석은 상태기계로 지운다."""
    out, buf, depth, in_c = [], "", 0, False
    for raw in body:
        ln, rest = "", raw
        while rest:
            if in_c:
                k = rest.find("*/")
                rest, in_c = ("", True) if k < 0 else (rest[k + 2:], False)
            else:
                k = rest.find("/*")
                if k < 0:
                    ln += rest
                    rest = ""
                else:
                    ln += rest[:k]
                    rest, in_c = rest[k + 2:], True
        s = ln.strip()
        if not s:
            continue
        buf += " " + s
        st = buf.strip()
        if s.startswith("do {"):
            depth += 1
        if LOOP.match(st):
            depth = max(0, depth - 1)
        if s.endswith(";") or s.endswith("{") or s.endswith("}"):
            out.append((st, depth))
            buf = ""
    return out


def parse(body: list[str]) -> list[dict]:
    strs: dict[str, str] = {}          # pcVar → 프레임 경로
    pts: dict[str, str] = {}           # local → "x, y"
    objs: dict[str, dict] = {}         # 변수 → 노드
    alias: dict[str, str] = {}         # this_00 = this + i*8 + 0x2d8  (멤버 앵커표)
    order: list[dict] = []
    pending = ""                       # 방금 만든 CCPoint 연산 결과(반환 슬롯 이름이 끊긴다)
    for st, depth in statements(body):
        st = pretty(st)

        for var, path in re.findall(r"(\w+)\s*=\s*(?:\([^)]*\))?\s*" + FRAME.pattern, st):
            strs[var] = path
        m = MAKE.match(st)
        if m:
            node = {"frame": strs.get(m.group(2), "?"), "loop": depth, "ops": []}
            objs[m.group(1)] = node
            order.append(node)
            continue
        m = PT.search(st)
        if m:
            pts[m.group(1)] = m.group(2)
            pending = ""
            continue
        if "CCPoint::operator" in st:
            op = re.search(r"CCPoint::operator([+\-*/])\((.*)\)", st)
            if op:
                terms = [alias.get(x.strip(), pts.get(x.strip(), x.strip()))
                         for x in split_args(op.group(2))]
                pending = "~(%s)" % (" %s " % op.group(1)).join(terms)
            continue
        # `this_00 = this + lVar6 * 8 + 0x2d8;` = 멤버 앵커표의 i 번째 — 이름을 붙여 둔다
        am = re.match(r"^(\w+)\s*=\s*\(?this \+ ([^;]+?)\)?;$", st)
        if am:
            alias[am.group(1)] = "ANCHOR[%s]" % am.group(2).strip()
            continue

        m = VCALL.search(st)
        if not m:
            m = BATCHCALL.search(st)
            if not m:
                continue
            recv, slot, args = "@batch" + m.group(1), m.group(2), m.group(3)
            alist = [a.strip() for a in split_args(args)]
            child = next((a for a in alist if a in objs), None)
            if child is not None and SLOT.get(slot, "").startswith("addChild"):
                objs[child]["ops"].append({"op": "addToBatch",
                    "arg": ", ".join(a for a in alist if a != child and "this" not in a)})
            continue
        recv, slot, args = m.group(1), m.group(2), m.group(3)
        name = SLOT.get(slot)
        if name is None:
            continue
        alist = [a.strip() for a in split_args(args)]
        # this 는 첫 인자이거나(정상) 마지막 인자다(Ghidra 인자 밀림 — 실수 인자일 때)
        target = None
        for cand in (alist[0] if alist else "", alist[-1] if alist else ""):
            if cand in objs:
                target = cand
                break
        if target is None:
            target = recv if recv in objs else None
        if target is None:
            # 배치노드/부모가 수신자인 addChild — **자식 쪽**에 기록한다
            if name.startswith("addChild"):
                child = next((a for a in alist if a in objs), None)
                if child is not None:
                    objs[child]["ops"].append({"op": "addTo",
                        "arg": ", ".join(a for a in alist if a != child)})
            continue
        rest = [a for a in alist if a != target]
        if name in ("setPosition", "setAnchorPoint"):
            v = rest[0] if rest else "?"
            if v in alias:
                v = alias[v]
            elif v in pts and not pending:
                v = pts[v]
            elif pending:
                v, pending = pending, ""       # 연산 결과는 이름이 끊겨 여기로 흘러든다
            elif v in pts:
                v = pts[v]
        elif name in ("addChild", "addChildTag"):
            v = ", ".join(rest)
            # 자식 쪽에도 부모를 적어 둔다
            for a in rest:
                if a in objs:
                    objs[a]["parent"] = objs[target].get("frame", "?")
        else:
            v = ", ".join(rest)
        objs[target]["ops"].append({"op": name, "arg": v})
    return order


def split_args(s: str) -> list[str]:
    out, d, cur = [], 0, ""
    for ch in s:
        d += (ch == "(") - (ch == ")")
        if ch == "," and d == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur)
    return out


def render(el: str, nodes: list[dict]) -> list[str]:
    out = [f"### {el}", ""]
    for n in nodes:
        tag = "  [loop]" if n.get("loop") else ""
        par = ("  ← 부모 %s" % n["parent"]) if n.get("parent") else ""
        out.append(f"- **{n['frame']}**{tag}{par}")
        for o in n["ops"]:
            out.append(f"    - {o['op']}({o['arg']})")
    out.append("")
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--el", default=None)
    a = ap.parse_args()

    lines = SRC.read_text(encoding="utf-8", errors="replace").splitlines()
    cuts = []
    for i, ln in enumerate(lines):
        m = HDR.match(ln)
        if m:
            cuts.append((i, m.group(1), int(m.group(3))))

    els = [a.el] if a.el else ELEMENTS
    md = ["# UltimateLayer 배치 — `extract_ultimate_layout.py` 기계 복원", "",
          "> `init<El>`(전체판) + `init<El>_C`(콜로세움 추가분)의 스프라이트 배치.",
          "> 좌표·앵커·배율·회전·z·tag 가 전부 원작 리터럴이다. 표현식은 원작 그대로 둔다.", ""]
    data: dict = {}
    for el in els:
        data[el] = {}
        for suffix in ("", "_C"):
            fn = "init%s%s" % (el.capitalize(), suffix)
            body = load_fn(fn, lines, cuts)
            if body is None:
                continue
            nodes = parse(body)
            data[el][fn] = nodes
            md.append("## %s (%d 노드)" % (fn, len(nodes)))
            md += render(el, nodes)
    if a.el:
        print("\n".join(md))
        return
    p = REPO / "docs" / "ref" / "design" / "ultimate_layer_layout.md"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text("\n".join(md) + "\n", encoding="utf-8")
    j = REPO / "data" / "recipes" / "ultimate_layout.json"
    j.write_text(json.dumps({"_tool": "scripts/tools/extract_ultimate_layout.py",
                             "_source": "docs/ref/orig_code/decomp/UltimateLayer.c",
                             "elements": data}, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"[write] {p.relative_to(REPO)}  ·  {j.relative_to(REPO)}")


if __name__ == "__main__":
    main()

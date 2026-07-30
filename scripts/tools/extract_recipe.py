"""스켈레톤-우선 파이프라인 Phase 2 — 디컴파일 → 렌더 레시피(JSON).

`docs/ref/orig_code/decomp/<Class>.c`의 Cocos 배치 관용구를 파싱해 씬 배치 스켈레톤을 추출한다.
연출/배치는 클라가 100% 담당하므로, 이 레시피가 곧 "무엇을 어디에 그리는가"의 정답.

인식하는 관용구(정적 배치 위주):
  · WorldMapBG::create(field, nameVar, ptA, ptB)   ← 월드맵 던전 조각
        nameVar ← builtin_strncpy(nameVar,"path/mapNNN.png",..) 로 역참조
        ptA/ptB ← 직전 CCPoint::CCPoint(var,X,Y)
  · CCSkeletonAnimation::createWithFile(jsonVar, plistVar, s) + CCPoint(pos)  ← 스파인 앰비언트
  · createWithSpriteFrameName("path/frame.png") + CCPoint(pos)               ← 스프라이트

한계: 데이터주도 배치(배열 루프)·좌표 표현식(`v*-0.5+870`)은 리터럴만 추출하고 나머지는
`_flags`에 표시. 값은 사용자/후속 검수 대상. 좌표계=cocos(원작), 이식 시 design.gd로 변환.

사용:  python scripts/tools/extract_recipe.py WorldMapElfLayer WorldMapDwarfLayer
       python scripts/tools/extract_recipe.py --all      # docs/ref/orig_code/decomp/*.c 전부
"""
from __future__ import annotations
import re, sys, json
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DECOMP = REPO / "docs" / "ref" / "orig_code" / "decomp"
OUT_DIR = REPO / "data" / "recipes"

RE_FUNC = re.compile(r"/\* ==== (\S+) @ (?:0x)?[0-9a-f]+ \(size=\d+\) ==== \*/")
RE_POINT = re.compile(r"CCPoint::CCPoint\((\w+),\s*(-?[\d.]+),\s*(-?[\d.]+)\)")
RE_POINT_EXPR = re.compile(r"CCPoint::CCPoint\((\w+),\s*([^,)]+),\s*([^,)]+)\)")
RE_STRNCPY = re.compile(r'(?:builtin_strncpy|strcpy)\((\w+),\s*"([^"]+)"')
RE_BG = re.compile(r"WorldMapBG::create\((0x[0-9a-f]+|\d+),\s*(\w+),\s*(\w+),\s*(\w+)\)")
RE_SPINE = re.compile(r"CCSkeletonAnimation::createWithFile\((\w+),\s*(\w+)")
RE_SPRITE = re.compile(r'createWithSpriteFrameName\("([^"]+)"\)')
RE_SETANIM = re.compile(r'setAnimation\(\w+,\s*"([^"]+)"')


def frame_key(path: str) -> str:
    """"scene/worldmap/map_elf_new/map001.png" → frame stem(경로 정규화, 변환 manifest 키와 대응)."""
    p = path[:-4] if path.endswith(".png") else path
    return p.replace("/", "_").replace(".", "_")


def parse_function(name: str, body: list[str]) -> list[dict]:
    items = []
    points: dict[str, list[float]] = {}       # var → [x,y] (리터럴만)
    strs: dict[str, str] = {}                  # var → string
    last_png = ""                              # 직전 strncpy 된 .png 경로(조각 프레임 역참조용)
    last_sprite = None
    pending_spine = None
    for ln in body:
        for m in RE_STRNCPY.finditer(ln):
            strs[m[1]] = m[2]
            if m[2].endswith(".png"):
                last_png = m[2]
        pm = RE_POINT.search(ln)
        if pm:
            points[pm[1]] = [float(pm[2]), float(pm[3])]
            # 스프라이트/스파인 위치: 직전 생성물에 좌표 부여
            if last_sprite is not None and last_sprite.get("pos") is None:
                last_sprite["pos"] = [float(pm[2]), float(pm[3])]
            if pending_spine is not None and pending_spine.get("pos") is None:
                pending_spine["pos"] = [float(pm[2]), float(pm[3])]
        # 조각(WorldMapBG)
        bm = RE_BG.search(ln)
        if bm:
            field = int(bm[1], 16) if bm[1].startswith("0x") else int(bm[1])
            frame = strs.get(bm[2]) or last_png  # name 변수 역참조 실패 시 직전 .png 사용
            pta = points.get(bm[3])
            ptb = points.get(bm[4])
            items.append({"kind": "piece", "field": field,
                          "frame": frame_key(frame) if frame else "",
                          "raw": frame, "ptA": pta, "ptB": ptb})
        # 스파인
        sm = RE_SPINE.search(ln)
        if sm:
            js = strs.get(sm[1], ""); pl = strs.get(sm[2], "")
            pending_spine = {"kind": "spine", "spine": frame_key(js), "raw": js,
                             "plist": pl, "pos": None, "anim": None}
            items.append(pending_spine)
        am = RE_SETANIM.search(ln)
        if am and pending_spine is not None:
            pending_spine["anim"] = am[1]
        # 스프라이트
        spm = RE_SPRITE.search(ln)
        if spm:
            last_sprite = {"kind": "sprite", "frame": frame_key(spm[1]),
                           "raw": spm[1], "pos": None}
            items.append(last_sprite)
    return items


def parse_class(cls: str) -> dict | None:
    path = DECOMP / f"{cls}.c"
    if not path.exists():
        return None
    lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
    # 함수 경계로 분할
    funcs: dict[str, list[str]] = {}
    cur = None
    for ln in lines:
        fm = RE_FUNC.search(ln)
        if fm:
            cur = f"{fm[1]}"; funcs.setdefault(cur, [])
        elif cur:
            funcs[cur].append(ln)
    recipe = {"_source": f"docs/ref/orig_code/decomp/{cls}.c (extract_recipe.py). 좌표=cocos원작. 이식=design.gd.",
              "class": cls, "methods": {}}
    total = 0
    for fname, body in funcs.items():
        items = parse_function(fname, body)
        if items:
            recipe["methods"][fname] = items
            total += len(items)
    recipe["_count"] = total
    return recipe if total else None


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    args = sys.argv[1:]
    if "--all" in args:
        classes = [p.stem for p in DECOMP.glob("*.c")]
    else:
        classes = [a for a in args if not a.startswith("--")]
    if not classes:
        print("클래스명 지정 또는 --all"); return
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for cls in classes:
        rec = parse_class(cls)
        if rec is None:
            print(f"[skip] {cls}: 관용구 없음/파일없음"); continue
        (OUT_DIR / f"{cls}.json").write_text(
            json.dumps(rec, ensure_ascii=False, indent=2), encoding="utf-8")
        # 요약
        kinds = {}
        for items in rec["methods"].values():
            for it in items:
                kinds[it["kind"]] = kinds.get(it["kind"], 0) + 1
        print(f"[{cls}] {rec['_count']} items {kinds} → data/recipes/{cls}.json")


if __name__ == "__main__":
    main()

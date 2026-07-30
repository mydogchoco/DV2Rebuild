"""씬 감사(audit) — 디컴파일에서 원작 씬의 구성요소를 추출해 재이식 체크리스트 생성.

풀스크린 UI 씬(cave/town/battle 등)은 worldmap과 달리 좌표가 VisibleRect 앵커 상대배치 +
변수/테마경로 프레임이라 절대좌표 레시피론 안 잡힌다. 대신 **"이 씬이 무엇으로 구성됐는가"**를 뽑아
현 구현과 갭분석하는 체크리스트를 만든다. 원작의 모든 요소 반영 여부 추적용.

각 클래스 `docs/ref/orig_code/decomp/<Class>.c`에서 추출:
  · atlases    : addSpriteFramesWithFile("...")           = 로드하는 스프라이트 아틀라스(에셋 의존성)
  · frames     : createWithSpriteFrameName("...")/CCSprite::create("literal") = 리터럴 프레임(변수/테마경로는 제외)
  · anchors    : VisibleRect::<anchor>                    = 화면앵커 배치 어휘(center/top/leftBottom…)
  · subscenes  : <GameClass>::create(                     = 인스턴스화하는 하위 씬/레이어/팝업/셀
  · spines     : CCSkeletonAnimation::createWithFile/.spine_json = 스파인
  · sounds     : playEffect/playBackground("...")         = 효과음/BGM
  · actions    : CCMoveBy/CCFadeIn/CCScaleTo/CCAnimation/runAction 존재 = 연출 유무
  · methods    : 함수 목록(무엇을 하는 씬인가)

출력: docs/ref/audit/<Class>.md (사람이 읽고 갭분석). 요약은 stdout.

사용:  python scripts/tools/audit_scene.py CaveScene TownElpisScene BattleScene
       python scripts/tools/audit_scene.py --all
"""
from __future__ import annotations
import re, sys
from collections import Counter, OrderedDict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DECOMP = REPO / "docs" / "ref" / "orig_code" / "decomp"
OUT = REPO / "docs" / "ref" / "audit"

RE_FUNC = re.compile(r"==== (\S+) @ (?:0x)?[0-9a-f]+ \(size=(\d+)\) ====")
RE_ATLAS = re.compile(r'addSpriteFramesWithFile\([^,]*,\s*"([^"]+)"')
RE_FRAME = re.compile(r'createWithSpriteFrameName\(\s*"([^"]+)"')
RE_CCSPR = re.compile(r'CCSprite::create\(\s*"([^"]+)"')
RE_ANCHOR = re.compile(r"VisibleRect::(\w+)")
RE_SUB = re.compile(r"\b([A-Z]\w+(?:Scene|Layer|Popup|Cell|Dialog|View|Menu|Item))::create\b")
RE_SPINE = re.compile(r'"([^"]+\.spine_json)"')
RE_SOUND = re.compile(r'play(?:Effect|Background|Music|Sound)\w*\([^,)]*,?\s*"([^"]+)"')
RE_ACTION = re.compile(r"\b(CCMoveBy|CCMoveTo|CCFadeIn|CCFadeOut|CCScaleTo|CCScaleBy|CCRotateBy|CCAnimation|CCBlink|CCJumpBy|CCEase)\b")


def audit(cls: str) -> dict | None:
    path = DECOMP / f"{cls}.c"
    if not path.exists():
        return None
    txt = path.read_text(encoding="utf-8", errors="ignore")
    methods = [(m[1], int(m[2])) for m in RE_FUNC.finditer(txt)]
    # 중복 메서드명(썽크+실체) 병합: 큰 사이즈만
    mm = {}
    for name, sz in methods:
        if name not in mm or sz > mm[name]:
            mm[name] = sz
    frames = sorted(set(RE_FRAME.findall(txt)) | set(RE_CCSPR.findall(txt)))
    return {
        "class": cls,
        "atlases": sorted(set(RE_ATLAS.findall(txt))),
        "frames": [f for f in frames if not f.endswith(".spine_json")],
        "anchors": sorted(set(RE_ANCHOR.findall(txt))),
        "subs": sorted(set(RE_SUB.findall(txt)) - {cls}),
        "spines": sorted(set(RE_SPINE.findall(txt))),
        "sounds": sorted(set(RE_SOUND.findall(txt))),
        "has_actions": bool(RE_ACTION.search(txt)),
        "action_kinds": sorted(set(RE_ACTION.findall(txt))),
        "methods": [n for n, _ in sorted(mm.items(), key=lambda kv: -kv[1])
                    if not n.startswith("~") and n != cls],
    }


def write_md(a: dict) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    L = [f"# 씬 감사: `{a['class']}`\n",
         f"> `docs/ref/orig_code/decomp/{a['class']}.c` 에서 추출(audit_scene.py). 재이식 갭분석 체크리스트.\n"]
    def sec(title, items, fmt="`{}`"):
        L.append(f"\n## {title} ({len(items)})\n")
        if not items:
            L.append("_(없음)_"); return
        L.append(", ".join(fmt.format(x) for x in items))
    sec("로드 아틀라스(에셋 의존성)", a["atlases"])
    sec("리터럴 프레임", a["frames"])
    sec("화면앵커 어휘(VisibleRect)", a["anchors"])
    sec("하위 씬/레이어/팝업/셀", a["subs"])
    sec("스파인", a["spines"])
    sec("사운드", a["sounds"])
    L.append(f"\n## 연출 액션\n\n{'있음: ' + ', '.join(a['action_kinds']) if a['has_actions'] else '없음'}")
    sec("메서드(크기순)", a["methods"])
    (OUT / f"{a['class']}.md").write_text("\n".join(L), encoding="utf-8")


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    args = sys.argv[1:]
    if "--all" in args:
        classes = sorted(p.stem for p in DECOMP.glob("*.c"))
    else:
        classes = [a for a in args if not a.startswith("--")]
    if not classes:
        print("클래스명 또는 --all"); return
    for cls in classes:
        a = audit(cls)
        if a is None:
            print(f"[skip] {cls}: 파일없음"); continue
        write_md(a)
        print(f"[{cls}] atlas{len(a['atlases'])} frame{len(a['frames'])} anchor{len(a['anchors'])} "
              f"sub{len(a['subs'])} spine{len(a['spines'])} sound{len(a['sounds'])} "
              f"action{'✓' if a['has_actions'] else '✗'} method{len(a['methods'])} → docs/ref/audit/{cls}.md")


if __name__ == "__main__":
    main()

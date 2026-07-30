"""자작 드래곤의 **아트 별칭** 생성 — 다른 드래곤의 그림을 자기 id 로도 부를 수 있게 한다.

`dragons.csv` 의 `notes` 에 `"루시퍼"와 동일한 이미지 사용` 처럼 적으면 `build_data.py` 가
`data/dragons.json` 에 `art_id` 를 굳힌다. 이 도구는 그 `art_id` 를 보고 **id 로 조립되는
경로들**(초상·크리티컬·스파인 씬)을 자기 id 이름으로도 만들어 둔다.

왜 이렇게 하나
--------------
render 쪽에서 드래곤 그림 경로를 만드는 곳이 40군데다(`portrait_%d` · `critical_%d` ·
`scenes/dragons/dragon_%d_%s.tscn` …). 그 전부에 `art_id` 조회를 끼워 넣는 것보다,
**빌드 때 별칭 파일을 만들어 두면 호출부를 하나도 안 건드려도 된다.**
산출물은 전부 재생성 가능(gitignore 대상)이라 원본을 복제해 두는 부담도 없다.

PNG 는 복사하지 않는다 — 별칭 `.tres` 가 원본 드래곤의 PNG 를 그대로 가리킨다.

    python scripts/tools/build_dragon_art_alias.py            # 생성
    python scripts/tools/build_dragon_art_alias.py --dry      # 무엇을 만들지만 출력
"""
from __future__ import annotations
import json, re, shutil, sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DRAGONS = REPO / "data/dragons.json"
CONV = REPO / "assets/converted"
SCENES = REPO / "scenes/dragons"

# id 로 이름이 갈리는 변환 폴더들. `<prefix><id>/` 안의 파일명·매니페스트 키에 id 가 박혀 있다.
ATLAS_DIRS = ["portrait_", "critical_", "dragon_"]


def _sub_id(text: str, src: int, dst: int) -> str:
    """단어 경계에서 src id 만 dst 로 바꾼다(3001 → 666). 좌표·해상도 숫자는 건드리지 않게
    반드시 `_<id>_` / `_<id>.` / `_<id>/` 꼴만 노린다."""
    return re.sub(r"(?<=[_/])%d(?=[_./])" % src, str(dst), text)


def alias_atlas_dir(src_dir: Path, dst_dir: Path, src: int, dst: int, dry: bool) -> int:
    """`.tres` 와 `_manifest.json` 만 별칭으로 만든다. PNG 는 원본을 그대로 가리킨다."""
    if not src_dir.is_dir():
        return 0
    n = 0
    if not dry:
        dst_dir.mkdir(parents=True, exist_ok=True)
    for f in sorted(src_dir.iterdir()):
        if f.suffix == ".tres":
            out = dst_dir / _sub_id(f.name, src, dst)
            # 파일명만 바꾸고 **내용의 ext_resource 경로는 원본 그대로** 둔다 —
            # 그래야 PNG 를 복제하지 않고 원본 텍스처를 함께 쓴다.
            if not dry:
                out.write_text(f.read_text(encoding="utf-8"), encoding="utf-8")
            n += 1
        elif f.name == "_manifest.json":
            man = json.loads(f.read_text(encoding="utf-8"))
            out_man = {_sub_id(k, src, dst): v for k, v in man.items()}
            if not dry:
                (dst_dir / "_manifest.json").write_text(
                    json.dumps(out_man, ensure_ascii=False, indent=1), encoding="utf-8")
            n += 1
    return n


def alias_scenes(src: int, dst: int, dry: bool) -> int:
    """`scenes/dragons/dragon_<id>_<stage>.tscn` 등을 파일 복사한다.
    씬 내부는 원본 아틀라스 PNG 를 가리키므로 **경로를 바꾸지 않고 그대로 복사**한다.
    ⚠️ 래퍼 씬(원본을 자식으로 물리는 방식)은 안 된다 — 호출부 일부가
    `inst.get_node_or_null("AnimationPlayer")` 로 **직속 자식**을 찾는다."""
    if not SCENES.is_dir():
        return 0
    n = 0
    for f in sorted(SCENES.glob("*.tscn")):
        m = re.fullmatch(r"(dragon|egg)_%d(_.*)?\.tscn" % src, f.name)
        if not m:
            continue
        out = SCENES / ("%s_%d%s.tscn" % (m.group(1), dst, m.group(2) or ""))
        if not dry:
            shutil.copyfile(f, out)
        n += 1
    return n


def main() -> int:
    dry = "--dry" in sys.argv
    dragons = json.loads(DRAGONS.read_text(encoding="utf-8"))
    todo = [d for d in dragons if d.get("art_id") is not None]
    if not todo:
        print("art_id 를 가진 드래곤이 없다 — 할 일 없음")
        return 0
    for d in todo:
        dst = int(d["id"])
        src = int(d["art_id"])
        made = 0
        for pre in ATLAS_DIRS:
            made += alias_atlas_dir(CONV / ("%s%d" % (pre, src)), CONV / ("%s%d" % (pre, dst)),
                                    src, dst, dry)
        made += alias_scenes(src, dst, dry)
        print("%s%-8s id=%-5d ← art %-5d  파일 %d" % (
            "(dry) " if dry else "", d["name"], dst, src, made))
    if not dry:
        print("\nGodot 을 한 번 열거나 `--headless --import` 로 임포트할 것.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

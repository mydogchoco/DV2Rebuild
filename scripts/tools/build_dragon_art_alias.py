from __future__ import annotations
import json, re, shutil, sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DRAGONS = REPO / "data/dragons.json"
CONV = REPO / "assets/converted"
SCENES = REPO / "scenes/dragons"

ATLAS_DIRS = ["portrait_", "critical_", "dragon_"]

def _sub_id(text: str, src: int, dst: int) -> str:
    return re.sub(r"(?<=[_/])%d(?=[_./])" % src, str(dst), text)

def alias_atlas_dir(src_dir: Path, dst_dir: Path, src: int, dst: int, dry: bool) -> int:
    if not src_dir.is_dir():
        return 0
    n = 0
    if not dry:
        dst_dir.mkdir(parents=True, exist_ok=True)
    for f in sorted(src_dir.iterdir()):
        if f.suffix == ".tres":
            out = dst_dir / _sub_id(f.name, src, dst)
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

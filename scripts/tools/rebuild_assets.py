from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

TOOLS = Path(__file__).resolve().parent
REPO = TOOLS.parents[1]
MAP = TOOLS / "asset_map.json"

sys.path.insert(0, str(TOOLS))

PRE_BUILDERS = ["fix_atlas_plist.py"]

ERRORS: list[str] = []

EXTRACTION_TOOLS = {
    "ccz_to_png.py": "텍스처 변환 보조",
    "fix_atlas_plist.py": "판본이 어긋난 아틀라스 2종의 좌표 보정",
    "build_intro_assets.py": "인트로 자산 반입",
}

SKIPPED: list[str] = []

def note_error(what: str, e: Exception | str):
    ERRORS.append(f"{what}: {e}")
    print(f"  [실패] {what}: {e}")

def step_atlases(m):
    import cocos_export
    for outdir, plists in m["atlases"].items():
        for pl in plists:
            if not (REPO / pl).exists():
                note_error(f"atlas {outdir}", f"원본 없음 {pl}")
                continue
            try:
                cocos_export.export(pl, outdir)
            except Exception as e:
                note_error(f"atlas {outdir} ({pl})", e)

def step_copies(m):
    for outdir, files in m["copies"].items():
        for relname, src in files.items():
            s = REPO / src
            d = REPO / "assets" / "converted" / outdir / relname
            if not s.exists():
                note_error(f"copy {outdir}/{relname}", f"원본 없음 {src}")
                continue
            d.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(s, d)

def step_dragons(m):
    import spine_export
    src = REPO / "DV2" / "480" / "dragon"
    for did in m["spine_dragons"]:
        did = str(did)
        for st in ("baby", "child", "adult", "e"):
            if (src / f"dragon_{did}_{st}_spine.spine_json").exists():
                try:
                    spine_export.export(did, st, "all")
                except Exception as e:
                    note_error(f"dragon {did} {st}", e)
        for awaken in (False, True):
            stem = f"dragon_{did}_{'e_critical' if awaken else 'critical'}_spine.spine_json"
            if (src / stem).exists():
                try:
                    spine_export.export_critical(did, awaken=awaken)
                except Exception as e:
                    note_error(f"dragon {did} critical(awaken={awaken})", e)

def step_monsters(m):
    import spine_export
    for mid in m["spine_monsters"]:
        try:
            spine_export.export_monster(str(mid))
        except Exception as e:
            note_error(f"monster {mid}", e)

def step_scenes(m):
    import spine_export
    overrides = m.get("spine_scene_atlas", {})
    for name, path in m["spine_scenes"].items():
        if not path:
            note_error(f"scenespine {name}", "원본 경로 미상")
            continue
        if not (REPO / path).exists():
            SKIPPED.append(f"scenespine {name} (원본 없음)")
            continue
        atlas = overrides.get(name)
        try:
            spine_export.export_scene(path, atlas_path=atlas)
        except Exception as e:
            note_error(f"scenespine {name}", e)

def step_custom(m):
    import spine_export
    for outdir, info in m["spine_custom"].items():
        sj = info.get("spine_json", "")
        if not sj:
            note_error(f"custom {outdir}", "원본 경로 미상")
            continue
        atl = info.get("atlas") or (os.path.splitext(sj)[0] + ".img_plist")
        if not (REPO / atl).exists():
            base = os.path.splitext(sj)[0]
            alt = base[:-len("_spine")] + "_spine.img_plist" if base.endswith("_spine") else base + "_spine.img_plist"
            atl = alt if (REPO / alt).exists() else atl
        target = os.path.join("assets", "converted", outdir)
        for stem in info.get("jsons") or ["scene"]:
            try:
                spine_export.export(outdir.replace("/", "_"), stem, "all",
                                    sj_path=sj, atlas_paths=[atl], outdir=target)
            except Exception as e:
                note_error(f"custom {outdir}/{stem}", e)

def _godot():
    import run_all_tests
    return run_all_tests.find_godot()

def step_import(m):
    godot = _godot()
    if not godot:
        note_error("import", "godot 실행 파일을 찾지 못함(GODOT 환경변수로 지정)")
        return
    r = subprocess.run([godot, "--headless", "--path", str(REPO), "--import"],
                       cwd=REPO, capture_output=True)
    if r.returncode != 0:
        note_error("import", f"exit {r.returncode}")

def step_gdscenes(m):
    godot = _godot()
    if not godot:
        note_error("gdscenes", "godot 실행 파일을 찾지 못함(GODOT 환경변수로 지정)")
        return
    r = subprocess.run([godot, "--headless", "--path", str(REPO),
                        "--script", "res://scripts/tools/build_all.gd"], cwd=REPO)
    if r.returncode != 0:
        note_error("gdscenes build_all", f"exit {r.returncode}")
    for out_tscn, in_json in m.get("gd_scenes", {}).items():
        r = subprocess.run([godot, "--headless", "--path", str(REPO),
                            "--script", "res://scripts/tools/build_spine_scene.gd",
                            "--", f"res://{in_json}", f"res://{out_tscn}"], cwd=REPO)
        if r.returncode != 0:
            note_error(f"gdscenes {out_tscn}", f"exit {r.returncode}")

def run_builder(name):
    p = TOOLS / name
    if not p.exists():
        if name in EXTRACTION_TOOLS:
            SKIPPED.append(f"{name} ({EXTRACTION_TOOLS[name]})")
        else:
            note_error(f"builder {name}", "스크립트 없음")
        return
    r = subprocess.run([sys.executable, str(p)], cwd=REPO)
    if r.returncode != 0:
        note_error(f"builder {name}", f"exit {r.returncode}")

def step_pre(m):
    for b in PRE_BUILDERS:
        run_builder(b)

ALWAYS_BUILDERS = ["build_dragon_art_alias.py"]

def step_builders(m):
    done = set(PRE_BUILDERS)
    for b in ALWAYS_BUILDERS:
        done.add(b)
        print(f"-- {b}")
        run_builder(b)
    for b in sorted(set(m["builders"].values())):
        if b in done:
            continue
        done.add(b)
        print(f"-- {b}")
        run_builder(b)

STEPS = [
    ("pre", step_pre),
    ("atlases", step_atlases),
    ("copies", step_copies),
    ("dragons", step_dragons),
    ("monsters", step_monsters),
    ("scenes", step_scenes),
    ("custom", step_custom),
    ("builders", step_builders),
    ("import", step_import),
    ("gdscenes", step_gdscenes),
]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", help="지정한 단계만 (예: --only atlases)")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()

    m = json.loads(MAP.read_text(encoding="utf-8"))
    os.chdir(REPO)

    if args.list:
        print(f"atlases {len(m['atlases'])}폴더 · copies {len(m['copies'])} · dragons {len(m['spine_dragons'])}"
              f" · monsters {len(m['spine_monsters'])} · scenes {len(m['spine_scenes'])}"
              f" · custom {len(m['spine_custom'])} · builders {len(set(m['builders'].values()))}")
        for u in m.get("unresolved", []):
            print(f"  (로컬 전용) {u['dir']} — {u['note']}")
        return 0

    if not (REPO / "DV2" / "480").is_dir():
        print("DV2/480 이 비어 있다 — 원작 추출 에셋을 DV2/ 에 넣은 뒤 다시 실행.")
        return 1

    for name, fn in STEPS:
        if args.only and name not in args.only:
            continue
        print(f"== {name} ==")
        fn(m)

    if SKIPPED:
        print("\n건너뛴 단계(보조 도구는 배포에 없다 — 암호화되지 않은 에셋을 전제한다):")
        for s in SKIPPED:
            print(f"  {s}")
    if m.get("unresolved"):
        print("\n다음 폴더는 이 스크립트가 재생성하지 못한다(별도 제작물):")
        for u in m["unresolved"]:
            print(f"  {u['dir']}")
    if ERRORS:
        print(f"\n실패 {len(ERRORS)}건:")
        for e in ERRORS[:60]:
            print(" ", e)
        return 1
    print("\n완료. 임포트까지 끝냈으니 Godot 으로 열면 바로 실행된다.")
    return 0

if __name__ == "__main__":
    sys.exit(main())

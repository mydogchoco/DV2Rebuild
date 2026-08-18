#!/usr/bin/env python3
from __future__ import annotations

import argparse
import io
import os
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
ICO_SIZES = [(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (24, 24), (16, 16)]

def template_exe() -> Path:
    base = Path(os.environ.get("APPDATA", "")) / "Godot" / "export_templates"
    cands = sorted(base.glob("*/windows_release_x86_64.exe"), reverse=True)
    if not cands:
        raise SystemExit(
            "Windows 내보내기 템플릿을 못 찾았다.\n"
            "  Godot 에디터 → 편집기 → 내보내기 템플릿 관리 → 다운로드 후 다시 실행할 것.\n"
            f"  찾은 위치: {base}")
    return cands[0]

def godot_icon(exe: Path):
    try:
        import pefile
    except ImportError:
        raise SystemExit("pefile 이 필요하다:  python -m pip install pefile")
    from PIL import Image

    pe = pefile.PE(str(exe), fast_load=True)
    pe.parse_data_directories([pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_RESOURCE"]])
    best = None
    for entry in pe.DIRECTORY_ENTRY_RESOURCE.entries:
        if entry.id != 3:
            continue
        for res in entry.directory.entries:
            for lang in res.directory.entries:
                d = lang.data.struct
                data = pe.get_data(d.OffsetToData, d.Size)
                if data[:8] == b"\x89PNG\r\n\x1a\n":
                    best = data
    if best is None:
        raise SystemExit("템플릿에서 PNG 아이콘을 못 찾았다(판본이 바뀌었을 수 있다).")
    return Image.open(io.BytesIO(best)).convert("RGBA")

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(REPO), help="출력 폴더(기본=레포 루트)")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    exe = template_exe()
    im = godot_icon(exe)
    print("원본: %s  (%dx%d)" % (exe.name, im.width, im.height))

    (out / "icon.png").write_bytes(b"")
    im.save(out / "icon.png")
    im.save(out / "icon.ico", format="ICO", sizes=ICO_SIZES)
    print("→", (out / "icon.png"))
    print("→", (out / "icon.ico"), "(%d사이즈)" % len(ICO_SIZES))
    print("\n자기 아이콘으로 바꾸려면 이 두 파일을 덮어쓰면 된다.")
    print("  PNG → ICO:  python -c \"from PIL import Image;"
          " im=Image.open('icon.png').convert('RGBA');"
          " im.save('icon.ico', sizes=%s)\"" % ICO_SIZES)
    return 0

if __name__ == "__main__":
    sys.exit(main())

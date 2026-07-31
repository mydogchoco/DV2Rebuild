#!/usr/bin/env python3
"""게임 시작 화면(원작 `IntroScene`) 자산 반입 — APK → 복호 → `DV2/480/` → `assets/converted/`.

## 왜 별도 도구인가

`DV2/480/` 추출본에는 **intro 계열이 통째로 없다**(`asset_index.py --grep intro` → 음악·파티클뿐).
그런데 원작 APK 에는 전부 들어 있고, 다만 텍스처가 **XXTEA 암호화 CCZ**(`CCZp`)라 그냥 못 읽는다.
키는 이미 복원돼 있다([[dv2-ccz-decryption]], `ccz_to_png.py`) — common/9patch 를 같은 방식으로
반입한 전례가 있다. 이 스크립트는 그 절차를 intro 에 대해 재현 가능하게 묶은 것이다.

    python scripts/tools/build_intro_assets.py           # 반입 + 변환
    python scripts/tools/build_intro_assets.py --dry     # 무엇을 할지만 출력

## 하는 일

1. `Dragon+Village+2.apk` 에서 intro 자산을 꺼낸다(§원본 우선 — 우리가 그리지 않는다).
2. `.pvr.ccz` 를 복호해 `.png` 로 굽고 `DV2/480/` 에 원작과 같은 경로로 놓는다.
   (원본 레포는 읽기 전용이지만 **복호 산출물 배치**는 common/9patch 때와 같은 정규 절차다.)
3. `cocos_export.py intro.img_plist intro_ui` — 시작 화면 UI 프레임 17종.
4. `spine_export.py --scene intro2020_3_spine` — 타이틀 스파인(중간 JSON).
   Godot 씬(.tscn) 빌드는 엔진이 필요해 여기서 하지 않는다 — 아래 명령을 이어서 돌린다:

    godot --headless --path . --script res://scripts/tools/build_spine_scene.gd -- \
        assets/converted/scenespine_intro2020_3_spine/scene.json scenes/fx/intro_title_spine.tscn

## 제외 (사용자 확정 2026-07-31)

`intro/game.*` = **리듬 미니게임**(`IntroScene::onClickMiniGame` → `MiniGameLayer`) 이라 반입하지
않는다. 같은 이유로 `music/bg_note_intro`·`effect_intro_*` 도 `build_music.py` 대상이 아니다.
`intro_etc.*`(로그인·회원가입 팝업 부품)·`intro_cloud`·`intro_dragon`·`intro_spine`(구판 인트로
연출)도 §2-1 로 컷된 화면의 부품이라 제외한다.
"""
from __future__ import annotations

import subprocess
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

REPO = Path(__file__).resolve().parents[2]
APK = REPO / "Dragon+Village+2.apk"
DV2 = REPO / "DV2" / "480"

# APK 경로 → DV2/480 상대 경로. `.pvr.ccz` 는 복호해 같은 이름 `.png` 로 굽는다.
PLAIN = [
    "intro.img_plist",
    "intro/intro2020_3_spine.spine_json",
    "intro/intro_spine2020_3_spine9.img_plist",
    # ── 구판 타이틀(사용자 확정 2026-07-31: 설정에서 고를 수 있게 한다) ──
    # 배치 코드는 구 libgame.so 와 함께 유실됐지만(5.1.1 문자열 전수에 이 이름들이 없다)
    # **트림 메타에 캔버스 안 위치가 박혀 있어** 정지 배치는 원본 근거로 복원된다:
    #   intro_dragon: sourceSize {768,519} 트림 없음 = 리소스 전체 화면
    #   intro_cloud : sourceSize {768,519} · offset {0,38} = 캔버스 중앙에서 38pt 위
    "intro/intro_dragon.img_plist",
    "intro/intro_cloud.img_plist",
    "intro/intro_logo_kr.png",
]
ENCRYPTED = [
    ("intro.pvr.ccz", "intro.png"),
    ("intro/intro_spine2020_3_spine9.pvr.ccz", "intro/intro_spine2020_3_spine9.png"),
    ("intro/intro_dragon.pvr.ccz", "intro/intro_dragon.png"),
    ("intro/intro_cloud.pvr.ccz", "intro/intro_cloud.png"),
]


def main() -> int:
    dry = "--dry" in sys.argv
    if not APK.exists():
        print(f"[error] APK 없음: {APK}")
        return 1

    z = zipfile.ZipFile(APK)

    def read(rel: str) -> bytes:
        return z.read("assets/480/" + rel)

    for rel in PLAIN:
        dst = DV2 / rel
        print(f"  copy   {rel}  ({len(read(rel))}B)")
        if not dry:
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(read(rel))

    # 구판 타이틀 맨 아래 하늘 배경(사용자 지시 2026-07-31). ⚠️ 원본 파일명이 **오타**다 —
    # `load_main_bg` 가 아니라 `loag_main_bg.jpg`. APK 가 아니라 이미 가진 `DV2/480/` 에 있고,
    # libgame.so 문자열 전수에 `loag` 가 없어 **원작 코드가 부르지 않는 자산**이다(=구판 잔재).
    sky_src = REPO / "DV2" / "480" / "scene" / "adventure" / "load_bg" / "loag_main_bg.jpg"
    sky_dst = REPO / "assets" / "converted" / "intro_old_bg" / "loag_main_bg.jpg"
    if sky_src.exists():
        print(f"  copy   {sky_src.name} -> {sky_dst.parent.name}/")
        if not dry:
            sky_dst.parent.mkdir(parents=True, exist_ok=True)
            sky_dst.write_bytes(sky_src.read_bytes())
    else:
        print(f"[warn] 하늘 배경 없음: {sky_src}")

    from ccz_to_png import decrypt_ccz, pvr_to_image

    for src, out in ENCRYPTED:
        dst = DV2 / out
        tmp = DV2 / src
        print(f"  decode {src} -> {out}")
        if dry:
            continue
        dst.parent.mkdir(parents=True, exist_ok=True)
        tmp.write_bytes(read(src))
        img = pvr_to_image(decrypt_ccz(tmp))
        img.save(dst)
        tmp.unlink()
        print(f"         {img.width}x{img.height} {img.mode}")

    if dry:
        return 0

    # ── 변환 ────────────────────────────────────────────────────────────────
    tools = Path(__file__).resolve().parent
    runs = [
        [sys.executable, str(tools / "cocos_export.py"), str(DV2 / "intro.img_plist"), "intro_ui"],
        [sys.executable, str(tools / "cocos_export.py"),
         str(DV2 / "intro/intro_dragon.img_plist"), "intro_old_bg"],
        [sys.executable, str(tools / "cocos_export.py"),
         str(DV2 / "intro/intro_cloud.img_plist"), "intro_old_cloud"],
        [sys.executable, str(tools / "spine_export.py"),
         "--scene", str(DV2 / "intro/intro2020_3_spine.spine_json"),
         "--atlas", str(DV2 / "intro/intro_spine2020_3_spine9.img_plist")],
    ]
    for cmd in runs:
        print("  run   ", " ".join(Path(c).name if "/" in c or "\\" in c else c for c in cmd[1:]))
        r = subprocess.run(cmd, cwd=REPO)
        if r.returncode != 0:
            print("[error] 변환 실패")
            return r.returncode
    print("\n다음: godot --headless --path . --script res://scripts/tools/build_spine_scene.gd -- \\")
    print("        assets/converted/scenespine_intro2020_3_spine/scene.json"
          " scenes/fx/intro_title_spine.tscn")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

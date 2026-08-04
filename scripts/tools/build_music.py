#!/usr/bin/env python3
"""원작 사운드(`DV2/music/*.mp3`) 중 **코드가 실제로 참조하는 것**만 `assets/music/` 로 복사한다.

`assets/music/` 는 gitignore 대상(저작권 자료)이라 이 스크립트가 반입 기록이자 재생성 수단이다.
원본 318곡을 통째로 넣지 않고, 우리 `scripts/**/*.gd` 가 부르는 키만 골라 넣는다:

  · `Bgm.sfx("<key>")` / `Bgm.play("<key>")` 의 리터럴
  · `data/worldmap.json` 의 `native.sounds[].track`(구역 앰비언트 — 코드가 아니라 데이터에 있다)
  · `"effect_skill_%d" % sid` 처럼 **런타임 조립**되는 것은 패턴으로 지정(아래 PATTERNS)

    python scripts/tools/build_music.py           # 복사
    python scripts/tools/build_music.py --dry     # 무엇을 넣을지만 출력

스킬 전용 효과음 근거
--------------------
docs/ref/orig_code/decomp/AdventureScene.c:57622 `CCString::createWithFormat("music/effect_skill_%d.mp3", …)`.
`DV2/music/effect_skill_N.mp3` 의 N 24종이 **전부 data/skills.json 의 스킬 id**이고
스킬 id 아닌 N은 하나도 없다 → N = 스킬 id.
"""
from __future__ import annotations

import re
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SRC = REPO / "DV2" / "music"
DST = REPO / "assets" / "music"
SCRIPTS = REPO / "scripts"

LITERAL = re.compile(r'Bgm\.(?:sfx|loop_sfx|play)\(\s*"([a-zA-Z0-9_]+)"')
# 런타임 조립 키 — 원본에 존재하는 것만 자동으로 걸린다.
PATTERNS = [
    re.compile(r"^effect_skill_\d+$"),        # 스킬 전용 효과음(= 스킬 id)
    re.compile(r"^effect_critical_[a-z0-9_]+$"),  # 속성별 크리티컬
    re.compile(r"^bg_\d+$"),                  # 던전(필드) BGM = bg_<필드id> (배경 bg_<필드id>.jpg 와 동일 번호)
    # 일반공격 타입별 효과음 — battle.gd `_ATK_FX` 테이블에서 고르므로 `Bgm.sfx("리터럴")`
    # 스캔에 안 걸린다. scratch/headbutt 는 원작 전투 프리로드 목록에 실재한다
    # (MakeInterface::preloadHeavyResource, docs/ref/orig_code/decomp/MakeInterface.c:28239·28416).
    re.compile(r"^effect_(bite|scratch|headbutt)$"),   # headbutt = 크리티컬 타격(_CRIT_FX)
    # 드래곤 보이스 — 원작 `info_dragon_v2.voice_{baby,child,adult,critical}_no` → `music/voice<N>.mp3`
    # (docs/ref/orig_code/decomp/Dragon.c:13478-13526). battle.gd 가 `"voice%d"` 로 조립하므로 리터럴 스캔에 안 걸린다.
    re.compile(r"^voice\d+$"),
    # 부화 빛기둥 타격음 — cave.gd 가 상수(`EGG_BEAT_SFX`)로 들고 있어 리터럴 스캔에 안 걸린다.
    # ⚠️ 원작 대응은 미확정(디컴프에 없는 익명 람다가 낸다) — docs/ref/porting/EggHatch.md §6.3.
    re.compile(r"^effect_egg$"),
    # 드래곤 피격음 — `rand()&1` 로 둘 중 하나. `"effect_dragon_damaged_%d"` 로 조립하므로
    # 리터럴 스캔에 안 걸린다(그래서 `_2` 가 통째로 빠져 있었다 — 2026-08-05 발견).
    # 원작: `InterFace::setCallHitSound` @00d3adec(탐험) ·
    #       `MakeInterface::runSpineWithAnimationName` @0104f468(콜로세움, 볼륨 0.25~0.50).
    re.compile(r"^effect_dragon_damaged_[12]$"),
]


def wanted_keys() -> set[str]:
    keys: set[str] = set()
    for gd in SCRIPTS.rglob("*.gd"):
        try:
            keys.update(LITERAL.findall(gd.read_text(encoding="utf-8", errors="replace")))
        except OSError:
            continue
    # 구역 앰비언트(원작 WorldMap*Layer::initSound)는 data 에 있다 — 코드 스캔에 안 걸린다.
    import json
    wm = json.loads((REPO / "data" / "worldmap.json").read_text(encoding="utf-8"))
    for reg in wm.get("regions", []):
        # 지역 BGM 도 데이터에 있다(`regions[].bgm`) — 코드 리터럴이 아니라 여기서 걷는다.
        # 빠뜨리면 그 지역만 조용히 이전 곡을 이어 튼다(우노 도입 때 실제로 그랬다).
        if reg.get("bgm"):
            keys.add(str(reg["bgm"]))
        for snd in reg.get("native", {}).get("sounds", []):
            if snd.get("track"):
                keys.add(str(snd["track"]))
        # 필드 터치 연출 효과음(원작 setMapAnimation) — data 의 field_fx[].sound.
        # 이걸 안 걷어서 던전 클릭 효과음이 전부 조용히 빠져 있었다(2026-07-29 사용자 검수).
        for fx in reg.get("native", {}).get("field_fx", []):
            if fx.get("sound"):
                keys.add(str(fx["sound"]))
    # 카데스의 공간 월드맵 BGM 도 데이터에 있다(data/kades.json bgm_worldmap).
    # 원작 확정: WorldMapScene::setBackground → "music/utakan_worldmap_bgm.mp3".
    kd = json.loads((REPO / "data" / "kades.json").read_text(encoding="utf-8"))
    if kd.get("bgm_worldmap"):
        keys.add(str(kd["bgm_worldmap"]))
    # 시나리오 연출 BGM — 원작 `ScenarioSupport::playBackGroundFieldMusic` 의 번호→트랙 표를
    # 디컴프에서 뽑아 data/scenario_flow.json `bgm` 에 담아 뒀다. story.gd 는 그 값을 변수로
    # 넘기므로 `Bgm.play("리터럴")` 스캔에 안 걸린다 — 여기서 걷지 않으면 스토리가 조용해진다.
    sf = REPO / "data" / "scenario_flow.json"
    if sf.exists():
        for track in json.loads(sf.read_text(encoding="utf-8")).get("bgm", {}).values():
            if track:
                keys.add(str(track))
    # 콜로세움 BGM — 로비 1곡 + **대전 랜덤 목록**(data/colosseum.json `bgm`).
    # fight.gd 가 `Colosseum.battle_bgm()` 로 골라 넘기므로 리터럴 스캔에 안 걸린다
    # (안 걷으면 목록의 2번째 곡부터 파일이 없어 조용히 무음이 된다 — 2026-08-05 실제로 그랬다).
    cs = REPO / "data" / "colosseum.json"
    if cs.exists():
        bgm = json.loads(cs.read_text(encoding="utf-8")).get("bgm", {})
        if bgm.get("lobby"):
            keys.add(str(bgm["lobby"]))
        for t in bgm.get("battle", []):
            keys.add(str(t))
    for mp3 in SRC.glob("*.mp3"):
        stem = mp3.stem
        if any(p.match(stem) for p in PATTERNS):
            keys.add(stem)
    return keys


def main() -> None:
    if not SRC.is_dir():
        raise SystemExit(f"원본 음원 폴더 없음: {SRC}")
    dry = "--dry" in sys.argv
    DST.mkdir(parents=True, exist_ok=True)
    keys = wanted_keys()
    copied = skipped = missing = 0
    for k in sorted(keys):
        src = SRC / f"{k}.mp3"
        dst = DST / f"{k}.mp3"
        if not src.exists():
            missing += 1
            print(f"  (원본 없음) {k}")
            continue
        if dst.exists():
            skipped += 1
            continue
        if not dry:
            shutil.copy2(src, dst)
        copied += 1
        print(f"  + {k}")
    print(f"\n참조 키 {len(keys)} / 복사 {copied} / 기존 {skipped} / 원본없음 {missing}")
    if not dry:
        print("Godot 에디터를 한 번 열거나 `--headless --import` 로 임포트할 것.")


if __name__ == "__main__":
    main()

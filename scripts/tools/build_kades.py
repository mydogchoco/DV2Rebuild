"""카데스의 공간 — 던전별 아티팩트 배정 + 모드 규칙 빌드.

산출:
  · data/drops.json  `kades.artifact_by_dungeon`  (유타칸 15던전 × 4종)
  · data/kades.json                                (모드 규칙 — 위키 확정분)
  · docs/input/sheets/artifact_by_dungeon.csv      (배정 결과를 시트에도 되적음)

## 아티팩트 배정 근거

위키 `dungeon_1.pdf` §2: "이그니스, 루멘, 마리스, 옵스큐럼, 벤투스, 테라 6종류가 있으며
**각 지역마다 나오는 아티펙트가 다르니** 자신에게 필요한 아티펙트에 맞춰 탐험하자."
→ "지역마다 다르다"는 사실만 확정이고 **어느 지역에 어느 종류인지 표는 위키에도 없다**.
사용자 지시(2026-07-29): "던전마다 4종류씩 임의 할당시켜."

⇒ 아래 표는 **자작**이다(원작값 아님). 던전 테마에 맞는 속성을 우선 넣고, 6종이 각각
정확히 10번씩 나오도록 균등하게 맞췄다. 튜닝 노브 = 이 파일의 ASSIGN.

## 모드 규칙 근거

· 월드맵 BGM: **원작 코드 확정** — `WorldMapScene::setBackground` (decomp :17170)
    `if (GameManager::getDBYutakanKades() == 1) "music/utakan_worldmap_bgm.mp3"`
    `else "music/bg_yutakan.mp3"`
· 던전 BGM: **원작 코드 확정** — `Field::getSoundPath` (decomp Field.c:358) 은 필드 id 를
    `fid % 600`(600번대) / `fid % 500`(500번대) 로 되돌린 뒤 `music/bg_%d.mp3` 를 만든다.
    ⇒ 카데스 던전은 **기본 필드와 같은 곡**을 쓴다(전용 곡 없음).
· 나머지(난이도 전설 고정 / 미각성 페널티 / 보스 Lv120~200 / 매 탐험 전투 / 지도 불가 /
    빛의 탑 진입 불가): 위키 `dungeon_1.pdf` §2 서술.

usage: python scripts/tools/build_kades.py
"""
from __future__ import annotations
import collections, csv, io, json
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DROPS = REPO / "data/drops.json"
OUT_KADES = REPO / "data/kades.json"
SHEET = REPO / "docs/input/sheets/artifact_by_dungeon.csv"

TYPES = ["이그니스", "루멘", "마리스", "옵스큐럼", "벤투스", "테라"]

# stage_id -> 던전명, 나오는 아티팩트 4종 (자작 — 위 문서 참조)
ASSIGN = {
    1:  ("희망의 숲",     ["테라", "벤투스", "루멘", "마리스"]),
    2:  ("난파선",       ["마리스", "벤투스", "옵스큐럼", "테라"]),
    3:  ("불의 산",      ["이그니스", "테라", "루멘", "옵스큐럼"]),
    4:  ("바람의 신전",   ["벤투스", "루멘", "테라", "이그니스"]),
    5:  ("하늘의 신전",   ["루멘", "벤투스", "이그니스", "마리스"]),
    6:  ("해골 요새",     ["옵스큐럼", "이그니스", "테라", "벤투스"]),
    7:  ("수목신의 묘지", ["테라", "옵스큐럼", "마리스", "루멘"]),
    8:  ("혼돈의 틈새",   ["옵스큐럼", "이그니스", "루멘", "벤투스"]),
    9:  ("수중동굴",     ["마리스", "테라", "옵스큐럼", "이그니스"]),
    10: ("몽환의 수정터", ["루멘", "마리스", "벤투스", "옵스큐럼"]),
    11: ("오색호수",     ["마리스", "루멘", "이그니스", "테라"]),
    12: ("원혼의 폭포",   ["옵스큐럼", "마리스", "벤투스", "이그니스"]),
    13: ("도적의 이글루", ["마리스", "테라", "루멘", "옵스큐럼"]),
    14: ("칼바람의 산맥", ["벤투스", "테라", "이그니스", "마리스"]),
    15: ("빛의 탑",      ["루멘", "이그니스", "옵스큐럼", "벤투스"]),
}


def main() -> int:
    # --- 균등 검사(자작표의 자기 점검) ---
    cnt = collections.Counter(t for _, ts in ASSIGN.values() for t in ts)
    assert set(cnt) == set(TYPES), "아티팩트 종류 표기가 6종과 다르다: %s" % sorted(cnt)
    assert len(set(cnt.values())) == 1, "종류별 등장 횟수가 균등하지 않다: %s" % dict(cnt)
    for sid, (_, ts) in ASSIGN.items():
        assert len(set(ts)) == 4, "stage %d 에 중복 종류가 있다" % sid

    # --- drops.json ---
    drops = json.loads(DROPS.read_text(encoding="utf-8"))
    kd = drops.setdefault("kades", {})
    kd["_artifact_type_note"] = (
        "위키 dungeon_1.pdf §2 는 '각 지역마다 나오는 아티펙트가 다르다'고만 적고 표가 없다. "
        "사용자 지시(2026-07-29)로 **던전마다 4종씩 자작 배정**했다(scripts/tools/build_kades.py "
        "ASSIGN — 튜닝 노브). 6종이 각각 10회씩 나오도록 균등하게 맞췄다. "
        "`artifact_by_dungeon` 에 없는 필드(엘프·드워프·우노)는 카데스 모드 자체가 없다."
    )
    kd["artifact_types"] = TYPES          # 폴백(배정표에 없는 필드용) — 6종 균등
    kd["artifact_by_dungeon"] = {str(sid): ts for sid, (_, ts) in sorted(ASSIGN.items())}
    kd["_artifact_authored"] = True
    DROPS.write_text(json.dumps(drops, ensure_ascii=False, indent=1), encoding="utf-8")

    # --- data/kades.json (모드 규칙) ---
    kades = {
        "_source": "위키 docs/ref/wiki/dungeon_1.pdf §2 카데스의 공간 + 원작 디컴프(BGM).",
        "_re_basis": [
            "월드맵 BGM = 원작 확정. WorldMapScene::setBackground (decomp :17170):",
            "  getDBYutakanKades()==1 → \"music/utakan_worldmap_bgm.mp3\", 아니면 bg_yutakan.",
            "던전 BGM = 원작 확정. Field::getSoundPath (decomp Field.c:358) 가 필드 id 를",
            "  600/500 으로 나눈 나머지로 되돌린 뒤 bg_<기본필드>.mp3 를 만든다 →",
            "  카데스 던전은 **기본 필드와 같은 곡**. 전용 던전 BGM 은 원작에도 없다.",
            "아래 수치(페널티·보스 레벨)는 위키 서술 그대로다. 페널티 적용 방식(합계 스탯에",
            "  곱)만 우리 해석이다 — 위키가 '능력치가 깎여 나간다'까지만 적는다.",
        ],
        "_wiki": [
            "'카데스의 공간으로 들어가게 되면 브금이 무섭게 바뀌고, 모든 스테이지의 난이도가 "
            "전설로 바뀌며, 유타칸 전 지역에 보라색 구름이 낀다.'",
            "'드래곤들이 각성을 하지 않은 상태에서 카데스의 공간에 진입할 경우 혼돈, 신성 속성은 "
            "35%, 탐험하고자 하는 던전의 속성이 드래곤의 속성과 같은 경우 25%, 그 이외의 드래곤은 "
            "50% 나 능력치가 깎여 나간다.'",
            "'보스 몬스터의 레벨은 120~200 사이로 랜덤하게 정해지며, 이에 따라 능력치도 달라진다.'",
            "'탐험 시마다 몬스터를 만나서 전투를 하게 된다. 지도 역시 사용 불가능하다.'",
            "'카오스 피어 레이드 할 때 제외하고 빛의 탑에 진입할 수 없다.'",
        ],
        "bgm_worldmap": "utakan_worldmap_bgm",
        "_bgm_dungeon_note": "던전 BGM 은 기본 필드와 같다(원작 Field::getSoundPath). 별도 키 없음.",
        "difficulty": "legend",
        "always_battle": True,
        "map_disabled": True,
        "light_tower_blocked": True,
        "_light_tower_note": "빛의 탑(15)은 애초에 변형 필드가 없어(DungeonBG.variant_field) "
                             "카데스 모드에서도 기본 필드로 열린다. 위키의 '진입 불가'를 그대로 "
                             "적용해 목록에서 막는다.",
        "unawakened_penalty_pct": {
            "chaos": 35,
            "holy": 35,
            "same_element": 25,
            "other": 50,
        },
        "_penalty_note": "각성하지 않은 드래곤만 받는다(각성 드래곤은 0%). "
                         "우선순위: 혼돈/신성 속성 → 35, 던전 속성과 같은 속성 → 25, 그 외 → 50. "
                         "합계 스탯(hp/att/def)에 (100-p)% 를 곱한다.",
        "boss_level": {"min": 120, "max": 200},
        "_boss_note": "위키 확정 구간. 보스 스탯은 우리 레벨 곡선으로 그 레벨까지 끌어올린다 "
                      "(원작 스탯표는 서버 유실).",
        "_authored": ["페널티를 '합계 스탯에 곱한다'는 적용 방식", "보스 스탯 산출 방법"],
    }
    OUT_KADES.write_text(json.dumps(kades, ensure_ascii=False, indent=1), encoding="utf-8")

    # --- 시트 되적기(사용자가 결과를 눈으로 확인할 수 있게) ---
    rows = list(csv.reader(io.open(SHEET, encoding="utf-8-sig")))
    head = rows[0]
    out = [head]
    for r in rows[1:]:
        if not r or not r[0].strip():
            continue
        sid = int(r[0])
        r = (r + [""] * len(head))[:len(head)]
        r[2] = " / ".join(ASSIGN[sid][1])
        r[3] = "자작 배정(build_kades.py) — 위키에 표 없음"
        out.append(r)
    with io.open(SHEET, "w", encoding="utf-8-sig", newline="") as f:
        csv.writer(f).writerows(out)

    print("artifact_by_dungeon: %d 던전" % len(ASSIGN))
    print("종류별 등장 횟수:", dict(cnt))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

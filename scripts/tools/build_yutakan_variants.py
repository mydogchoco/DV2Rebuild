"""유타칸 변형 던전(밤 501~514 / 카데스 601~614)의 몬스터 편성을 데이터에 기입한다.

유실된 서버 데이터(변형 던전 로스터)를 두 출처로 복원한다:

  · **몬스터 이름·유형·속성·스탯·스킬** = 커뮤니티 위키 `docs/ref/wiki/dungeon_1.pdf`
      §1.2 밤(1.2.1~1.2.12 던전별 보스 12종) · §1.2 머리말(지역 무관 랜덤 3종) ·
      §1.3 기타(칼리고마가) · §2.1 카데스의 공간 보스(2.1.1~2.1.4, 12종).
      (추출 텍스트 = `scratch_shots/wiki_txt/dungeon_1.txt`, `extract_wiki.py` 와 같은 소스)
  · **몬스터 번호(스프라이트 asset id)** = 사용자 확정(2026-07-29):
      #163~#174 = 밤 던전 순서대로 전용 보스 · #160~#162·#175 = 밤 지역 전역 랜덤 조우 ·
      #182~#193 = 카데스 던전 순서대로 전용 보스.
      검수 시트 = `docs/input/review/monster_sheets/monsters_160_175.png` · `monsters_176_193.png`.

⚠️ **(밤)·(카데스)에는 지정된 몬스터 외의 일반 몬스터가 등장하지 않는다**(사용자 확정).
   종전에는 `data_loader._variant_stage` 가 낮 필드의 편성을 통째로 상속했다 — 그게 오연출이었다.

변형이 있는 필드는 1~14 중 6·8 을 뺀 **12종**뿐이다(`DungeonBG.variant_field`,
원작 `WorldMapPopupLayer::init`). 추출 배경도 정확히 501~505·507·509~514 / 601~605·607·609~614 다.

사용:  python scripts/tools/build_yutakan_variants.py          # data/stages.json · data/monsters.json 갱신
       python scripts/tools/build_yutakan_variants.py --check  # 기입 여부만 확인(쓰지 않음)
"""
from __future__ import annotations
import json
import sys
from collections import OrderedDict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
STAGES = REPO / "data" / "stages.json"
MONSTERS = REPO / "data" / "monsters.json"

WIKI = "나무위키 dungeon_1 §1.2/§1.3/§2.1"

# ── 밤: 지역 무관 랜덤 조우 (위키 §1.2 머리말 + §1.3) ──────────────────────────
# "지역에 무관하게 랜덤으로 등장하는 몬스터들은 다음과 같다" (실버/골드 임프 · 검은 로브의 사도)
# §1.3 기타의 4번째 랜덤은 **블랙 윗치**다(#175, 사용자 확정 2026-07-31).
# 종전 주석의 '칼리고마가'는 위키 옮겨적기 오류였다 — 칼리고마가는 전투 그림자 몹이라 별개다.
#
# ⚠️ #160/#161 의 금·은 배정은 **스프라이트 색**으로 정했다(검수 시트 monsters_160_175.png:
#    #160 금색 · #161 은청색). 위키 서술 순서(실버 → 골드)와 반대지만 두 몬스터는 스탯이 같아
#    이름표만 달라진다.
NIGHT_RANDOM = [
    # id, 이름, 유형, 크기, 속성, att, def, hp, 스킬, 가중치
    (160, "골드 임프 (Gold Imp)", "인간형", "소형", "none", 171, 66, 456, [], 1),
    (161, "실버 임프 (Silver Imp)", "인간형", "소형", "none", 171, 66, 456, [], 1),
    (162, "검은 로브의 사도 (Black Robe)", "인간형", "중형", "chaos", 275, 66, 1680,
     ["야수의 본능", "피의 갈증"], 1),
    # 🔴 2026-07-31 이름 정정 — 이 자리는 **블랙 윗치**다(사용자 확정).
    #    위키 §1.3 을 옮기면서 '칼리고마가'로 잘못 적었고, 그 뒤 사용자가 채운
    #    `docs/input/sheets/monster_drop_pool.csv:36` 과 우리 코드 4곳
    #    (adventure_run.gd · battle.gd · test_drops.gd · adventure_events.json)은
    #    이미 전부 **#175 = 블랙 윗치**로 쓰고 있었다 — 여기만 낡아 있었다.
    #    ⚠️ 이 줄을 안 고치고 빌더를 돌리면 stages.json 의 옳은 이름이 **되돌아간다**.
    #    칼리고마가는 별개다 — **전투 그림자 몹**(사용자 확정)이라 구현 대상이 아니다
    #    (그림자 조우 = AdventureManager::setIsMonsterShadowMode, 미이식).
    (175, "블랙 윗치 (Black Witch)", "무형", "소형", "none", 264, 180, 2400, [], 1),
]
# 보스 가중치 — 위키 "보통은 처음부터 보스를 마주하지만 … 다른 몬스터가 나올 수도 있다".
# 확률 수치는 위키에 없다 → 자작 노브. 7 : 1×4 = 보스 약 64%.  # ASSUMPTION
NIGHT_BOSS_WEIGHT = 7

# ── 밤: 던전별 전용 보스 12종 (위키 §1.2.1~§1.2.12, 전부 Lv.50) ────────────────
# (기본 필드 id, asset id, 이름, 유형, 크기, 속성, att, def, hp, 스킬)
NIGHT_BOSS = [
    (1, 163, "포마스 (Fomas)", "특수형", "대형", "dark", 171, 66, 2100, ["신경독소"]),
    (2, 164, "아녹마 (Anogma)", "인간형", "중형", "aqua", 198, 12, 4560, ["치유의 빛", "빛의 정화"]),
    (3, 165, "디콘 (Decon)", "특수형", "중형", "fire", 352, 132, 780, ["심판의 날개", "야수의 본능"]),
    (4, 166, "기모모 (Gimomo)", "특수형", "중형", "earth", 193, 210, 840, ["어둠의 손길", "교차막기"]),
    (5, 167, "듀마 (Duma)", "언데드", "중형", "dark", 178, 132, 720, ["망각의 망치"]),
    (7, 168, "토라토스 (Toratos)", "특수형", "대형", "earth", 171, 480, 600, ["철갑 방패", "신의 결계"]),
    (9, 169, "고가 (Goga)", "특수형", "대형", "aqua", 308, 12, 4560, ["피의 갈증", "복수의 거울"]),
    (10, 170, "키보 (Kibo)", "인간형", "중형", "wind", 275, 138, 1020, ["시한폭탄"]),
    (11, 171, "투바로 (Tubaro)", "특수형", "중형", "chaos", 171, 540, 720, ["무언의 압박", "자연의 수호"]),
    (12, 172, "사스 (Sas)", "언데드", "대형", "dark", 198, 12, 4560, ["거신의 돌격", "시한폭탄"]),
    (13, 173, "고곤 (Gogon)", "동물형", "대형", "light", 193, 210, 900, ["상처 파악", "신의 분노"]),
    (14, 174, "아이스티톤 (Icetiton)", "무형", "대형", "aqua", 176, 216, 900,
     ["철갑 방패", "마비의 구름"]),
]
NIGHT_LEVEL = 50   # 위키 §1.2 "모든 던전의 레벨이 50으로 상향조정 됐으며"

# ── 카데스: 던전별 전용 보스 12종 (위키 §2.1.1~§2.1.4) ────────────────────────
# 위키: "보스 빼고 몹들의 모습은 달라진 게 없다. 보스도 원래 몹에 색만 바꾼것뿐이다" ⇒
# **이름은 낮 보스와 같고 스프라이트만 다르다**(#182~#193). 스탯은 낮 보스 값을 그대로 싣고,
# 진입 시 레벨 120~200 을 굴려 `battle.gd::_apply_kades_enemy` 가 보스 레벨곡선으로 끌어올린다.
KADES_BOSS = [
    (1, 182), (2, 183), (3, 184), (4, 185), (5, 186), (7, 187),
    (9, 188), (10, 189), (11, 190), (12, 191), (13, 192), (14, 193),
]


def _load(p: Path):
    return json.loads(p.read_text(encoding="utf-8"), object_pairs_hook=OrderedDict)


def _enemy(asset_id, name, element, att, dfn, hp, level, skills, boss=True, weight=None):
    e = OrderedDict()
    e["id"] = asset_id
    e["name"] = name
    e["level"] = level
    e["element"] = element
    e["hp_max"] = hp
    e["att"] = att
    e["def"] = dfn
    e["boss"] = boss
    if skills:
        e["skills"] = list(skills)
    if weight is not None:
        e["weight"] = weight
    return e


def build_stages(check: bool = False) -> int:
    d = _load(STAGES)
    stages = d["stages"]
    night_by_field = {f: row for row in NIGHT_BOSS for f in [row[0]]}
    day_boss = {}
    for f, _aid in KADES_BOSS:
        s = stages[str(f)]
        for e in s["enemies"]:
            if e.get("boss"):
                day_boss[f] = e
                break

    n = 0
    for f, aid, name, form, size, el, att, dfn, hp, skills in NIGHT_BOSS:
        s = stages[str(f)]
        nv = s.setdefault("night", OrderedDict())
        nv["level"] = NIGHT_LEVEL
        enemies = [_enemy(aid, name, el, att, dfn, hp, NIGHT_LEVEL, skills,
                          weight=NIGHT_BOSS_WEIGHT)]
        for rid, rname, _fm, _sz, rel, ratt, rdef, rhp, rskills, w in NIGHT_RANDOM:
            enemies.append(_enemy(rid, rname, rel, ratt, rdef, rhp, NIGHT_LEVEL, rskills,
                                  boss=False, weight=w))
        nv["enemies"] = enemies
        nv["random_boss"] = True
        nv["_enemies_basis"] = (
            f"{WIKI} §1.2.{NIGHT_BOSS.index(night_by_field[f]) + 1} 보스 1종 + §1.2 머리말·§1.3 "
            "지역 무관 랜덤 4종. 몬스터 번호=사용자 확정(#163~174 던전순 보스 / #160~162·175 랜덤). "
            "밤은 한 번만 탐험할 수 있고(위키) 조우도 1회다 → random_boss 로 1마리만 뽑는다. "
            "weight 는 '보통은 보스, 가끔 다른 몬스터' 를 옮긴 자작 노브(위키에 확률 없음)."
        )
        n += 1

    for f, aid in KADES_BOSS:
        s = stages[str(f)]
        db = day_boss[f]
        kv = s.setdefault("kades", OrderedDict())
        kv["enemies"] = [_enemy(aid, str(db["name"]), str(db.get("element", "none")),
                                int(db["att"]), int(db["def"]), int(db["hp_max"]),
                                int(db["level"]), db.get("skills", []))]
        kv["_enemies_basis"] = (
            f"{WIKI} §2.1 — 카데스 보스는 **낮 보스와 같은 몬스터의 색만 바뀐 판**이다"
            "('보스도 원래 몹에 색만 바꾼것뿐이다') → 이름·기본 스탯은 낮 보스 그대로, "
            f"스프라이트만 #{aid}(사용자 확정 #182~193 던전순). "
            "레벨은 진입 시 120~200 을 굴리고(data/kades.json boss_level) "
            "battle.gd::_apply_kades_enemy 가 보스 레벨곡선으로 스탯을 끌어올린다. "
            "일반 몬스터는 등장하지 않는다(사용자 확정)."
        )
        n += 1

    d["_variant_basis"] = (
        "유타칸 밤(501~514)·카데스(601~614) 편성 = scripts/tools/build_yutakan_variants.py 가 기입. "
        "각 스테이지의 night/kades 블록 참조. 변형이 있는 필드는 1~14 중 6·8 을 뺀 12종뿐이다."
    )
    if not check:
        STAGES.write_text(json.dumps(d, ensure_ascii=False, indent=1), encoding="utf-8")
    return n


def build_monsters(check: bool = False) -> int:
    d = _load(MONSTERS)
    lst = d["monsters"]
    have = {int(m.get("asset_id", 0)) for m in lst}
    rows = []
    for aid, name, form, size, el, att, dfn, hp, skills, _w in NIGHT_RANDOM:
        rows.append((aid, name, form, size, el, att, dfn, hp, skills, "yutakan_night"))
    for _f, aid, name, form, size, el, att, dfn, hp, skills in NIGHT_BOSS:
        rows.append((aid, name, form, size, el, att, dfn, hp, skills, "yutakan_night"))
    # ⚠️ 이미 있는 항목도 **이름은 맞춘다.** 종전에는 `if aid in have: continue` 로 통째 건너뛰어서
    #    이 표에서 이름을 고쳐도 monsters.json 이 낡은 채 남았다 —
    #    #175 가 stages.json 에선 '블랙 윗치', monsters.json 에선 '칼리고마가' 로 갈렸던 원인이다.
    by_id = {int(m.get("asset_id", -1)): m for m in lst}
    renamed = 0
    for aid, name, *_rest in rows:
        cur = by_id.get(aid)
        if cur is not None and str(cur.get("name", "")) != name:
            cur["name"] = name
            cur["_name_basis"] = "build_yutakan_variants.NIGHT_* 표가 이름의 단일 출처다."
            renamed += 1
    if renamed:
        print(f"  이름 정정 {renamed}건")
    n = 0
    for aid, name, form, size, el, att, dfn, hp, skills, region in rows:
        if aid in have:
            continue
        m = OrderedDict()
        m["name"] = name
        m["form"] = form
        m["size"] = size
        m["element"] = el
        m["att"] = att
        m["def"] = dfn
        m["hp"] = hp
        m["skills"] = list(skills)
        m["region"] = region
        m["asset_id"] = aid
        m["_source"] = WIKI
        lst.append(m)
        n += 1
    # 카데스 보스(#182~193)는 낮 보스의 색 변형이라 도감 항목을 새로 만들지 않는다(위키 §2.1).
    d["_variant_note"] = (
        "#160~#175 = 유타칸 밤 전용(랜덤 4 + 던전 보스 12). #182~#193 = 카데스 보스로 "
        "낮 보스의 색 변형이라 별도 도감 항목 없음(스프라이트만 다르다). "
        "출처 = " + WIKI + ", 번호 배정 = 사용자 확정 2026-07-29."
    )
    if not check:
        MONSTERS.write_text(json.dumps(d, ensure_ascii=False, indent=1), encoding="utf-8")
    return n


if __name__ == "__main__":
    chk = "--check" in sys.argv
    ns = build_stages(chk)
    nm = build_monsters(chk)
    print(f"stages: {ns} 변형 블록, monsters: {nm} 신규 항목" + (" (check only)" if chk else ""))

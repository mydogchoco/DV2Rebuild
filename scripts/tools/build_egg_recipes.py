#!/usr/bin/env python3
"""알 강화(info_upgrade_egg) · 알 조합(info_combine_egg) 레시피 채우기.

## ⚠️ HARD RULE 6 예외 — 사용자 승인 (2026-07-27)
두 테이블의 **행 값**은 원작 서버 런타임 주입분이라 유실됐고 위키에도 개수/확률이 없다.
사용자가 "어차피 유실이라 사용자도 모른다. 임의 값으로 채우고 문서화한 뒤, 문제되면 나중에
미세 조정하자"고 승인해 **자작 수치**로 채운다.

  · **스키마·재료 축**은 원작/위키 근거 그대로 유지한다(타협 없음).
  · **개수·골드·확률만** 자작이며 전부 아래 상수로 모여 있다 → 튜닝 노브.
  · 결과 JSON 의 각 레시피에 `"_authored": true` 를 박아 원작 유래분과 구분한다.

## 근거로 유지하는 것
알 강화 재료 **3칸의 정체**는 원작 클라가 알려 준다 — `LaboratoryEggLayer::setEgg` 가 빈 슬롯에
그리는 아이콘이 순서대로 `icon_element`(정령석) · `icon_stoneheart` · `icon_crystal`(결정)이다
(:4767 / :4761 / :4754, 스크린샷 `docs/ref/orig_image/lab/알강화.png` 와 일치).
등급별 재료 **티어**는 위키 `labwiki.pdf` §2.1:
    1강 = 온전한 정령석   + 온전한 스톤하트   + 속성 결정   → 부화 등급 7.0 확정
    2강 = 완벽한 정령석   + 완벽한 스톤하트   + 속성 결정   → 7.2 확정
    3강 = 완전무결한 정령석 + 완전무결한 스톤하트 + 속성 결정 → 7.5 확정
    (4강 8.0 은 이벤트 전용 → 만들지 않는다)
⚠️ 종전 판은 3번째 칸에 "이전 등급 알"을 넣었는데 근거가 없었다 — 원작의 대상 알은 왼쪽
   **알 슬롯 그 자체**이고 재료 3칸은 위 세 종류다. 2026-07-30 사용자 확정으로 결정으로 교체.
스키마(원작 클라 복원):
    upgrade: select upgrade_no, item1, item2, item3, cost from info_upgrade_egg
             where type='%s' and grade=%d           (UpgradeEgg.c:401)
             → item1..3 = (아이템번호, 개수) 쌍. LaboratoryEggLayer::setEgg :4995-5000 이
               번호(+0x3c/+0x44/+0x4c)와 개수(+0x40/+0x48/+0x50)로 갈라 읽고,
               isPosibleUpgrade :1120 가 슬롯별 보유수 ≥ 개수만 검사한다.
    combine: select combine_no, item1, item2, item3, item4 from info_combine_egg
             where target_no=%d                     (CombineEgg.c:306)

## 자작한 것
    UPGRADE_COST     등급별 골드
    UPGRADE_MAT_QTY  등급별 재료 개수
    COMBINE_COST     조합 골드
    조합표 자체(어떤 속성알 2개 → 어떤 알)

    python scripts/tools/build_egg_recipes.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
ITEMS = REPO / "data" / "items.json"
UP_OUT = REPO / "data" / "upgrade_egg.json"
CB_OUT = REPO / "data" / "combine_egg.json"
SHEET = REPO / "docs" / "input" / "review" / "egg_recipe_sheet.md"

# ── 자작 수치(튜닝 노브) ────────────────────────────────────────────────────
# grade 0→1, 1→2, 2→3. 위키가 재료 "종류"만 알려 주고 개수·비용은 침묵한다.
UPGRADE_MAT_QTY = {0: 10, 1: 10, 2: 10}       # 정령석/스톤하트/결정 각각 이만큼(사용자 확정 2026-07-30)
UPGRADE_COST = {0: 30_000, 1: 120_000, 2: 400_000}   # 골드
UPGRADE_RATE = {0: 100, 1: 100, 2: 100}       # 성공률 % — 일단 확정 성공(실패 시스템 미도입)
COMBINE_COST = 50_000                          # 알 조합 골드

# 등급별 재료 티어(위키 labwiki.pdf §2.1 — 이 축은 근거가 있다).
# 순서 = 원작 슬롯 순서(정령석 → 스톤하트 → 결정, setEgg :4767/:4761/:4754).
GRADE_MATS = {
    0: ["stone_spirit2", "stone_heart2"],      # 온전한
    1: ["stone_spirit3", "stone_heart3"],      # 완벽한
    2: ["stone_spirit4", "stone_heart4"],      # 완전무결한
}

# 3번째 칸 = **그 알 속성의 일반 결정**(위키 "속성 결정", 사용자 확정 2026-07-30).
# 알/드래곤의 element 어휘 → data/items.json 의 결정 키. aqua·earth 만 이름이 다르다.
ELEMENT_CRYSTAL = {
    "fire": "crystal_fire", "aqua": "crystal_water", "wind": "crystal_wind",
    "earth": "crystal_earth", "light": "crystal_light", "dark": "crystal_dark",
    "holy": "crystal_holy", "chaos": "crystal_chaos", "shadow": "crystal_shadow",
}
# 가상 알 키(`egg:<드래곤id>`, EggGacha)는 items.json 에 행이 없다 → 와일드카드 행 + 이 토큰으로
# 런타임에 속성을 보고 결정을 고른다(EggUpgrade.resolve_materials).
CRYSTAL_TOKEN = "@element_crystal"

# 알 조합표(자작): 같은 계열 2개 → 상위/희귀 알.
# 원작 조합표는 유실이라 "속성알 2개 → 그 속성의 상위 알" 이라는 단순 규칙을 세웠다.
COMBINE_TABLE = [
    (["mall_fire_egg", "mall_ground_egg"], "mall_haetai_egg"),      # 불+땅 → 해태
    (["mall_water_egg", "mall_wind_egg"], "mall_jaryong_egg"),      # 물+바람 → 자룡
    (["mall_light_egg", "mall_holy_egg"], "mall_back_egg"),         # 빛+신성 → 백룡
    (["mall_dark_egg", "mall_chaos_egg"], "mall_black_egg"),        # 어둠+혼돈 → 흑룡
    (["mall_dark_egg", "mall_darkpoll_egg"], "mall_bagma_egg"),     # 어둠+다크폴 → 바그마
    (["mall_fire_egg", "mall_light_egg"], "mall_gaoron_egg"),       # 불+빛 → 가오론
]


def egg_types(items: dict) -> list[str]:
    """알 종류 키 = items.json 의 category=='egg'. (`_*_basis` 같은 문자열 주석 항목은 건너뛴다.)"""
    out = []
    for k, v in items.items():
        if not isinstance(v, dict) or v.get("category") != "egg":
            continue
        out.append(k)
    return sorted(out)


def _mats(grade: int, crystal: str) -> list[dict]:
    """원작 슬롯 순서대로 재료 3칸: 정령석 · 스톤하트 · 결정."""
    out = [{"item": m, "count": UPGRADE_MAT_QTY[grade]} for m in GRADE_MATS[grade]]
    out.append({"item": crystal, "count": UPGRADE_MAT_QTY[grade]})
    return out


def build_upgrade(items: dict) -> dict:
    recipes = []
    no = 1
    for t in egg_types(items):
        el = str(items[t].get("element") or "")
        crystal = ELEMENT_CRYSTAL.get(el, "")
        if crystal == "" or crystal not in items:
            # 속성이 없는 알(의문의 알·빛나는 의문의 알)은 **개봉** 대상이라 강화하지 않는다
            # (EggGacha.is_gacha_egg → 연구소 알 목록에서도 빠진다).
            continue
        for grade in (0, 1, 2):
            recipes.append({
                "upgrade_no": no, "type": t, "grade": grade,
                "materials": _mats(grade, crystal),
                "cost": UPGRADE_COST[grade],
                "success_rate": UPGRADE_RATE[grade],
                "_authored": True,
            })
            no += 1
    # 와일드카드 3행 — 가챠로 얻는 가상 알 키(`egg:<드래곤id>`)는 items.json 에 행이 없다.
    # 결정은 토큰으로 두고 런타임에 그 드래곤 속성으로 해석한다.
    for grade in (0, 1, 2):
        recipes.append({
            "upgrade_no": no, "type": "*", "grade": grade,
            "materials": _mats(grade, CRYSTAL_TOKEN),
            "cost": UPGRADE_COST[grade],
            "success_rate": UPGRADE_RATE[grade],
            "_authored": True,
        })
        no += 1
    return {
        "_source": "원작 UpgradeEgg 모델 (docs/ref/orig_code/decomp/UpgradeEgg.c). SQLite 테이블 info_upgrade_egg.",
        "_re_basis": (
            "스키마=클라 복원: UpgradeEgg::setInfo `select upgrade_no, item1, item2, item3, cost "
            "from info_upgrade_egg where type='%s' and grade=%d`(UpgradeEgg.c:401) — item1..3 은 "
            "(아이템번호, 개수) 쌍이고 LaboratoryEggLayer::setEgg :4995-5000 이 갈라 읽는다. "
            "재료 **3칸의 정체**는 원작 클라의 빈 슬롯 아이콘이 근거 — icon_element(정령석)·"
            "icon_stoneheart·icon_crystal(결정), setEgg :4767/:4761/:4754. "
            "등급별 **티어**는 위키 labwiki.pdf §2.1(1강 온전한 / 2강 완벽한 / 3강 완전무결한 + 속성 결정). "
            "4강(8.0)은 이벤트 전용이라 제외."
        ),
        "_authored_note": (
            "⚠️ HARD RULE 6 예외(사용자 승인 2026-07-27, 개수 재확정 2026-07-30): 재료 **개수**·**골드**·"
            "**성공률**은 원작 유실이라 자작했다(각 10개). 튜닝 노브 = "
            "scripts/tools/build_egg_recipes.py 의 UPGRADE_MAT_QTY / UPGRADE_COST / UPGRADE_RATE. "
            "각 레시피의 _authored:true 가 자작 표식. docs/input/review/egg_recipe_sheet.md 참조."
        ),
        "_wildcard_note": (
            "type='*' 3행 = 가챠로 얻는 가상 알 키(`egg:<드래곤id>`, EggGacha)용 폴백. 원작에는 없는 "
            "행이지만 원작의 알은 서버 객체(Egg)였고 우리 가상 알은 items.json 에 행이 없어서 필요하다. "
            "재료 `@element_crystal` 토큰은 EggUpgrade.resolve_materials 가 그 알의 속성으로 해석한다."
        ),
        "_element_crystal": dict(ELEMENT_CRYSTAL),
        "recipes": recipes,
    }


def build_combine(items: dict) -> dict:
    recipes = []
    no = 1
    for mats, target in COMBINE_TABLE:
        if target not in items or any(m not in items for m in mats):
            continue
        recipes.append({
            "combine_no": no, "target": target, "materials": mats,
            "cost": COMBINE_COST, "_authored": True,
        })
        no += 1
    return {
        "_source": "원작 CombineEgg 모델 (docs/ref/orig_code/decomp/CombineEgg.c). SQLite 테이블 info_combine_egg.",
        "_re_basis": (
            "스키마=클라 복원: CombineEgg::setInfo `select combine_no, item1, item2, item3, item4 "
            "from info_combine_egg where target_no=%d` (CombineEgg.c:306)."
        ),
        "_authored_note": (
            "⚠️ HARD RULE 6 예외(사용자 승인 2026-07-27): **조합표 자체가 유실**이라 자작했다. "
            "규칙 = 속성알 2개 → 그 계열의 희귀 알(불+땅=해태, 물+바람=자룡, 빛+신성=백룡, "
            "어둠+혼돈=흑룡 …). 튜닝 노브 = COMBINE_TABLE / COMBINE_COST. "
            "egg_fragments.json(알조각 7세트→특수드래곤)은 이 조합과 별개 시스템이다."
        ),
        "recipes": recipes,
    }


SHEET_TMPL = """# 알 강화·조합 레시피 — 자작 수치 기록 (HARD RULE 6 예외)

> 생성기: `scripts/tools/build_egg_recipes.py` → `data/upgrade_egg.json` · `data/combine_egg.json`
> 사용자 승인(2026-07-27): "어차피 유실된 정보라 사용자도 잘 모르므로 임의 값으로 채우고 문서화.
> 문제되면 나중에 미세 조정."

## 원작 근거로 **유지**한 것 (건드리지 않음)
- 스키마: `info_upgrade_egg(upgrade_no,type,grade,item1..3,cost)` · `info_combine_egg(combine_no,target_no,item1..4)`
- 알 강화 **재료 3칸의 정체**: 원작 `LaboratoryEggLayer::setEgg` 의 빈 슬롯 아이콘
  `icon_element`(정령석) → `icon_stoneheart` → `icon_crystal`(결정) (:4767 / :4761 / :4754)
- 등급별 **티어**: 위키 `labwiki.pdf` §2.1
  - 1강 = 온전한 정령석 + 온전한 스톤하트 + 속성 결정 → 부화 등급 **7.0 확정**
  - 2강 = 완벽한 정령석 + 완벽한 스톤하트 + 속성 결정 → **7.2 확정**
  - 3강 = 완전무결한 정령석 + 완전무결한 스톤하트 + 속성 결정 → **7.5 확정**
  - 4강(8.0)은 이벤트 전용 → 만들지 않음

## 자작한 것 (튜닝 노브)

| 노브 | 현재 값 | 의미 |
|---|---|---|
| `UPGRADE_MAT_QTY` | 전 단계 10개 | 정령석·스톤하트·결정 각각의 소모 개수 |
| `UPGRADE_COST` | 3만 / 12만 / 40만 골드 | 강화 골드 |
| `UPGRADE_RATE` | 100 / 100 / 100 % | 성공률(현재 실패 시스템 미도입이라 확정 성공) |
| `COMBINE_COST` | 5만 골드 | 알 조합 골드 |
| `COMBINE_TABLE` | {ncomb}종 | 어떤 알 2개 → 어떤 알 (아래 표) |

### 알 조합표 (자작)

| 재료 | 결과 |
|---|---|
{combrows}

## 조정 방법
`scripts/tools/build_egg_recipes.py` 상단 상수만 고치고 다시 실행하면 됩니다.
데이터의 각 레시피에는 `"_authored": true` 가 붙어 있어 원작 유래분과 구분됩니다.

재료 **수급**은 `data/combine_item.json`(원작 `ItemSmeltPopup`/`info_combine_item`)의 환산 조합이 담당한다 —
조각난×12 → 온전한, ×6 → 완벽한, ×3 → 완전무결한 (위키 각주 [3]~[8] **확정치**).

관련: `docs/input/review/upgrade_egg_sheet.md`(원 스키마 시트) · `scripts/systems/egg_upgrade.gd`(규칙) ·
`scripts/ui/laboratory.gd`(알 강화 UI) · `scripts/ui/breeding.gd`(알 조합 UI).
"""


def main() -> None:
    items = json.loads(ITEMS.read_text(encoding="utf-8"))
    up = build_upgrade(items)
    cb = build_combine(items)
    if "--dry" in sys.argv:
        print(json.dumps(up["recipes"][:3], ensure_ascii=False, indent=1))
        print(json.dumps(cb["recipes"], ensure_ascii=False, indent=1))
        return
    UP_OUT.write_text(json.dumps(up, ensure_ascii=False, indent=1), encoding="utf-8")
    CB_OUT.write_text(json.dumps(cb, ensure_ascii=False, indent=1), encoding="utf-8")
    rows = "\n".join(
        "| %s | %s |" % (" + ".join(items[m]["name"] for m in r["materials"]),
                         items[r["target"]]["name"])
        for r in cb["recipes"])
    SHEET.write_text(SHEET_TMPL.format(ncomb=len(cb["recipes"]), combrows=rows), encoding="utf-8")
    print("[build_egg_recipes] upgrade %d recipes / combine %d recipes / sheet %s"
          % (len(up["recipes"]), len(cb["recipes"]), SHEET.name))


if __name__ == "__main__":
    main()

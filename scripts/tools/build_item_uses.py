"""아이템 **용도**(`use`) 채우기 — 사용자 시트 → data/items.json.

입력
----
· `docs/input/items/groups.csv`  — 39 분류의 `그룹 공통 용도` + `설명`(예외 항목).
    2026-07-29 사용자 기입 완료. 아이템 322종 중 등록분 257종의 용도가 여기서 대부분 결정된다.
· `docs/ref/wiki/item.pdf`      — 위키 서술(사용자가 "items.csv 에 필요했던 내용은 여기 있다"고 지정).
    ⇒ 그룹 답과 어긋나지 않는 선에서 **개별 아이템 보충**에만 쓴다.

무엇을 쓰나
----------
1. `use`     — 그 아이템이 무엇에 쓰이는가(한글 한 줄). 가방 상세에 그대로 나온다.
2. `offline` — 오프라인 재구현에서의 상태. 시트 답이 확정해 준 것만 고친다:
     · `impl`  이미 배선돼 동작한다
     · `todo`  용도는 알지만 그 기능이 아직 없다
     · `stub`  자리만 있다(스토리 등 상위 시스템 미구현)
     · `dummy` **원작에서도 사용처가 없던 더미**  ← 이번에 새로 생긴 상태
   `dummy` 는 "우리가 못 만든 것"이 아니라 "원작에 없던 것"이라 가방에서 다르게 안내한다.

`use` 는 표시용 텍스트다 — 규칙·수치를 담지 않는다(그건 각 시스템의 data 파일 몫).

usage: python scripts/tools/build_item_uses.py [--dry]
"""
from __future__ import annotations
import csv, io, json, sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
GROUPS = REPO / "docs/input/items/groups.csv"
ITEMS = REPO / "data/items.json"

# ── 분류별 offline 재판정 ───────────────────────────────────────────────────
# 시트 답으로 **확정된 것만** 적는다. 없는 분류는 기존 값을 그대로 둔다.
#   값 = (offline, 왜)
GROUP_OFFLINE = {
    # 배선 확인 완료 — 시트 답이 "이건 이미 되는 것"임을 확인해 줬다.
    "drink": ("impl", "cave.gd `_use_food` → ItemEffect.drink_of. 수치=data/item_effects.json"),
    "alchemy": ("impl", "점술집 연금술(magicshop.gd 용액 제작·용액 상점)이 소비한다"),
    "powder": ("impl", "점술집 젬 분해로 얻고 혼성젬 제작이 소비한다(magicshop.gd POWDERS)"),
}

# ── 아이템별 offline 재판정 ─────────────────────────────────────────────────
ITEM_OFFLINE = {
    # groups.csv consumable/qol 설명: "옛날 시스템의 잔재로 … 더미 아이템으로 남았음"
    "energy_drink": ("dummy", "탐험 피로도 회복용. 피로도 시스템이 사라진 원작에서도 더미"),
    "hero_auto1": ("dummy", "자동탐험 기간제. 자동탐험이 기본이 된 뒤 더미화"),
    "hero_auto7": ("dummy", "자동탐험 기간제. 자동탐험이 기본이 된 뒤 더미화"),
    # groups.csv document/mix_book: "더미 아이템"
    "mix_book": ("dummy", "groups.csv document/mix_book = 더미 아이템"),
    "mix_perfectbook": ("dummy", "groups.csv document/mix_book = 더미 아이템"),
    # groups.csv egg/element_egg: "단, 혼돈속성은 더미 데이터로 원작에서는 구현되지 않았음"
    "mall_chaos_egg": ("dummy", "혼돈속성 알은 원작에서 구현되지 않은 더미 데이터"),
    # §2-1 온라인 CUT
    "ticket": ("cut", "토너먼트 티켓 = PvP. 오프라인 재구현에서 삭제(CLAUDE.md §2-1)"),
    # 장비 귀속·부가옵션 배선(2026-07-29). 원작 근거 = docs/ref/porting/EquipBelongOption.md
    "item_disconnect": ("impl", "구드라의 지혜 = 장비 귀속 1회 해제. cave.gd `_unbind_equip` 이 소비한다"),
    "ginu_coin_green": ("impl", "기누의 동전(레어) = 부가옵션 재설정. cave.gd `_reroll_options` 가 소비한다"),
    "ginu_coin_yellow": ("impl", "기누의 동전(유니크) = 부가옵션 재설정. cave.gd `_reroll_options` 가 소비한다"),
    "ginu_coin_red": ("impl", "기누의 동전(에픽) = 부가옵션 재설정. cave.gd `_reroll_options` 가 소비한다"),
}

# ── 분류별 용도(그룹 공통) ──────────────────────────────────────────────────
# groups.csv `그룹 공통 용도` 를 가방에 그대로 쓰기 좋게 다듬은 것. 뜻은 바꾸지 않는다.
GROUP_USE = {
    "blessing": "드래곤 레벨업에 쓴다",
    "box": "열쇠로 열어 정해진 풀에서 랜덤 아이템을 얻는다",
    "buff": "탐험 보상(경험치·골드)을 늘리는 버프",
    "key": "상자류를 여는 데 쓴다",
    "level": "드래곤 레벨을 조정한다",
    "nest": "드래곤 삭제·보관·부화에 쓴다",
    "story": "스토리 진행 전용 — 퀘스트를 받아 탐험으로 모으고, 클리어하면 사라진다",
    "essence": "속성 정기. 드래곤 알 교환 등에 쓴다",
    "raid_shard": "레이드 산출 재화. 드래곤 알·상점 특수 품목과 교환한다",
    "map": "'보물지도' 시스템 전용",
    "memory_random": "해당 레벨의 **랜덤** 스킬 스크롤을 얻는다",
    "memory_select": "해당 레벨의 스킬 스크롤 중 **하나를 골라** 얻는다",
    "mix_book": "더미 아이템 — 원작에도 사용처가 없다",
    "dragon_egg": "상점 EGG 탭에서 다이아로 산다. 쓰면 그 드래곤의 알을 얻는다",
    "element_egg": "상점 EGG 탭에서 정기로 산다. 그 속성의 2~4성 알을 무작위로 얻는다",
    "gacha_egg": "상점 EGG 탭에서 다이아로 산다. 정해진 풀에서 드래곤 알을 무작위로 얻는다",
    "drink": "일정 턴 동안 능력치를 올리는 버프 물약",
    "feed": "드래곤 먹이",
    "heal": "탐험 중 줄어든 드래곤 체력을 회복시킨다",
    "alchemy": "점술집 연금술 재료",
    "awaken_mat": "우노의 두 던전에서 얻는다. 우노 연구소의 각성·장비 강화 등에 쓴다",
    "awaken_stone": "드래곤 각성 재료. 드래곤 성급에 맞는 마석이 필요하다",
    "craft": "발록 관련 제작 재료(알 제작·장신구 제작/구매)",
    "crystal": "유타칸 연구소의 결정 추출·생산으로 얻는다. 알 조합 등에 쓴다",
    "crystal_ex": "유타칸 연구소의 결정 추출·생산으로 얻는다. 알 조합 등에 쓴다",
    "jewel": "임프 상인(퐁)과의 거래에 쓰는 재화. 유타칸(밤) 탐험으로 모은다",
    "powder": "젬 분해로 얻는다. 점술집의 젬 기능에 쓴다",
    "shard": "모아서 해당 드래곤을 얻는 알조각",
    "spirit_stone": "엘리시움 레이드 산출. 알 강화·드래곤 강화에 쓴다",
    "stone_heart": "메탈타워 레이드 산출. 알 강화·드래곤 강화에 쓴다",
    "revive": "쓰러진 드래곤을 깨운다",
}

# ── 아이템별 용도(그룹에서 벗어나는 것) ─────────────────────────────────────
# 출처: groups.csv `설명` 칸(사용자 기입) + 위키 item.pdf.
ITEM_USE = {
    # consumable/nest — groups.csv 설명
    "holynest": "부화 전용. 한 번 사면 영구적으로 남는 축복받은 둥지",
    # consumable/qol — groups.csv 설명
    "dragon_namechange": "드래곤의 별명을 바꾼다",
    "namechange": "유저 닉네임을 바꾼다",
    "energy_drink": "탐험 피로도를 회복하던 아이템. 피로도가 사라진 뒤로는 더미",
    "item_disconnect": "장비에 걸린 귀속을 1회 푼다. 풀면 다른 드래곤에게 옮겨 낄 수 있다",
    "hero_auto1": "자동탐험을 켜 주던 기간제(1일) 아이템. 자동탐험이 기본이 된 뒤로는 더미",
    "hero_auto7": "자동탐험을 켜 주던 기간제(7일) 아이템. 자동탐험이 기본이 된 뒤로는 더미",
    # consumable/slot — groups.csv 설명
    "gem_init": "드래곤이 장착한 젬을 모두 없애고 슬롯을 비운다",
    "gemslot_change": "드래곤의 젬 슬롯 색을 전부 무작위로 바꾼다. 착용 중인 젬은 파괴된다",
    "skillslot_change": "드래곤의 스킬 슬롯 모양을 무작위로 바꾼다",
    "ginu_coin_green": "장비의 부가옵션 종류·수치를 다시 뽑는다. 장비와 레어도가 같아야 쓸 수 있다",
    "ginu_coin_red": "장비의 부가옵션 종류·수치를 다시 뽑는다. 장비와 레어도가 같아야 쓸 수 있다",
    "ginu_coin_yellow": "장비의 부가옵션 종류·수치를 다시 뽑는다. 장비와 레어도가 같아야 쓸 수 있다",
    # consumable/ticket — groups.csv 설명
    "portal": "혼돈의 틈새에 들어갈 때 소모한다",
    "ticket": "PvP 토너먼트 입장권 — 오프라인 재구현에서는 쓰지 않는다",
    # food/revive — 위키 item.pdf §2.2 + 우리 배선
    "elixir": "행동불능이 된 드래곤을 깨운다",
    # food/feed — groups.csv 설명(맘므/다르스 계열)
    # (개별로 적을 필요 없이 그룹 문구로 충분)
    # material/craft
    "balrog_core": "발록 알 제작·발록 장신구 제작/구매에 쓴다",
    # consumable/box — 유일하게 개봉표가 확정된 상자(위키 item.pdf §9.3)
    "jem_random": "열면 높은 등급의 일반 젬이 하나 나온다",
    # document/mix_book
    "mix_book": "더미 아이템 — 원작에도 사용처가 없다",
    "mix_perfectbook": "더미 아이템 — 원작에도 사용처가 없다",
    # egg/element_egg
    "mall_chaos_egg": "혼돈속성 알 — 원작에서 구현되지 않은 더미 데이터",
}

# 위키가 등급별 사용 레벨대를 못박은 회복 물약(item.pdf §2.2).
HEAL_LV = {"heal_potion1": "Lv.1~24(해치~해츨링)", "heal_potion2": "Lv.25~44(성체)",
           "heal_potion3": "Lv.45~50(오라 성체)"}


def main() -> int:
    dry = "--dry" in sys.argv
    groups = {r["분류"]: r for r in csv.DictReader(io.open(GROUPS, encoding="utf-8-sig"))}
    items = json.loads(ITEMS.read_text(encoding="utf-8"))

    # `_use_basis` 등 메타 키는 이 도구가 직접 써 넣은 것이라 두 번째 실행부터 섞여 들어온다.
    # 아이템이 아니므로 걸러낸다(예전엔 여기서 TypeError 로 죽었다 — 재실행 불가였다).
    rows = {k: v for k, v in items.items() if not k.startswith("_") and isinstance(v, dict)}

    # 시트가 커버하는 분류가 실제 items.json 분류와 맞는지 먼저 확인(오타·누락 조기 발견).
    have = {"%s/%s" % (v["category"], v["subcategory"]) for v in rows.values()}
    missing = sorted(have - set(groups))
    if missing:
        print("⚠️ groups.csv 에 없는 분류: %s" % missing)

    n_use = n_off = 0
    for key, v in rows.items():
        sub = v.get("subcategory", "")
        use = ITEM_USE.get(key) or GROUP_USE.get(sub, "")
        if key in HEAL_LV:
            use = "%s — %s 에게 쓴다" % (use, HEAL_LV[key])
        if use:
            if v.get("use") != use:
                n_use += 1
            v["use"] = use
        off = ITEM_OFFLINE.get(key)
        if off is None and sub in GROUP_OFFLINE:
            off = GROUP_OFFLINE[sub]
        if off and v.get("offline") != off[0]:
            v["offline"] = off[0]
            v["_offline_basis"] = off[1]
            n_off += 1

    items["_use_basis"] = (
        "각 아이템의 `use` = 무엇에 쓰이는가(가방 상세 표시용). 출처는 "
        "docs/input/items/groups.csv (사용자 기입 2026-07-29, 39분류 전부) + "
        "docs/ref/wiki/item.pdf. 빌드: scripts/tools/build_item_uses.py. "
        "`use` 는 표시 텍스트일 뿐 규칙·수치를 담지 않는다 — 그건 각 시스템의 data 파일 몫이다."
    )
    items["_offline_states"] = {
        "impl": "배선돼 동작한다",
        "todo": "용도는 알지만 그 기능이 아직 없다",
        "stub": "자리만 있다(상위 시스템 미구현)",
        "cut": "오프라인 재구현에서 삭제(CLAUDE.md §2-1)",
        "dummy": "**원작에서도 사용처가 없던 더미 아이템**(우리가 못 만든 게 아니다)",
    }

    if dry:
        print("(dry) use %d / offline %d 건 변경 예정" % (n_use, n_off))
        return 0
    ITEMS.write_text(json.dumps(items, ensure_ascii=False, indent=1), encoding="utf-8")
    total = sum(1 for k, v in items.items() if isinstance(v, dict) and v.get("use"))
    print("use 채움: %d 건 변경 / 전체 %d 종에 용도 있음" % (n_use, total))
    print("offline 재판정: %d 건" % n_off)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

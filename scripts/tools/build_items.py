"""아이템 마스터 데이터(data 계층) 빌드.

- 아이콘 변환: DV2/480/item/{food,egg,mtr,etc,doc,quest,spc}.img_plist
  -> assets/converted/item_<cat>/  (AtlasTexture .tres + _manifest.json)
- data/items.json 생성 (서버 DB 대체, 불변 마스터 데이터)

출처: docs/input/item_inventory.md (사용자 검수 완료) + docs/ref/wiki/item.pdf.
효과(effect) 수치는 역설계 대상(HARD RULE 6) → 전부 null/TODO, 전투·부화·육성 구현 시 채움.

⚠️ 이 스크립트는 items.json 을 **통째로 덮어쓴다** — 사용자 시트에서 온 `use`/`desc`/`name`
정정이 날아간다. 다시 돌렸다면 반드시 이어서 실행할 것:
    python scripts/tools/build_item_uses.py     # 용도(groups.csv)
    python scripts/tools/build_item_descs.py    # 설명·이름 정정(items.csv)

usage: python scripts/tools/build_items.py
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
import cocos_export

DRAGONS = "data/dragons.json"
OUT = "data/items.json"
ITEM_DIR = "DV2/480/item"
CATS = ["food", "egg", "mtr", "etc", "doc", "quest", "spc"]

# 자산 키 속성 토큰 -> 프로젝트 속성 표기 (water=aqua, ground=earth)
EL = {"ground": "earth", "water": "aqua", "fire": "fire", "wind": "wind",
      "light": "light", "dark": "dark", "holy": "holy", "chaos": "chaos",
      "shadow": "shadow"}
ELK = {"earth": "땅", "aqua": "물", "fire": "불", "wind": "바람", "light": "빛",
       "dark": "어둠", "holy": "신성", "chaos": "혼돈", "shadow": "그림자"}

items = {}


def icon_of(cat, base):
    return "item_%s/item_%s_%s" % (cat, cat, base)


def add(key, cat, name, category, subcategory, **kw):
    """cat = 아이콘 아틀라스(food/egg/mtr/etc/doc/quest/spc). category = 게임 분류."""
    e = {
        "name": name,
        "category": category,
        "subcategory": subcategory,
        "element": kw.get("element"),
        "icon": icon_of(cat, key),
        "stack": kw.get("stack", True),
        "effect": None,                 # TODO 역설계
        "offline": kw.get("offline", "impl"),
    }
    for opt in ("dragon_id", "tier", "size", "grade", "piece", "stage", "note"):
        if opt in kw:
            e[opt] = kw[opt]
    items[key] = e


def main():
    dragons = {d["id"]: d for d in json.load(open(DRAGONS, encoding="utf-8"))}

    # ---------------- food ----------------
    FEED = [
        ("food_ground_paopao_half", "팜피오 조각", "ground", "소"),
        ("food_ground_paopao", "팜피오", "ground", "대"),
        ("food_water_fly_pirania", "에므 치어", "water", "소"),
        ("food_water_pirania", "에므", "water", "대"),
        ("food_fire_chickenleg", "드블랑 다리", "fire", "소"),
        ("food_fire_chicken", "드블랑 통구이", "fire", "대"),
        ("food_wind_branch_yggdrasil", "양식 가르시아", "wind", "소"),
        ("food_wind_yggdrasil", "자연산 가르시아", "wind", "대"),
        ("food_light_lightmelon_piece", "파프노 조각", "light", "소"),
        ("food_light_lightmelon", "파프노팜", "light", "대"),
        ("food_dark_darkmelon_piece", "다르스 조각", "dark", "소"),
        ("food_dark_darkmelon", "다르스팜", "dark", "대"),
        ("food_holy_small_ginseng", "양식 게게바노", "holy", "소"),
        ("food_holy_big_ginseng", "자연산 게게바노", "holy", "대"),
        ("food_chaos_tadpole", "맘므치어", "chaos", "소"),
        ("food_chaos_toud", "맘므루구", "chaos", "대"),
        ("food_shadow_chocolate_piece", "초콜릿 조각", "shadow", "소"),
        ("food_shadow_chocolate", "초콜릿", "shadow", "대"),
    ]
    for key, name, tok, size in FEED:
        add(key, "food", name, "food", "feed", element=EL[tok], size=size)
    # 원본 자산 오타: 프레임명이 'food_chaos_tadpole,'(끝 쉼표) → 아이콘 경로 보정
    items["food_chaos_tadpole"]["icon"] = "item_food/item_food_food_chaos_tadpole,"

    for key, name, tier in [("heal_potion1", "회복물약", 1),
                            ("heal_potion2", "축복받은 회복물약", 2),
                            ("heal_potion3", "여신의 회복물약", 3)]:
        add(key, "food", name, "food", "heal", tier=tier)
    add("elixir", "food", "생명의 정수", "food", "revive", offline="stub")

    add("drink", "food", "자양강장제", "food", "drink", offline="todo")
    for pre, nm in [("att", "공격력"), ("def", "방어력"), ("hp", "체력"),
                    ("cri", "크리티컬"), ("miss", "회피"), ("prodef", "방어확률")]:
        for t in (1, 2, 3):
            add("%s_drink%d" % (pre, t), "food", "%s 물약 %d단계" % (nm, t),
                "food", "drink", tier=t, offline="todo")

    # ---------------- egg ----------------
    for tok in ["ground", "water", "fire", "wind", "light", "dark", "holy", "chaos"]:
        add("mall_%s_egg" % tok, "egg", "%s속성 드래곤알" % ELK[EL[tok]],
            "egg", "element_egg", element=EL[tok])
    add("mall_question_egg", "egg", "의문의 알", "egg", "gacha_egg")
    add("mall_question_egg2", "egg", "빛나는 의문의 알", "egg", "gacha_egg")
    # 특정 드래곤 알 (사용자 검수). back/snake = 추정.
    DEGG = [("mall_bagma_egg", 4021, False), ("mall_gaoron_egg", 4024, False),
            ("mall_jin_egg", 4022, False), ("mall_uchi_egg", 4027, False),
            ("mall_toly_egg", 4026, False), ("mall_ullr_egg", 4028, False),
            ("mall_sion_egg", 3006, False), ("mall_zephyros_egg", 4005, False),
            ("mall_tropheus_egg", 4012, False), ("mall_wybern_egg", 74, False),
            ("mall_haetai_egg", 75, False), ("mall_woods_egg", 4025, False),
            ("mall_darkpoll_egg", 175, False), ("mall_pang_egg", 4019, False),
            ("mall_jaryong_egg", 95, False), ("mall_black_egg", 34, False),
            ("mall_snake_egg", 69, True), ("mall_back_egg", 54, True)]
    for key, did, assumed in DEGG:
        dn = dragons[did]["name"]
        kw = {"dragon_id": did, "element": dragons[did].get("element")}
        if assumed:
            kw["note"] = "ASSUMPTION: 파일명만으로 미확정, 드래곤 id 추정"
        add(key, "egg", "%s의 알" % dn, "egg", "dragon_egg", **kw)
    # mall_question_egg3 / mall_monster_egg = 이미지 확인 전까지 보류(미수록)

    # ---------------- mtr (재료) ----------------
    CR = ["earth", "aqua", "fire", "wind", "light", "dark", "holy", "chaos", "shadow"]
    inv = {v: k for k, v in EL.items()}  # proj el -> ground식 토큰(food/egg/essence용)
    # ⚠️ crystal·gudrabox 아틀라스는 'earth' 토큰 사용(food/egg/essence는 'ground'). aqua만 'water'.
    ctok = lambda pe: "water" if pe == "aqua" else pe
    for pe in CR:
        add("crystal_%s" % ctok(pe), "mtr", "%s의 결정" % ELK[pe],
            "material", "crystal", element=pe)
    for pe in ["earth", "aqua", "fire", "wind", "light", "dark", "holy", "chaos"]:
        add("crystal2_%s" % ctok(pe), "mtr", "%s의 전용 결정" % ELK[pe],
            "material", "crystal_ex", element=pe)

    SP = ["조각난", "온전한", "완벽한", "완전무결한"]
    for i in range(4):
        add("stone_spirit%d" % (i + 1), "mtr", "%s 정령석" % SP[i],
            "material", "spirit_stone", tier=i + 1)
        add("stone_heart%d" % (i + 1), "mtr", "%s 스톤하트" % SP[i],
            "material", "stone_heart", tier=i + 1)
    add("anima", "mtr", "아니마", "material", "awaken_mat")
    add("bonner", "mtr", "보네르", "material", "awaken_mat")
    for s in (3, 4, 5, 6):
        add("evol_jewel_%d" % s, "mtr", "각성의 마석(%d성)" % s,
            "material", "awaken_stone", grade=s)

    # 제작(후순위 — 젬/연금 시스템 의존)
    add("att_powder", "mtr", "붉은 마법가루", "material", "powder", offline="todo")
    add("def_powder", "mtr", "푸른 마법가루", "material", "powder", offline="todo")
    add("hp_powder", "mtr", "노란 마법가루", "material", "powder", offline="todo")
    add("balrog_core", "mtr", "발록의 핵", "material", "craft", offline="stub")
    ALC = [("moderation", "절제"), ("wisdom", "지혜"), ("courage", "용기"),
           ("justice", "정의"), ("glory", "영광"), ("legend", "전설")]
    for k, nm in ALC:
        add("alchemy_%s" % k, "mtr", "%s의 용액" % nm, "material", "alchemy", offline="todo")
    add("alchemy_special", "mtr", "초월의 용액", "material", "alchemy", offline="todo")
    add("alchemy_platinum_01", "mtr", "샌즈의 눈물(10%)", "material", "alchemy", offline="todo")
    add("alchemy_platinum_02", "mtr", "샌즈의 눈물(20%)", "material", "alchemy", offline="todo")
    # 보석 4종 — 임프 상인(퐁) 거래 재화. 🟢 2026-08-04 `todo` → `impl`:
    #   수급처(임프 #160/#161 드랍, `data/monster_drops.json`)와 소비처(임프 상점,
    #   `scripts/ui/imp_shop.gd`)가 둘 다 배선돼 실제로 돌아간다 — 표기만 낡아 있었다
    #   (`test_imp_shop.gd` 의 "입수 가능 표시" 4건이 그걸 잡고 있었다).
    for k, nm in [("amethyst", "자수정"), ("emerald", "에메랄드"),
                  ("ruby", "루비"), ("sapphire", "사파이어")]:
        add("jewel_%s" % k, "mtr", nm, "material", "jewel", offline="impl")

    # 알조각 (7조각 조합)
    SHARD = {"janer": 4036, "nowaema": 4035, "lucifer": 3001, "holy": 3002,
             "rudra": 3039, "aton": 3040, "chaos": 3003}
    for code, did in SHARD.items():
        dn = dragons[did]["name"]
        for i in range(1, 8):
            add("%s_egg_%d" % (code, i), "mtr", "%s의 알조각 %d" % (dn, i),
                "material", "shard", dragon_id=did, piece=i)

    # ---------------- etc ----------------
    for pe in CR:
        tok = inv[pe]
        add("ele_%s" % tok, "etc", "%s의 정기" % ELK[pe],
            "currency", "essence", element=pe)
    for key, nm in [("bless_of_dragon", "드래곤의 축복"), ("bless_of_maia", "마이아의 축복"),
                    ("bless_of_dersa", "데르사의 축복"), ("bless_of_amor", "아모르의 축복")]:
        add(key, "etc", nm, "consumable", "blessing")
    add("level_down", "etc", "Lv -1", "consumable", "level")
    # Lv+1: 레벨업 화면(_lvup_item_button) + 가방 사용(_use_consumable) 양쪽에서 소모된다 → impl.
    add("level_up", "etc", "Lv +1", "consumable", "level")
    add("ascension", "etc", "드래곤의 승천", "consumable", "nest")
    add("bridle", "etc", "드래곤의 고삐", "consumable", "nest")
    # 슬롯 재부여 — 원작 문자열이 동작을 확정해 준다(2026-07-27 구현):
    #   `CaveBagMsg19`/`CaveToastMsg21` 잼 슬롯 랜덤 변경  → gemslot_change(샌즈의 비약)
    #   `CaveBagMsg20`/`CaveToastMsg22` 스킬 슬롯 랜덤 변경 → skillslot_change(다이즈의 호신부)
    #   `CaveToastMsg8` "드래곤의 젬 슬롯이 초기화되었습니다." → gem_init(장착 젬 전량 해제)
    add("gemslot_change", "etc", "샌즈의 비약", "consumable", "slot")
    add("skillslot_change", "etc", "다이즈의 호신부", "consumable", "slot")
    add("gem_init", "etc", "젬슬롯 초기화", "consumable", "slot")
    # slot_reset(슬롯 초기화)·기누의 동전 = 무엇을 초기화/소환하는지 근거가 없어 todo 유지.
    for key, nm in [("slot_reset", "슬롯 초기화"),
                    ("ginu_coin_green", "기누의 동전(레어)"), ("ginu_coin_yellow", "기누의 동전(유니크)"),
                    ("ginu_coin_red", "기누의 동전(에픽)")]:
        add(key, "etc", nm, "consumable", "slot", offline="todo")
    # 편의/버프
    add("energy_drink", "etc", "에너지 드링크", "consumable", "qol", offline="stub")
    add("hero_auto1", "etc", "기누의 약속(1일)", "consumable", "qol", offline="todo")
    add("hero_auto7", "etc", "기누의 약속(7일)", "consumable", "qol", offline="todo")
    for key, nm in [("expx2", "경험치 2배"), ("expx4", "경험치 4배"),
                    ("goldx2", "골드 2배"), ("goldx4", "골드 4배")]:
        add(key, "etc", nm, "consumable", "buff", offline="todo")
    add("portal", "etc", "고대 포탈", "consumable", "ticket", offline="stub")
    add("ticket", "etc", "토너먼트 티켓", "consumable", "ticket", offline="stub")
    add("dragon_namechange", "etc", "드래곤 이름변경", "consumable", "qol")
    add("namechange", "etc", "닉네임 변경", "consumable", "qol")
    add("item_disconnect", "etc", "함정 제거 키트", "consumable", "qol", offline="stub")
    # 상자/열쇠 (드롭 테이블 역설계 필요 → todo)
    for key, nm in [("key", "열쇠"), ("key_all", "만능 열쇠"), ("key_copper", "구리빛 열쇠"),
                    ("key_silver", "은빛 열쇠"), ("key_gold", "금빛 열쇠"), ("key_dark", "암흑 열쇠")]:
        add(key, "etc", nm, "consumable", "key", offline="todo")
    for key, nm in [("box", "비밀 상자"), ("box_dark", "어둠의 상자"), ("box_gold", "금상자"),
                    ("box_silver", "은상자"), ("magicbox", "봉인된 마법의 상자"),
                    ("stone_pocket", "유용한 돌 자루")]:
        add(key, "etc", nm, "consumable", "box", offline="todo")
    # 진귀한 보석 상자 = **젬 뽑기 상자**. 위키 item.pdf §9.3 에 수치가 확정돼 있다:
    #   "바루스에게 개당 15다이아, 10연속 뽑기는 125 다이아 … 높은 등급의 일반 젬을 뽑을 수 있지만"
    # 상점 '뽑기' 탭에서 다이아로 구매 → 가방에서 개봉(cave.gd _use_consumable "gembox").
    add("jem_random", "etc", "진귀한 보석 상자", "consumable", "box")
    for pe in CR:
        add("gudrabox_%s" % ctok(pe), "etc", "구드라의 상자(%s)" % ELK[pe],
            "consumable", "box", element=pe, offline="todo")
    # 레이드 재화 (멀티 의존 → stub)
    add("kasizclaw", "etc", "카시즈의 파편", "currency", "raid_shard", offline="stub")
    add("cronakscale", "etc", "크로낙의 파편", "currency", "raid_shard", offline="stub")

    # ---------------- doc (문서) ----------------
    for key, nm in [("map_seal", "봉인된 보물지도"),
                    ("map_elf_namal", "엘프 지역 지도(일반)"), ("map_elf_hero", "엘프 지역 지도(영웅)"),
                    ("map_dwarf_normal", "드워프 지역 지도(일반)"), ("map_dwarf_hero", "드워프 지역 지도(영웅)"),
                    ("map_utakan_nomal", "유타칸 지역 지도(일반)"), ("map_utakan_hero", "유타칸 지역 지도(영웅)")]:
        add(key, "doc", nm, "document", "map")
    add("mix_book", "doc", "신비한 조합서 책", "document", "mix_book")
    add("mix_perfectbook", "doc", "퍼펙트 도감", "document", "mix_book", offline="stub")
    for i in range(1, 6):
        add("eggmix%d" % i, "doc", "조합서 %d" % i, "document", "recipe")
    # scroll = 에자녹의 기억(랜덤), skillbook = 권능(선택)
    for i in range(1, 6):
        add("scroll_n%d" % i, "doc", "에자녹의 기억(%d레벨)" % i, "document", "memory_random")
    add("scroll_silver", "doc", "에자녹의 기억(실버)", "document", "memory_random")
    add("scroll_gold", "doc", "에자녹의 기억(골드)", "document", "memory_random")
    for i in range(1, 6):
        add("s_skillbook%d" % i, "doc", "에자녹의 권능(%d레벨)" % i, "document", "memory_select")
    # ⚫ `s_skillbook`(등급 없는 '에자녹의 권능', 아이템번호 453)은 **넣지 않는다** —
    #   원작 `ItemSkillSelectPopup::init` 의 레벨 계산은 `param_1 - 0x1c6`(454~458 = 1~5레벨)이라
    #   453 은 조건에 안 걸려 레벨이 0으로 남는다(data/skill_scrolls.json `_basis` 참조).
    #   즉 원작에서도 쓸 수 없던 구판 잔존 더미다 ⇒ 🟦사용자 확정 2026-07-31 **구현에서 제외**.
    #   아이콘(`item_doc/item_doc_s_skillbook`)은 남아 있으니 근거가 생기면 이 줄만 되살리면 된다.

    # ---------------- quest / spc ----------------
    add("quest_herb", "quest", "약초", "consumable", "story", offline="stub")
    add("stone", "quest", "마영석", "consumable", "story", offline="stub")
    add("stone2", "quest", "마법석", "consumable", "story", offline="stub")
    add("holynest", "spc", "축복받은 둥지", "consumable", "nest")

    # ============== 출력 ==============
    # 1) 아이콘 변환
    for cat in CATS:
        cocos_export.export(os.path.join(ITEM_DIR, cat + ".img_plist"), "item_" + cat)

    # 2) items.json
    ordered = {k: items[k] for k in sorted(items)}
    json.dump(ordered, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)

    # 요약
    from collections import Counter
    by_off = Counter(v["offline"] for v in items.values())
    by_cat = Counter(v["category"] for v in items.values())
    print("\nitems.json: %d items -> %s" % (len(items), OUT))
    print("  by offline:", dict(by_off))
    print("  by category:", dict(by_cat))


if __name__ == "__main__":
    main()

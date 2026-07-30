"""데이터 트랙 — 나무위키 젬 PDF → data/gems.json (전 젬 종류 × 전 티어).

유실된 서버 데이터(젬 종류별 티어 수치)가 위키에 표로 문서화돼 있다.
`docs/ref/wiki/gems.pdf`를 pymupdf로 텍스트 추출 → 절(§) 헤더로 젬 종류를 구분하고,
각 절의 "…올려준다." 줄에서 정수를 순서대로 뽑아 티어 배열을 만든다.

원작 클라 근거(값이 아니라 *구조*):
  - 젬 타입 코드 = `Item::getTypeDetail()` 문자열. Dragon.c 에 실재:
      일반  HP / ATT / DEF
      혼성  ATTHP / ATTDEF / HPATT / HPDEF / DEFATT / DEFHP
      소울  SOULHP / SOULATT / SOULDEF / SOULALL
    (`grep -o '"[A-Z][A-Z0-9_]*"' docs/ref/orig_code/decomp/Dragon.c`)
  - 젬 슬롯 = 3개. Dragon 오브젝트의 this+0x158 / 0x160 / 0x168 를
    getHpAdd/getAttAdd/getDefAdd 가 순서대로 훑는다(Dragon.c:1940~2050 등).
  - 소울젬의 % 성분은 `Item::getTypeParam(slot) % 1000` 으로 뽑는다
    (Dragon.c:1974). 즉 원작은 flat/pct 를 한 정수에 패킹했다. 우리는
    패킹하지 않고 필드를 나눠 둔다(같은 결과, 더 읽기 쉬움).

⚠️ 위키 서술은 검증 안 됨. 확인된 오탈자는 SECTIONS 의 stat 지정이 이긴다:
  - "공격의 젬" 1티어가 "체력을 7만큼"으로 적혀 있음 → 공격 7.
  - "체공젬" 1티어가 "체력을 36, 방어력을 4"로 적혀 있음 → 체력 36, 공격 4.
  숫자는 위키 그대로 두고 어느 스탯인지만 절 제목을 따른다.

사용:  python scripts/tools/build_gems.py            # data/gems.json 재생성
       python scripts/tools/build_gems.py --dry      # 파싱 결과만 출력
"""
from __future__ import annotations
import re, sys, json
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PDF = REPO / "docs" / "ref" / "wiki" / "gems.pdf"
OUT = REPO / "data" / "gems.json"

# 절 제목 → (원작 typeDetail 코드, 분류, 티어당 스탯키 순서)
# 스탯키: hp/att/def = flat, *_pct = %, cri/evd/blk = 부가 확률(%)
SECTIONS: list[tuple[str, str, str, list[str]]] = [
    ("체력의 젬",     "HP",      "normal", ["hp"]),
    ("공격의 젬",     "ATT",     "normal", ["att"]),
    ("방어의 젬",     "DEF",     "normal", ["def"]),
    ("체공젬",        "HPATT",   "hybrid", ["hp", "att"]),
    ("체방젬",        "HPDEF",   "hybrid", ["hp", "def"]),
    ("공체젬",        "ATTHP",   "hybrid", ["att", "hp"]),
    ("공방젬",        "ATTDEF",  "hybrid", ["att", "def"]),
    ("방체젬",        "DEFHP",   "hybrid", ["def", "hp"]),
    ("방공젬",        "DEFATT",  "hybrid", ["def", "att"]),
    # 샌즈의 젬 typeDetail = "ATTDEFHP" (원작 GemsPopup::setGemsList 의 memcmp 체인에 실재.
    # 이전엔 "ALL" 로 적었는데 원작에서 "ALL" 은 **슬롯 필터** 문자열이고 젬 코드가 아니다).
    ("샌즈의 젬",     "ATTDEFHP", "hybrid", ["hp", "att", "def"]),
    ("공격의 소울젬", "SOULATT", "soul",   ["att", "att_pct", "cri"]),
    ("방어의 소울젬", "SOULDEF", "soul",   ["def", "def_pct", "blk"]),
    ("체력의 소울젬", "SOULHP",  "soul",   ["hp", "hp_pct", "evd"]),
    ("샌즈의 소울젬", "SOULALL", "soul",   ["all_pct"]),
]

# 일반/혼성젬 19단계 모양 이름(위키 §2.1 "자갈→…→원형").
SHAPES = [
    "자갈", "돌멩이", "동그란 돌멩이",
    "삼각형", "삼각+구멍", "삼각+보석",
    "사각형", "사각+구멍", "사각+보석",
    "오각형", "오각+구멍", "오각+보석",
    "육각형", "육각+구멍", "육각+보석",
    "팔각형", "팔각+구멍", "팔각+보석",
    "원형",
]

# 위키 §2.2 "강화단계 / 소모되는 다이아량" — 강화 실패 복구 다이아(18단계).
REPAIR_DIA = {
    "짱돌": 1, "돌멩이": 2, "동그란 돌멩이": 3,
    "삼각젬": 4, "삼각구멍": 5, "삼각보석": 6,
    "사각젬": 7, "사각구멍": 8, "사각보석": 9,
    "오각젬": 10, "오각구멍": 11, "오각보석": 12,
    "육각젬": 13, "육각구멍": 14, "육각보석": 15,
    "팔각젬": 16, "팔각구멍": 17, "팔각보석": 18,
}

# 젬 슬롯 타입 — 원작 `Dragon::getGemType(slot)` 0..3 순서 그대로.
#   CaveScene::setDragonInfo 가 이 값으로 칸 배경색을 고른다(red/blue/yellow/white).
# 슬롯마다 넣을 수 있는 젬이 다르다 — 원작 문자열 `CaveGemEuqipMsg2`
#   "선택한 젬과 맞는 슬롯이 없습니다." 가 그 제약을 말한다.
# 허용 집합은 `GemsPopup::setGemsList` 의 memcmp 체인을 그대로 옮긴 것이다
#   (docs/ref/orig_code/decomp/GemsPopup.c — ALL:14종 / ATT:5종 / DEF:6종 / HP:6종).
# ⚠️ 원작 코드는 ATT 슬롯 분기에서만 SOULALL(샌즈의 소울젬) 비교가 빠져 있다(SOULATT 비교 후
#   곧바로 끝난다). DEF·HP 는 받으므로 **원작 버그/오타**로 판단 — 사용자 확정(2026-07-27)으로
#   ATT 칸도 SOULALL 을 받도록 정정했다. 원작 그대로로 되돌리려면 ATT 목록에서 "SOULALL" 만 빼면 된다.
SLOT_TYPES = ["ATT", "DEF", "HP", "ALL"]
SLOT_TYPE_KR = {"ATT": "공격", "DEF": "방어", "HP": "체력", "ALL": "만능"}
_ALL_CODES = [
    "ATT", "ATTDEF", "ATTHP", "DEF", "DEFATT", "DEFHP", "HP", "HPATT", "HPDEF",
    "ATTDEFHP", "SOULATT", "SOULDEF", "SOULHP", "SOULALL",
]
SLOT_ACCEPT = {
    "ALL": _ALL_CODES,
    "ATT": ["ATT", "ATTDEF", "ATTHP", "ATTDEFHP", "SOULATT", "SOULALL"],
    "DEF": ["DEF", "DEFATT", "DEFHP", "ATTDEFHP", "SOULDEF", "SOULALL"],
    "HP": ["HP", "HPATT", "HPDEF", "ATTDEFHP", "SOULHP", "SOULALL"],
}

# 위키 오타 정정 — 사용자 확정(2026-07-27). (젬 이름, 1-base 단계, 키) → 값
# 방어의 소울젬 10단계 방어율이 위키에 1%로 적혀 있는데 9단계(4%)·8단계(2%)보다 낮다.
# 다른 소울젬은 마지막 단계가 최대치(공격 5% · 체력 4%)이므로 오타로 판단, 사용자가 7% 로 확정.
TIER_OVERRIDES = {
    ("방어의 소울젬", 10, "blk"): 7,
}

# 위키 §2.2 용액표 — 혼성젬 강화용. points=[min,max] 또는 success_pct.
POTIONS = [
    {"name": "절제의 용액", "cost_dust_each": 1, "points": [1, 5]},
    {"name": "지혜의 용액", "cost_dust_each": 2, "points": [1, 10]},
    {"name": "용기의 용액", "cost_dust_each": 3, "points": [1, 25]},
    {"name": "정의의 용액", "cost_dust_each": 4, "points": [1, 50]},
    {"name": "초월의 용액", "cost_note": "13강 이상 젬 분해", "success_pct": 15},
]

# 위키 §3 소울젬 강화 비용(10단계). dust=젬가루, mat=발록 재료, core=발록의 핵.
SOUL_UPGRADE = [
    {"step": 1,  "gold": 1_000_000, "dust": 50},
    {"step": 2,  "gold":    50_000, "dust": 100},
    {"step": 3,  "gold":   100_000, "dust": 150},
    {"step": 4,  "gold":   200_000, "dust": 200},
    {"step": 5,  "gold":   300_000, "dust": 250},
    {"step": 6,  "gold":   400_000, "dust": 300},
    {"step": 7,  "gold":   500_000, "dust": 500},
    {"step": 8,  "gold":   700_000, "dust": 1000, "mat": 3},
    {"step": 9,  "gold":   900_000, "dust": 2000, "mat": 6, "core": 1},
    {"step": 10, "gold": 1_000_000, "dust": 3000, "mat": 9, "core": 2},
]

# 위키 §2.2 "승급시 …의 소울젬이 된다" — 혼성젬 → 소울젬 승급 대응.
PROMOTE = {
    "HPATT": "SOULHP", "HPDEF": "SOULHP",
    "ATTHP": "SOULATT", "ATTDEF": "SOULATT",
    "DEFHP": "SOULDEF", "DEFATT": "SOULDEF",
    "ATTDEFHP": "SOULALL",
}
PROMOTE_COST = {"gold": 1_000_000, "_source": "위키 §2.2 '승급하려면 100만골드와 소량의 젬가루'"}

VALUE_LINE = re.compile(r"올려준다")
INT = re.compile(r"\d+")


def read_text() -> str:
    import fitz  # pymupdf
    doc = fitz.open(PDF)
    return "\n".join(page.get_text() for page in doc)


def slice_sections(text: str) -> dict[str, list[str]]:
    """절 제목 줄 위치로 텍스트를 잘라 절별 줄 목록을 돌려준다."""
    lines = [ln.strip() for ln in text.splitlines()]
    # 목차에도 같은 제목이 나오므로 '마지막' 등장 위치들만 쓴다(본문이 뒤에 온다).
    starts: list[tuple[int, str]] = []
    for title, *_ in SECTIONS:
        idxs = [i for i, ln in enumerate(lines) if ln.endswith(title)]
        if not idxs:
            raise SystemExit(f"[build_gems] 절을 못 찾음: {title}")
        starts.append((idxs[-1], title))
    starts.sort()
    out: dict[str, list[str]] = {}
    for k, (i, title) in enumerate(starts):
        j = starts[k + 1][0] if k + 1 < len(starts) else len(lines)
        out[title] = lines[i + 1:j]
    return out


def parse_tiers(lines: list[str], keys: list[str], title: str) -> list[dict]:
    tiers: list[dict] = []
    for ln in lines:
        if not VALUE_LINE.search(ln):
            continue
        nums = [int(n) for n in INT.findall(ln)]
        if len(nums) != len(keys):
            print(f"  ! {title}: skip (nums={len(nums)}, want={len(keys)})", file=sys.stderr)
            continue
        tier = {}
        for key, val in zip(keys, nums):
            if key == "all_pct":       # 샌즈 소울젬: 체·공·방 모두 같은 %
                tier["hp_pct"] = val
                tier["att_pct"] = val
                tier["def_pct"] = val
            else:
                tier[key] = val
        for (t_name, t_step, t_key), t_val in TIER_OVERRIDES.items():
            if t_name == title and t_step == len(tiers) + 1:
                tier[t_key] = t_val
        tiers.append(tier)
    return tiers


def build() -> dict:
    text = read_text()
    sections = slice_sections(text)
    gems: dict[str, dict] = {}
    for title, code, category, keys in SECTIONS:
        tiers = parse_tiers(sections[title], keys, title)
        entry: dict = {
            "code": code,
            "category": category,
            "tiers": tiers,
        }
        if category != "soul":
            entry["shapes"] = SHAPES[:len(tiers)]
            if code in PROMOTE:
                entry["promote_to"] = PROMOTE[code]
        gems[title] = entry
        print(f"  {code:8s} {category:6s} tiers={len(tiers):2d}  {tiers[0]} .. {tiers[-1]}")
    return {
        "_source": (
            "나무위키 gems.pdf 전량 파싱(scripts/tools/build_gems.py). "
            "일반3 + 혼성6 + 샌즈1(각 19티어) + 소울4(각 10단계)."
        ),
        "_re_basis": (
            "젬 타입 코드/슬롯 수 = 원작 클라 복원. Item::getTypeDetail() 문자열 "
            "HP/ATT/DEF·ATTHP/ATTDEF/HPATT/HPDEF/DEFATT/DEFHP·SOULHP/SOULATT/SOULDEF/SOULALL "
            "이 docs/ref/orig_code/decomp/Dragon.c 에 실재하고, 젬 슬롯은 this+0x158/0x160/0x168 3칸. "
            "소울젬 %성분은 원작이 getTypeParam()%1000 으로 패킹(Dragon.c:1974) — 우리는 필드 분리."
        ),
        "_wiki_typos": [
            "공격의 젬 1티어가 '체력을 7만큼'으로 표기 → 절 제목대로 공격 7로 해석.",
            "체공젬 1티어가 '체력을 36, 방어력을 4'로 표기 → 절 제목대로 체력 36 / 공격 4로 해석.",
            "방어의 소울젬 10단계 blk가 1로 표기(8단계 2 · 9단계 4보다 낮다) → 위키 오타. "
            "사용자 확정(2026-07-27)으로 7 로 정정. TIER_OVERRIDES 참조.",
        ],
        "slots": 3,
        "slot_types": {
            "_source": (
                "원작 Dragon::getGemType(slot) 0=ATT 1=DEF 2=HP 3=ALL (CaveScene::setDragonInfo 가 "
                "이 값으로 gem_red/blue/yellow/white_bg 를 고른다). 허용 집합은 "
                "GemsPopup::setGemsList 의 memcmp 체인 그대로."
            ),
            "_re_basis": (
                "슬롯 타입 **값**(드래곤별 어느 칸이 무슨 색인가)은 서버 DB라 유실. "
                "사용자 확정(2026-07-27): 부화 시 칸마다 4종 중 랜덤 1종 부여, 이후 "
                "'샌즈의 비약'(items.json gemslot_change)으로 랜덤 재부여."
            ),
            "_asymmetry_note": (
                "원작 코드는 ATT 분기에만 SOULALL 비교가 없다(SOULATT 비교 후 종료). DEF·HP 는 "
                "받으므로 원작 오타로 판단 → 사용자 확정(2026-07-27)으로 ATT 도 SOULALL 을 받는다."
            ),
            "order": SLOT_TYPES,
            "kr": SLOT_TYPE_KR,
            "accept": SLOT_ACCEPT,
        },
        "stat_keys": {
            "hp": "체력(flat)", "att": "공격력(flat)", "def": "방어력(flat)",
            "hp_pct": "체력 %", "att_pct": "공격력 %", "def_pct": "방어력 %",
            "cri": "크리티컬 확률 %", "evd": "회피율 %", "blk": "방어(막기)율 %",
        },
        "gems": gems,
        "craft": {
            "_source": "위키 §2.2 — 혼성젬 제작: 공/방/체 가루 각 20개, 결과 종류 랜덤. 샌즈의 눈물 투입 시 샌즈젬 확률↑.",
            "hybrid_dust_each": 20,
            "sands_tear_item": "샌즈의 눈물",
        },
        "upgrade": {
            "_source": "위키 §2.2(혼성 강화/복구·용액) · §3(소울젬 강화 비용).",
            "potion_max_per_try": 5,
            "alchemy_point_overflow": 100,
            "_alchemy_note": (
                "연금술 포인트 총합이 100을 넘으면 0으로 초기화(위키 §2.2 + 사용자 확정 2026-07-27). "
                "원작 문자열 <AlchemyMsg11> 은 '성공률이 하락합니다' 라고 적지만 하락폭이 유실이라 "
                "사용자가 '하락 = 초기화(0%)' 로 확정했다."
            ),
            "success": {
                "_re_basis": (
                    "⚠️ ASSUMPTION — 강화 실패율은 위키에도 원작 문자열에도 없다(복구 다이아표만 있다). "
                    "사용자 확정(2026-07-27): '실패율은 나도 기억이 나지 않으니 assumption 으로 채우자'. "
                    "실패가 존재하는 근거는 <MagicWelcomeGem> '실패할 수도 있으니 신중하게 도전하세요!' "
                    "와 <MagicGemFail>, 그리고 자산 scene/magicshop/gem_fail·btn_gemrepair 다."
                ),
                "_formula": "성공률(%) = clamp(start - step×티어, floor, 100) + 연금포인트, 100 상한",
                "base_pct_start": 100,
                "step_pct": 5,
                "base_pct_soul_start": 90,
                "step_pct_soul": 7,
                "floor_pct": 10,
            },
            "potions": POTIONS,
            "repair_diamond": REPAIR_DIA,
            "soul_steps": SOUL_UPGRADE,
            "promote": PROMOTE_COST,
        },
    }


def main() -> None:
    data = build()
    if "--dry" in sys.argv:
        print(json.dumps(data, ensure_ascii=False, indent=2)[:2000])
        return
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    n = sum(len(g["tiers"]) for g in data["gems"].values())
    print(f"[build_gems] wrote {OUT.relative_to(REPO)}: {len(data['gems'])} gem types, {n} tiers")


if __name__ == "__main__":
    main()

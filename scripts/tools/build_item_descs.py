"""아이템 **설명**(`desc`) 채우기 — 사용자 시트 → data/items.json.

원작 근거
--------
아이템 설명은 원작에서 `Item::getComment()` 한 곳에서 나온다(서버 DB `info_item.comment`).
이 문자열을 쓰는 화면은 셋이고 전부 **같은 문자열**을 쓴다:

  · 구매/판매 창  `ItemDetailLayer::initWidget`  (ItemDetailLayer.c:12680)
        `CCLabelBMFontEx` 줄바꿈 폭 300pt · 앵커(0,1) · 길이 0xf0(240)자 초과 시 0.8배 축소
  · 가방 상세     `BagPopup::resetString`        (BagPopup.c:11254)
        `[장비효과 줄]\n[이름 줄]\n[comment]` 를 이어 붙여 **CCScrollView(높이 105)** 안의
        라벨에 `setStringWithColor` 로 넣는다 → 길면 스크롤된다
  · 사용 확인 팝업 `ItemCommentPopup::setDetailString` (ItemCommentPopup.c:1111)

수치가 아니라 **텍스트**라 서버와 함께 유실됐고, 사용자가 원작 지식으로 되살렸다
(`docs/input/items/items.csv` 의 `설명` 열, 2026-07-29 기입 완료 222종).

무엇을 쓰나
----------
1. `desc` — 그 아이템의 원작 설명문(한글). 구매 창·가방 상세에 그대로 나온다.
2. `name` — 시트가 이름을 고쳐 준 항목은 함께 반영한다. 우리가 자산 키에서 유추한 이름이
   틀린 경우가 있었다(`item_disconnect` 함정 제거 키트 → **구드라의 지혜**).

`desc` 는 표시용 텍스트다 — 규칙·수치를 담지 않는다(그건 각 시스템의 data 파일 몫).
`use`(scripts/tools/build_item_uses.py, 분류별 한 줄 용도)와는 별개 열이다.

usage: python scripts/tools/build_item_descs.py [--dry]
"""
from __future__ import annotations
import csv, io, json, re, sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SHEET = REPO / "docs/input/items/items.csv"
ITEMS = REPO / "data/items.json"
GEMS = REPO / "data/gems.json"
SCROLLS = REPO / "data/skill_scrolls.json"

# 윈도 콘솔 기본 코드페이지(cp949)가 이모지를 못 찍어 죽던 것 방지.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# 시트에는 있지만 **일부러 items.json 에 안 넣은** 아이템 — 경고 대상이 아니다.
# `s_skillbook` = 등급 없는 '에자녹의 권능'(원작 번호 453). 레벨이 0으로 남는 구판 더미라
# 🟦사용자 확정 2026-07-31 로 구현에서 뺐다(scripts/tools/build_items.py 의 같은 주석 참조).
SHEET_ONLY = {"s_skillbook"}


def clean(s: str) -> str:
    """시트 기입 흔들림만 정리한다 — 문장은 손대지 않는다."""
    s = s.replace(" ", " ").strip()
    s = re.sub(r"[ \t]+", " ", s)      # 연속 공백 1칸
    s = re.sub(r"\s+([.,])", r"\1", s)  # 마침표 앞 공백
    return s


# ─────────────────────────── 기호(플레이스홀더) 해석 ───────────────────────────
# 시트의 `설명` 열에는 사용자가 **일부러 비워 둔 자리**가 있다 —
#   `n`  = 그 아이템의 수치(연금포인트·조각 번호·성급·스킬 레벨…)
#   `~`  = 그 아이템의 속성/등급 이름
# 사용자 설명(2026-07-31): "AI 가 아이템별로 적절한 수치/속성을 넣도록 표기한 기호".
#
# ⚠️ 값을 **지어내지 않는다**(HARD RULE 6). 전부 이미 있는 데이터에서 끌어온다:
#   용액 연금포인트  → data/gems.json `upgrade.potions[].points`
#   샌즈의 눈물 확률 → data/gems.json `craft.sands_tear_items[].sands_bonus_pct`
#   스킬 스크롤 레벨 → data/skill_scrolls.json `scrolls[].levels`
#   조각 번호·성급   → 아이템 키 접미사(`aton_egg_3` · `evol_jewel_5`)
#   기누의 동전 등급 → 이름의 `(레어)/(에픽)/(유니크)`
#   속성 이름        → data/items.json `element`
# 🟦사용자 확정(2026-07-31): 치환은 **CSV 가 아니라 여기서** 한다. gems.json 수치를 튜닝하면
#   설명문이 저절로 따라오고, 같은 수치가 두 곳에 적혀 어긋나는 일이 없다.

ELEMENT_KR = {
    "fire": "불", "aqua": "물", "earth": "땅", "wind": "바람", "light": "빛",
    "dark": "어둠", "holy": "신성", "chaos": "혼돈", "shadow": "그림자",
}

# `jem_random`(진귀한 보석 상자) — 시트 문구가 구드라 상자("~~속성의 특수한 아이템")에서
# **잘못 복사**돼 있었다(속성과 무관한 아이템이다). 🟦사용자 확정 2026-07-31: 본래 기능을
# 추적해 설명문을 채운다. 기능 출처 = data/drops.json `box.jem_random`
# (categories=["normal"] · tier 9~14) → `Drops.roll_gem_box` 가 일반 젬 1개를 준다.
DESC_OVERRIDE = {
    "jem_random": "귀한 보석만 골라 봉인한 상자. 열면 잘 다듬어진 일반 젬 하나가 나온다. "
                  "무엇이 나올지 모르니 긴장하는 것이 좋을 지도...",
}


def _potion_points(gems: dict) -> dict:
    """아이템키 → 연금포인트 문구('1~25' / '25')."""
    out = {}
    for p in gems.get("upgrade", {}).get("potions", []):
        pts = p.get("points")
        if not pts:
            continue
        lo, hi = int(pts[0]), int(pts[1])
        out[str(p.get("item", ""))] = str(lo) if lo == hi else "%d~%d" % (lo, hi)
    return out


def _sands_bonus(gems: dict) -> dict:
    """아이템키 → 샌즈젬 확률 보너스(%)."""
    return {str(s.get("item", "")): str(int(s.get("sands_bonus_pct", 0)))
            for s in gems.get("craft", {}).get("sands_tear_items", [])}


def _scroll_levels(scrolls: dict) -> dict:
    """아이템키 → 스킬 레벨 문구('3' / '1~3')."""
    out = {}
    for k, v in scrolls.get("scrolls", {}).items():
        lv = [int(x) for x in v.get("levels", [])]
        if lv:
            out[k] = str(lv[0]) if len(lv) == 1 else "%d~%d" % (min(lv), max(lv))
    return out


def resolve(key: str, desc: str, item: dict, tbl: dict) -> str:
    """설명문의 `n`/`~` 자리를 그 아이템의 실제 값으로 채운다. 근거가 없으면 그대로 둔다."""
    # ── `n` = 수치 ────────────────────────────────────────────────────────────
    pts = tbl["points"].get(key)
    if pts:
        desc = desc.replace("연금포인트를 n", "연금포인트를 %s" % pts)
    sands = tbl["sands"].get(key)
    if sands:
        desc = desc.replace("확률을 n%", "확률을 %s%%" % sands)
    lv = tbl["levels"].get(key)
    if lv:
        desc = desc.replace("[레벨n 스킬]", "[레벨%s 스킬]" % lv)
        desc = desc.replace("n레벨", "%s레벨" % lv)
    m = re.search(r"_(\d+)$", key)          # 조각 `aton_egg_3` · 마석 `evol_jewel_5`
    if m:
        desc = re.sub(r"\bn(번째|성)", m.group(1) + r"\1", desc)
    # ── `~` = 속성/등급 이름 ──────────────────────────────────────────────────
    el = item.get("element")
    if isinstance(el, str) and el in ELEMENT_KR:
        desc = re.sub(r"~+", ELEMENT_KR[el], desc)   # `~~속성` 처럼 겹친 자리도 한 번에
    else:
        # 기누의 동전 — 등급이 **이름**에 실려 있다(`기누의 동전(레어)`).
        g = re.search(r"\(([^)]+)\)\s*$", str(item.get("name", "")))
        if g:
            desc = desc.replace("~등급", g.group(1) + " 등급")   # "에픽 등급의 장신구"
    return desc


# 치환하고도 남은 기호 = 근거를 못 찾은 자리. 조용히 넘기지 않고 경고한다.
LEFTOVER = re.compile(r"(?<![0-9A-Za-z가-힣])n(?=[0-9가-힣%])|~(?![0-9])")


def main() -> int:
    dry = "--dry" in sys.argv
    rows = list(csv.DictReader(io.open(SHEET, encoding="utf-8-sig")))
    items = json.loads(ITEMS.read_text(encoding="utf-8"))
    gems = json.loads(GEMS.read_text(encoding="utf-8"))
    scrolls = json.loads(SCROLLS.read_text(encoding="utf-8"))
    tbl = {"points": _potion_points(gems), "sands": _sands_bonus(gems),
           "levels": _scroll_levels(scrolls)}

    n_desc = n_name = n_fix = 0
    unknown = []
    leftover = []
    for r in rows:
        key = r.get("id", "").strip()
        if not key:
            continue
        v = items.get(key)
        if not isinstance(v, dict):
            if key not in SHEET_ONLY:
                unknown.append(key)
            continue
        desc = clean(r.get("설명", ""))
        if key in DESC_OVERRIDE:
            desc = DESC_OVERRIDE[key]
        elif desc:
            fixed = resolve(key, desc, v, tbl)
            if fixed != desc:
                n_fix += 1
                desc = fixed
            if LEFTOVER.search(desc):
                leftover.append(key)
        if desc and v.get("desc") != desc:
            v["desc"] = desc
            n_desc += 1
        name = clean(r.get("이름", ""))
        if name and v.get("name") != name:
            print("  이름 정정: %-20s %s → %s" % (key, v.get("name"), name))
            v["name"] = name
            n_name += 1

    if unknown:
        print("⚠️ items.json 에 없는 id: %s" % unknown)
    if leftover:
        print("⚠️ 기호가 남은 설명(값의 근거를 못 찾음) %d 종: %s"
              % (len(leftover), ", ".join(leftover)))

    real = [k for k, v in items.items() if isinstance(v, dict) and not k.startswith("_")]
    miss = sorted(k for k in real if not items[k].get("desc"))
    items["_desc_basis"] = (
        "각 아이템의 `desc` = 원작 아이템 설명문(원작 `Item::getComment()` / 서버 "
        "info_item.comment 에 해당). 서버와 함께 유실돼 사용자가 원작 지식으로 복원했다 — "
        "출처 docs/input/items/items.csv `설명` 열(2026-07-29). 빌드: "
        "scripts/tools/build_item_descs.py. 표시처는 상점 구매/판매 창(원작 ItemDetailLayer)과 "
        "가방 상세(원작 BagPopup::resetString) 두 곳. `desc` 는 표시 텍스트일 뿐 "
        "규칙·수치를 담지 않는다 — 시트의 `n`/`~` 자리는 빌더가 각 시스템의 data 파일"
        "(gems.json 용액 포인트·샌즈 보너스, skill_scrolls.json 레벨, items.json element)에서 "
        "읽어 채운다. 즉 수치의 단일 출처는 여전히 그 시스템이고 설명문은 그것을 비출 뿐이다."
    )

    if dry:
        print("(dry) desc %d 건 / name %d 건 변경 예정" % (n_desc, n_name))
    else:
        ITEMS.write_text(json.dumps(items, ensure_ascii=False, indent=1), encoding="utf-8")
        print("desc 채움: %d 건 변경 (기호 해석 %d 건)" % (n_desc, n_fix))
        print("name 정정: %d 건" % n_name)
    print("설명 있음 %d / 전체 %d 종  (미기입 %d: %s)"
          % (len(real) - len(miss), len(real), len(miss), ", ".join(miss)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

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


def clean(s: str) -> str:
    """시트 기입 흔들림만 정리한다 — 문장은 손대지 않는다."""
    s = s.replace(" ", " ").strip()
    s = re.sub(r"[ \t]+", " ", s)      # 연속 공백 1칸
    s = re.sub(r"\s+([.,])", r"\1", s)  # 마침표 앞 공백
    return s


def main() -> int:
    dry = "--dry" in sys.argv
    rows = list(csv.DictReader(io.open(SHEET, encoding="utf-8-sig")))
    items = json.loads(ITEMS.read_text(encoding="utf-8"))

    n_desc = n_name = 0
    unknown = []
    for r in rows:
        key = r.get("id", "").strip()
        if not key:
            continue
        v = items.get(key)
        if not isinstance(v, dict):
            unknown.append(key)
            continue
        desc = clean(r.get("설명", ""))
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

    real = [k for k, v in items.items() if isinstance(v, dict) and not k.startswith("_")]
    miss = sorted(k for k in real if not items[k].get("desc"))
    items["_desc_basis"] = (
        "각 아이템의 `desc` = 원작 아이템 설명문(원작 `Item::getComment()` / 서버 "
        "info_item.comment 에 해당). 서버와 함께 유실돼 사용자가 원작 지식으로 복원했다 — "
        "출처 docs/input/items/items.csv `설명` 열(2026-07-29). 빌드: "
        "scripts/tools/build_item_descs.py. 표시처는 상점 구매/판매 창(원작 ItemDetailLayer)과 "
        "가방 상세(원작 BagPopup::resetString) 두 곳. `desc` 는 표시 텍스트일 뿐 "
        "규칙·수치를 담지 않는다."
    )

    if dry:
        print("(dry) desc %d 건 / name %d 건 변경 예정" % (n_desc, n_name))
    else:
        ITEMS.write_text(json.dumps(items, ensure_ascii=False, indent=1), encoding="utf-8")
        print("desc 채움: %d 건 변경" % n_desc)
        print("name 정정: %d 건" % n_name)
    print("설명 있음 %d / 전체 %d 종  (미기입 %d: %s)"
          % (len(real) - len(miss), len(real), len(miss), ", ".join(miss)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

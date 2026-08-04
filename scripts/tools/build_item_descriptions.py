#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""장비/젬 사용자 설명 시트 생성 및 게임 데이터 반영.

    python scripts/tools/build_item_descriptions.py
        현재 장비 카탈로그 + 젬 공유분류 5행으로 CSV를 동기화한다.
        이미 사용자가 적은 설명은 (종류, 키) 기준으로 보존한다.

    python scripts/tools/build_item_descriptions.py --apply
        CSV의 설명을 data/item_descriptions.json으로 반영한다.

CSV는 Excel에서 바로 열리는 UTF-8 BOM 형식이다. 장비는 카탈로그 키별 설명을,
젬은 일반/혼성/소울/샌즈/샌즈 소울 5개 분류별 공유 설명을 한 번만 적는다.
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parents[2]
CSV_PATH = ROOT / "docs" / "input" / "sheets" / "item_descriptions.csv"
JSON_PATH = ROOT / "data" / "item_descriptions.json"
EQUIPMENT_PATH = ROOT / "data" / "equipment.json"

FIELDS = ["종류", "키", "카테고리", "표시명", "설명(기입)"]
GEM_ROWS = [
    ("normal", "일반 젬"),
    ("hybrid", "혼성 젬"),
    ("soul", "소울 젬"),
    ("sands", "샌즈의 젬"),
    ("sands_soul", "샌즈의 소울젬"),
]


def equipment_rows(table: dict) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []

    def add(key: str, category: str, name: str) -> None:
        rows.append({"종류": "장비", "키": key, "카테고리": category,
                     "표시명": name, "설명(기입)": ""})

    for kind, spec in table.get("basic", {}).items():
        for grade in spec.get("grades", []):
            add(f"basic:{kind}:{int(grade['grade'])}", "일반장비", str(grade["name"]))
    for item in table.get("event", []):
        if item.get("implemented", True):
            add(f"event:{item['name']}", "일반장비", str(item["name"]))
    for family, family_def in table.get("special", {}).items():
        if not family_def.get("implemented", True):
            continue
        for item in family_def.get("items", []):
            add(f"special:{family}:{item['name']}", "특수장비", str(item["name"]))
    for item in table.get("exclusive", {}).get("list", []):
        if item.get("implemented", False):
            add(f"exclusive:{item.get('name', '')}", "전용장비", str(item.get("name", "")))
    artifacts = table.get("artifacts", {})
    grades = artifacts.get("grades", [])
    for item in artifacts.get("types", []):
        for grade_index, grade_name in enumerate(grades):
            name = f"{grade_name} {item['name']}"
            add(f"artifact:{item['name']}:{grade_index}", "아티팩트", name)

    order = {"전용장비": 0, "특수장비": 1, "일반장비": 2, "아티팩트": 3}
    rows.sort(key=lambda row: (order[row["카테고리"]], row["표시명"], row["키"]))
    return rows


def expected_rows() -> list[dict[str, str]]:
    table = json.loads(EQUIPMENT_PATH.read_text(encoding="utf-8"))
    rows = equipment_rows(table)
    rows.extend({"종류": "젬", "키": key, "카테고리": label,
                 "표시명": f"{label} 공통 설명", "설명(기입)": ""}
                for key, label in GEM_ROWS)
    return rows


def read_existing() -> dict[tuple[str, str], str]:
    if not CSV_PATH.exists():
        return {}
    with CSV_PATH.open(encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        return {(str(row.get("종류", "")).strip(), str(row.get("키", "")).strip()):
                str(row.get("설명(기입)", "")) for row in reader}


def sync() -> int:
    previous = read_existing()
    rows = expected_rows()
    preserved = 0
    for row in rows:
        key = (row["종류"], row["키"])
        if key in previous:
            row["설명(기입)"] = previous[key]
            preserved += int(bool(previous[key].strip()))
    CSV_PATH.parent.mkdir(parents=True, exist_ok=True)
    with CSV_PATH.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    equip_count = sum(row["종류"] == "장비" for row in rows)
    print(f"시트 동기화: {CSV_PATH.relative_to(ROOT)}")
    print(f"  장비 {equip_count}행 + 젬 공유분류 {len(GEM_ROWS)}행 · 작성 설명 보존 {preserved}칸")
    return 0


def apply() -> int:
    if not CSV_PATH.exists():
        print("설명 CSV가 없다. 먼저 인자 없이 실행해 생성하세요.", file=sys.stderr)
        return 1
    with CSV_PATH.open(encoding="utf-8-sig", newline="") as stream:
        rows = list(csv.DictReader(stream))
    expected = {(row["종류"], row["키"]) for row in expected_rows()}
    seen: set[tuple[str, str]] = set()
    equipment: dict[str, str] = {}
    gem_categories: dict[str, str] = {}
    errors: list[str] = []
    for line_no, row in enumerate(rows, start=2):
        kind = str(row.get("종류", "")).strip()
        key = str(row.get("키", "")).strip()
        identity = (kind, key)
        if identity in seen:
            errors.append(f"{line_no}행: 중복 키 {kind}/{key}")
            continue
        seen.add(identity)
        desc = str(row.get("설명(기입)", "")).strip()
        if kind == "장비":
            equipment[key] = desc
        elif kind == "젬":
            gem_categories[key] = desc
        else:
            errors.append(f"{line_no}행: 종류는 장비 또는 젬이어야 함: {kind}")
    missing = sorted(expected - seen)
    if missing:
        errors.append("필수 행 누락: " + ", ".join(f"{kind}/{key}" for kind, key in missing[:10]))
    if errors:
        print("CSV 반영 실패:", *errors, sep="\n  ", file=sys.stderr)
        return 1
    doc = {
        "_source": "docs/input/sheets/item_descriptions.csv 사용자 작성. build_item_descriptions.py --apply.",
        "_gem_note": "normal/hybrid/soul/sands/sands_soul 5개 설명을 같은 분류의 모든 티어가 공유한다.",
        "equipment": equipment,
        "gem_categories": gem_categories,
    }
    JSON_PATH.write_text(json.dumps(doc, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    filled_equip = sum(bool(value) for value in equipment.values())
    filled_gem = sum(bool(value) for value in gem_categories.values())
    print(f"게임 데이터 반영: {JSON_PATH.relative_to(ROOT)}")
    print(f"  작성 완료 장비 {filled_equip}/{len(equipment)} · 젬 분류 {filled_gem}/{len(gem_categories)}")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="CSV 설명을 게임 JSON으로 반영")
    args = parser.parse_args()
    sys.exit(apply() if args.apply else sync())

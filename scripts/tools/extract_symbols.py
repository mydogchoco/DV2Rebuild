"""libgame.so 심볼 → 시스템별 클래스/메서드 지도(재구현 청사진).

출력: docs/ref/design/reverse_engineering.md 의 "부록 A. 심볼 지도" 섹션용 마크다운.
Cocos2d-x/STL/rapidjson 등 엔진·표준 라이브러리 잡음은 걸러내고, 게임 고유 클래스만
시스템 카테고리로 묶어 메서드 목록을 낸다.

사용:  python scripts/tools/extract_symbols.py [so경로] > docs/ref/orig_code/symbol_map.md
"""
from __future__ import annotations
import sys
from collections import defaultdict
from so_reader import ELF, demangle, DEFAULT_SO

# 시스템 카테고리: (표시명, 클래스명에 포함되면 매칭되는 키워드들)
# 위에서부터 먼저 매칭 — 순서가 우선순위.
CATEGORIES: list[tuple[str, tuple[str, ...]]] = [
    ("전투/전투연출 (Battle/Fight)", ("Battle", "Fight", "Ultimate", "MapAttack", "Skill", "Damage", "TeamBuff", "Crest")),
    ("모험/스테이지 (Adventure)", ("Adventure", "Field", "Stage", "Map", "Mission")),
    ("레이드/원정 (Raid/Expedition)", ("Raid", "Expedition", "Exped", "Dwarf", "WorldRaid", "Flame")),
    ("드래곤 코어 (Dragon)", ("Dragon", "Aura", "Book", "Race")),
    ("알/부화/교배/조합 (Egg/Breed/Combine)", ("Egg", "Breed", "Mate", "Combine", "Hatch", "Cave")),
    ("진화/각성/강화 (Evolve/Enchant)", ("Enchant", "Evolv", "Awak", "Limit", "Seal", "Potential", "Amor")),
    ("가챠/상점/재화 (Gacha/Shop)", ("Gacha", "Shop", "Store", "Buy", "Charge", "Merchant", "Box")),
    ("아이템/인벤 (Item)", ("Item", "Inven", "Bag", "Gem", "Equip", "Recipe")),
    ("몬스터 (Monster)", ("Monster", "Enemy", "Boss")),
    ("월드/마을/둥지 (Town/World)", ("Town", "World", "Nest", "Village", "Home")),
    ("매니저/코어 (Manager/Core)", ("Manager", "GameData", "UserData", "Save", "Json", "Network", "Http", "Server")),
]

# 이 접두/키워드가 클래스 경로에 있으면 게임 로직이 아니라 엔진/라이브러리 → 제외
ENGINE_PREFIXES = ("std", "__ndk1", "__cxx", "rapidjson", "google", "spine", "boost")
ENGINE_CLASS_HINTS = ("CC", "extension", "network", "ui::", "__")


def is_engine(sym) -> bool:
    if not sym.namespaces:
        return True
    top = sym.namespaces[0]
    if top in ENGINE_PREFIXES:
        return True
    path = sym.full
    # cocos2d 네임스페이스라도 게임 고유 클래스는 남긴다. 순수 엔진 클래스만 제외.
    for h in ENGINE_CLASS_HINTS:
        if h in path:
            return True
    return False


def categorize(cls: str) -> str | None:
    for label, keys in CATEGORIES:
        if any(k in cls for k in keys):
            return label
    return None


def main():
    # Windows 기본 cp949 → UTF-8 강제(한글/em-dash 출력)
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    so = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SO
    elf = ELF(so)
    names = elf.dynsym_names()

    # 클래스 -> set(메서드)  (카테고리 매칭된 게임 클래스만)
    cats: dict[str, dict[str, set[str]]] = defaultdict(lambda: defaultdict(set))
    game_classes: set[str] = set()
    undemangled = 0
    for raw in names:
        sym = demangle(raw)
        if sym is None:
            undemangled += 1
            continue
        if is_engine(sym):
            continue
        # cocos2d:: 네임스페이스 접두는 표시상 제거(가독성)
        ns = sym.namespaces
        if ns and ns[0] == "cocos2d":
            ns = ns[1:]
        cls = "::".join(ns) if ns else sym.member
        cat = categorize(cls)
        if cat is None:
            continue
        game_classes.add(cls)
        member = sym.member
        # 소멸자/생성자/vtable 잡음 축소: 대표만
        cats[cat][cls].add(member)

    # 마크다운 출력
    out = []
    out.append("<!-- 자동생성: scripts/tools/extract_symbols.py — 원본 libgame.so 심볼 기반. 수기수정 금지. -->")
    out.append(f"# 부록 A. 심볼 지도 (재구현 청사진)\n")
    out.append(f"- 원본: `{so}` (스트립 안 됨)")
    out.append(f"- 동적 심볼 총 {len(names):,}개 중 게임 고유 클래스 {len(game_classes):,}개 추출\n")
    out.append("> 각 클래스는 원작의 실제 구현 단위다. 메서드 이름이 곧 '무엇을 구현해야 하는지'의 목록.\n")

    for label, _ in CATEGORIES:
        classes = cats.get(label)
        if not classes:
            continue
        out.append(f"\n## {label}\n")
        for cls in sorted(classes):
            methods = sorted(m for m in classes[cls]
                             if not m.startswith("~") and m != cls)  # 소멸자/생성자 제외
            if not methods:
                methods_str = "_(생성/소멸자만)_"
            else:
                shown = methods[:40]
                methods_str = ", ".join(f"`{m}`" for m in shown)
                if len(methods) > 40:
                    methods_str += f" _(+{len(methods)-40} more)_"
            out.append(f"### `{cls}` ({len(methods)} methods)")
            out.append(methods_str + "\n")

    sys.stdout.write("\n".join(out))
    sys.stderr.write(
        f"\n[extract_symbols] 게임 클래스 {len(game_classes)}개, "
        f"디맹글 실패 {undemangled}개(주로 치환/템플릿 심볼)\n"
    )


if __name__ == "__main__":
    main()
